`include "config_pkg.sv"
`include "usb_packet_pkg.sv"
`include "usb_ep_pkg.sv"
`include "util_macros.sv"

// USB Protocol Engine (PE)
module usb_pe #(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk12_i,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,

    // Timeout module
    output logic readTimerRst_o,
    input logic packetWaitTimeout_i,

    // State information
    input logic txDoneSending_i,
    output logic isSendingPhase_o,

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk12_i!
    output logic rxAcceptNewData_o,
    input logic [7:0] rxData_i,
    input logic rxIsLastByte_i,
    input logic rxDataValid_i,
    input logic keepPacket_i,

    // Data Transmit Interface: synced with clk12_i!
    output logic txReqSendPacket_o,
    output logic txDataValid_o,
    output logic txIsLastByte_o,
    output logic [7:0] txData_o,
    input logic txAcceptNewData_i,

    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    input logic [ENDPOINTS-2:0] EP_IN_popTransDone_i,
    input logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_IN_popData_i,
    output logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o,
    output logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o,

    input logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i,
    input logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_OUT_dataValid_i,
    input logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i,
    output logic [ENDPOINTS-2:0] EP_OUT_full_o
);

//====================================================================================
//===================================Endpoint logic===================================
//====================================================================================

    localparam EP_SELECT_WID = $clog2(ENDPOINTS);
    logic [EP_SELECT_WID-1:0] epSelect;
    logic [1:0] upperTransStartPID;
    logic gotTransStartPacket;
    logic isHostIn;
    // Status bit that indicated whether the next byte is the PID or actual data
    // This information can be simply obtained by watching gotTransStartPacket_i
    // but as this is likely needed for IN endpoints, the logic was centralized
    // to safe resources!
    logic byteIsData, nextByteIsData;

    // Used for received data
    logic fillTransDone;
    logic fillTransSuccess;
    logic EP_WRITE_EN;
    logic [8-1:0] wData;
    logic writeFifoFull;

    // Used for data to be output
    logic popTransDone;
    logic popTransSuccess;
    logic EP_READ_EN;
    logic readDataAvailable;
    logic readIsLastPacketByte;
    logic [8-1:0] rData;
    logic epResponseValid;
    logic epResponseIsHandshakePID;
    logic [1:0] epResponsePacketID;
    logic resetDataToggle;

    logic [ENDPOINTS-1:0] EP_IN_full;

    logic [ENDPOINTS-1:0] EP_OUT_dataAvailable;
    logic [ENDPOINTS-1:0] EP_OUT_isLastPacketByte;
    logic [8*ENDPOINTS - 1:0] EP_OUT_dataOut;

    logic [ENDPOINTS-1:0] EP_respValid;
    // If epRespHandshakePID == 1'b1 then epRespPacketID is expected to be for a handshake, otherwise a DATA pid is expected
    logic [ENDPOINTS-1:0] EP_respHandshakePID;
    logic [2*ENDPOINTS - 1:0] EP_respPacketID;

    always_comb begin
        // Set this bit as soon as we have a handshake -> we skipped PID
        nextByteIsData = byteIsData;

        // A new transaction started
        if (gotTransStartPacket) begin
            // Ignore the first byte which is the PID / ignore all data if it is not a device request, we do not expect any input!
            nextByteIsData = 1'b0;
        end else if (!byteIsData && EP_WRITE_EN) begin
            // TODO EP_WRITE_EN is basically the signal for an handshake... but might change in the future!
            // Once we have skipped the PID we have data bytes!
            nextByteIsData = 1'b1;
        end
    end
    always_ff @(posedge clk12_i) begin
        byteIsData <= nextByteIsData;
    end

    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(8)) rDataMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_dataOut),
        .data_o(rData)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) fifoFullMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_IN_full),
        .data_o(writeFifoFull)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) readDataAvailableMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_dataAvailable),
        .data_o(readDataAvailable)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) readIsLastPacketByteMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_isLastPacketByte),
        .data_o(readIsLastPacketByte)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) responseValidMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respValid),
        .data_o(epResponseValid)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) responseIsHandshakePIDMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respHandshakePID),
        .data_o(epResponseIsHandshakePID)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(2)) responsePacketIDMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respPacketID),
        .data_o(epResponsePacketID)
    );

    `define CREATE_EP_CASE(x)                                               \
        x: `EP_``x``_MODULE(epConfig) epX (                                 \
            .clk12_i(clk12_i),                                              \
            .gotTransStartPacket_i(gotTransStartPacket && isEpSelected),    \
            .isHostIn_i(isHostIn),                                          \
            .transStartTokenID_i(upperTransStartPID),                       \
            .byteIsData_i(byteIsData),                                      \
            .deviceConf_i(deviceConf),                                      \
            .resetDataToggle_i(resetDataToggle),                            \
                                                                            \
            /* Device IN interface */                                       \
            .EP_IN_fillTransDone_i(fillTransDone),                          \
            .EP_IN_fillTransSuccess_i(fillTransSuccess),                    \
            .EP_IN_dataValid_i(EP_WRITE_EN && isEpSelected),                \
            .EP_IN_data_i(wData),                                           \
            .EP_IN_full_o(EP_IN_full[x]),                                   \
                                                                            \
            .EP_IN_popTransDone_i(EP_IN_popTransDone_i[x-1]),               \
            .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i[x-1]),         \
            .EP_IN_popData_i(EP_IN_popData_i[x-1]),                         \
            .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o[x-1]),             \
            .EP_IN_data_o(EP_IN_data_o[(x-1) * 8 +: 8]),                    \
                                                                            \
            /* Device OUT interface */                                      \
            .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i[x-1]),           \
            .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i[x-1]),     \
            .EP_OUT_dataValid_i(EP_OUT_dataValid_i[x-1]),                   \
            .EP_OUT_data_i(EP_OUT_data_i[(x-1) * 8 +: 8]),                  \
            .EP_OUT_full_o(EP_OUT_full_o[x-1]),                             \
                                                                            \
            .EP_OUT_popTransDone_i(popTransDone),                           \
            .EP_OUT_popTransSuccess_i(popTransSuccess),                     \
            .EP_OUT_popData_i(EP_READ_EN && isEpSelected),                  \
            .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[x]),               \
            .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[x]),         \
            .EP_OUT_data_o(EP_OUT_dataOut[x * 8 +: 8]),                     \
                                                                            \
            .respValid_o(EP_respValid[x]),                                  \
            .respHandshakePID_o(EP_respHandshakePID[x]),                    \
            .respPacketID_o(EP_respPacketID[x * 2 +: 2])                    \
        )


    localparam USB_DEV_ADDR_WID = 7;
    logic [USB_DEV_ADDR_WID-1:0] deviceAddr;
    localparam USB_DEV_CONF_WID = 8;
    logic [USB_DEV_CONF_WID-1:0] deviceConf;
    generate

        // Endpoint 0 has its own implementation as it has to handle some unique requests!
        logic isEp0Selected;
        assign isEp0Selected = epSelect == 0;
        `EP_0_MODULE(USB_DEV_ADDR_WID, USB_DEV_CONF_WID, USB_DEV_EP_CONF) ep0 (
            .clk12_i(clk12_i),

            // Endpoint 0 handles the decice state!
            .usbResetDetected_i(usbResetDetected_i),
            .ackUsbResetDetect_o(ackUsbResetDetect_o),
            .deviceAddr_o(deviceAddr),
            .deviceConf_o(deviceConf),
            .resetDataToggle_o(resetDataToggle),

            .transStartTokenID_i(upperTransStartPID),
            .gotTransStartPacket_i(gotTransStartPacket && isEp0Selected),
            .byteIsData_i(byteIsData),

            // Device IN interface
            .EP_IN_fillTransDone_i(fillTransDone),
            .EP_IN_fillTransSuccess_i(fillTransSuccess),
            .EP_IN_dataValid_i(EP_WRITE_EN && isEp0Selected),
            .EP_IN_data_i(wData),
            .EP_IN_full_o(EP_IN_full[0]),

            /*
            .EP_IN_popTransDone_i(EP_IN_popTransDone_i[0]),
            .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i[0]),
            .EP_IN_popData_i(EP_IN_popData_i[0]),
            .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o[0]),
            .EP_IN_data_o(EP_IN_data_o[0 * 8 +: 8]),
            */

            // Device OUT interface
            /*
            .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i[0]),
            .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i[0]),
            .EP_OUT_dataValid_i(EP_OUT_dataValid_i[0]),
            .EP_OUT_data_i(EP_OUT_data_i[0 * 8 +: 8]),
            .EP_OUT_full_o(EP_OUT_full_o[0]),
            */

            .EP_OUT_popTransDone_i(popTransDone),
            .EP_OUT_popTransSuccess_i(popTransSuccess),
            .EP_OUT_popData_i(EP_READ_EN && isEp0Selected),
            .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[0]),
            .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[0]),
            .EP_OUT_data_o(EP_OUT_dataOut[0 * 8 +: 8]),
            .respValid_o(EP_respValid[0]),
            .respHandshakePID_o(EP_respHandshakePID[0]),
            .respPacketID_o(EP_respPacketID[0 +: 2])
        );

        genvar i;
        for (i = 1; i < ENDPOINTS; i = i + 1) begin

            localparam usb_ep_pkg::EndpointConfig epConfig = USB_DEV_EP_CONF.epConfs[i-1];

            if (!epConfig.isControlEP && epConfig.conf.nonControlEp.epTypeDevIn == usb_ep_pkg::NONE && epConfig.conf.nonControlEp.epTypeDevOut == usb_ep_pkg::NONE) begin
                $fatal("Wrong number of endpoints specified! Got endpoint type NONE for ep%i", i);
            end

            logic isEpSelected;
            assign isEpSelected = i == epSelect;

            case (i)
                `CREATE_EP_CASE(1);
                `CREATE_EP_CASE(2);
                `CREATE_EP_CASE(3);
                `CREATE_EP_CASE(4);
                `CREATE_EP_CASE(5);
                `CREATE_EP_CASE(6);
                `CREATE_EP_CASE(7);
                `CREATE_EP_CASE(8);
                `CREATE_EP_CASE(9);
                `CREATE_EP_CASE(10);
                `CREATE_EP_CASE(11);
                `CREATE_EP_CASE(12);
                `CREATE_EP_CASE(13);
                `CREATE_EP_CASE(14);
                `CREATE_EP_CASE(15);
                default:
                    $fatal("Invalid Endpoint count!");
            endcase
        end
    endgenerate

//====================================================================================
//====================================RX Interface====================================
//====================================================================================

    logic transactionStarted, transactionDone;
    // Based on useInternalBuf we need to switch between the Endpoint FIFOs and the internal buffer to receive i.e. Token Packets that might start an transaction
    // We also want to receive the host response in our internal buffer -> switch buffers back after data was sent!
    logic useInternalBuf, forceInternalBuf;
    assign useInternalBuf = !transactionStarted || forceInternalBuf;

    // This buffer is used to receive the first packet that might initiate a transaction
    localparam TRANS_START_BUF_MAX_BIT_IDX = usb_packet_pkg::INIT_TRANS_PACKET_BUF_LEN-1;
    `MUTE_LINT(UNUSED)
    logic [TRANS_START_BUF_MAX_BIT_IDX:0] transStartPacketBuf;
    `UNMUTE_LINT(UNUSED)
    logic transStartPacketBufFull;

    logic transBufRst;
    assign transBufRst = receiveDone;
    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(usb_packet_pkg::INIT_TRANS_PACKET_BUF_BYTE_COUNT),
        .INITIALIZE_BUF_IDX(1)
    ) transStartBufWrapper (
        .clk_i(clk12_i),
        .rst_i(transBufRst),

        .data_i(wData),
        .dataValid_i(useInternalBuf && rxDataValid_i),

        .buffer_o(transStartPacketBuf),
        .isFull_o(transStartPacketBufFull)
    );

    // Endpoint FIFO connections
    logic receiveDone;
    logic receiveSuccess;
    initial begin
        receiveDone = 1'b0;
        transactionStarted = 1'b0;
        gotTransStartPacket = 1'b0;
    end

    // Serial frontend connections
    assign EP_WRITE_EN = !useInternalBuf && rxHandshake;
    assign wData = rxData_i;

    logic rxBufFull;
    // Ignore that the buffer is full if we are not yet in an transaction -> fast ignore transactions for other USB devices on the same bus!
    assign rxBufFull = useInternalBuf ? transStartPacketBufFull && transactionStarted : writeFifoFull;
    // If this is the last byte, always accept
    assign rxAcceptNewData_o = (!receiveDone && !rxBufFull) || rxIsLastByte_i;

    logic rxHandshake;
    assign rxHandshake = rxAcceptNewData_o && rxDataValid_i;

    usb_packet_pkg::TokenPacket tokenPacketPart;
    assign tokenPacketPart = usb_packet_pkg::TokenPacket'(transStartPacketBuf[usb_packet_pkg::TOKEN_PACKET_OFFSET +: usb_packet_pkg::TOKEN_PACKET_BITS]);

    usb_packet_pkg::PID_Types packetPID;
    assign packetPID = usb_packet_pkg::PID_Types'(transStartPacketBuf[usb_packet_pkg::PACKET_HEADER_OFFSET +: usb_packet_pkg::PACKET_HEADER_BITS / 2]);
    assign upperTransStartPID = packetPID[3:2];

    // Start of Frame (SOF)
    logic isSOF;
    assign isSOF = upperTransStartPID == usb_packet_pkg::PID_SOF_TOKEN[3:2];

    logic isTokenPID;
    assign isTokenPID = packetPID[usb_packet_pkg::PACKET_TYPE_MASK_OFFSET +: usb_packet_pkg::PACKET_TYPE_MASK_LENGTH] == usb_packet_pkg::TOKEN_PACKET_MASK_VAL;

    logic isValidTransStartPacket;
    assign isValidTransStartPacket = receiveDone && receiveSuccess && isTokenPID && !isSOF && tokenPacketPart.endptSel < ENDPOINTS[3:0] && tokenPacketPart.devAddr == deviceAddr;

    logic rxFailCondition;
    // treat full buffer as error -> not all data could be stored!
    // Otherwise if this is the last byte and keepPacket_i is set low there was some transmission error -> receive failed!
    //TODO if receive failed because a buffer was full, we should rather respond with an NAK (as described in the spec) for OUT tokens instead of no response at all (which is typically used to indicate transmission errors, i.e. invalid CRC)
    //TODO !keepPacket can also have multiple reasons: byte was not received (similar to rxBufFull), CRC error, DP signal error
    assign rxFailCondition = rxBufFull || !keepPacket_i;

`ifdef DEBUG_LEDS
    initial begin
        LED_R = 1'b0;
        LED_G = 1'b0;
        LED_B = 1'b0;
    end
    //TODO check why the simulation triggers these error conditions & refine conditions / fix issues
    always_ff @(posedge clk12_i) begin
        LED_R <= LED_R || (receiveDone && !receiveSuccess);
        LED_G <= LED_G || usbResetDetected_i;
        LED_B <= LED_B || packetWaitTimeout_i;
    end
`endif


    always_ff @(posedge clk12_i) begin
        // Will only be asserted on receiveDone -> we dont have to specifically check whether be received a byte & if it was the last byte
        receiveSuccess <= receiveDone || !rxFailCondition;
        // Signal that receiving is done for a single cycle
        receiveDone <= !receiveDone && rxHandshake && rxIsLastByte_i;

        // Only start the transaction if we recieved the packet correctly!
        transactionStarted <= transactionStarted ? !transactionDone : isValidTransStartPacket;
        // Delay gotTransStartPacket to ensure that epSelect is set too! Else the previous endpoint feels responsible!
        gotTransStartPacket <= !transactionStarted && isValidTransStartPacket;
        //TODO it might be worth considering to replace the epSelect register with an static assign to tokenPacketPart.endptSel[EP_SELECT_WID-1:0]
        epSelect <= transactionStarted ? epSelect : tokenPacketPart.endptSel[EP_SELECT_WID-1:0];
    end

//====================================================================================
//====================================TX Interface====================================
//====================================================================================

    logic [10:0] maxPacketSize;
    // This counter is used to ensure that we do not send more than max. packet size many bytes!
    logic [10:0] maxBytesLeft;

    logic nextIsSendingPhase;
    assign txReqSendPacket_o = !isSendingPhase_o && nextIsSendingPhase;
    logic sendPID, nextSendPID;
    logic sendHandshake;
    logic nextIsPidLast;
    logic [3:0] pidData;
    // This flag is supposed to be set during the isSendingPhase_o, after the PID was sent and after that only data will be send
    logic isActiveSendingData;
    always_ff @(posedge clk12_i) begin
        pidData <= sendPID ? pidData : {epResponsePacketID, sendHandshake ? usb_packet_pkg::HANDSHAKE_PACKET_MASK_VAL : usb_packet_pkg::DATA_PACKET_MASK_VAL};
    end

    assign txData_o = sendPID ? {~pidData, pidData} : rData;
    assign txDataValid_o = sendPID || (readDataAvailable && isActiveSendingData);
    assign txIsLastByte_o = (isActiveSendingData && readIsLastPacketByte) || maxBytesLeft == 1;
    assign EP_READ_EN = isActiveSendingData && txAcceptNewData_i;

    logic txHandshake;
    assign txHandshake = txDataValid_o && txAcceptNewData_i;

    initial begin
        maxBytesLeft = 11'b0;
        sendPID = 1'b0;
        isActiveSendingData = 1'b0;
    end

    always_ff @(posedge clk12_i) begin
        sendPID <= sendPID ? !txHandshake : nextSendPID;

        // When the last byte was sent, clear this flag
        // Else if we have a falling sendPID edge (sendPID && txHandshake)
        // then data will be send next (except if PID was the only thing to send (&& maxBytesLeft != 1))
        isActiveSendingData <= isActiveSendingData ? !(txIsLastByte_o && txHandshake) : sendPID && txHandshake && !(maxBytesLeft == 1);

        if (!sendPID && nextSendPID) begin
            maxBytesLeft <= nextIsPidLast ? 1 : maxPacketSize;
        end else begin
            // Update maxBytesLeft at every handshake
            maxBytesLeft <= isActiveSendingData && txHandshake ? maxBytesLeft - 1 : maxBytesLeft;
        end

    end

//====================================================================================
//================================Transaction Handling================================
//====================================================================================

/*
Device Transaction State Machine Hierarchy Overview:

    Device_Process_trans
      - Dev_do_OUT: if pid == PID_OUT_TOKEN || (pid == PID_SETUP_TOKEN && ep_type == control)
        - Dev_Do_IsochO: if type of selected endpoint (ep_type) == isochronous
        - Dev_Do_BCINTO: if ep_type == interrupt || (not high speed && (ep_type == bulk || ep_type == control))
        (- Dev_HS_BCO) <- For HighSpeed devices: if high speed && (ep_type == bulk || ep_type == control)

      - Dev_do_IN: if pid == PID_IN_TOKEN
        - Dev_Do_IsochI: if ep_type == isochronous
        - Dev_Do_BCINTI: (if ep_type == bulk || ep_type == control || ep_type == interrupt) aka else

      (- Dev_HS_ping: if pid == PID_SPECIAL_PING) <- For HighSpeed devices

*/

    //TODO adjust length as needed!
    typedef enum logic[3:0] {
        PE_RST_RX_CLK = 0,
        PE_WAIT_FOR_TRANSACTION,

        // Host sends data: PE_DO_OUT_ISO: page 229 NOTE: No DATA toggle checks!
        IsochO_HANDLE_PACKET,
        // Has no handshake phase -> can be simulated as transmission error -> nothing is send in return!

        // Host sends data: PE_DO_OUT_BCINT: page 221
        BCINTO_HANDLE_PACKET,
        // Issue response
        BCINTO_ISSUE_RESPONSE,
        BCINTO_WAIT_RESPONSE_SENT,

        // Device sends data: PE_DO_IN_ISOCH: page 229 NOTE: Always use DATA0 PID!
        IsochI_ISSUE_PACKET,
        IsochI_WAIT_PACKET_SENT,
        // Has no handshake phase -> no wait needed, directly go back to initial state!

        // Device sends data: PE_DO_IN_BCINT: page 221
        BCINTI_ISSUE_PACKET,
        BCINTI_WAIT_PACKET_SENT,
        // We need to switch back to the internal buffer!
        BCINTI_AWAIT_RESPONSE
    } TransactionState;

    TransactionState transState, nextTransState;

    initial begin
        transState = PE_WAIT_FOR_TRANSACTION;
        isSendingPhase_o = 1'b0;
    end

    assign isHostIn = upperTransStartPID == usb_packet_pkg::PID_IN_TOKEN[3:2];
    logic isEpIsochronous;

    always_comb begin
        nextTransState = transState;
        readTimerRst_o = 1'b1;
        nextIsSendingPhase = isSendingPhase_o;
        transactionDone = 1'b0;

        nextSendPID = 1'b0;
        nextIsPidLast = 1'b1;
        sendHandshake = 1'b1;

        fillTransSuccess = 1'b0;
        fillTransDone = 1'b0;
        popTransDone = 1'b0;
        popTransSuccess = 1'b0;

        forceInternalBuf = 1'b0;

        unique case (transState)
            PE_RST_RX_CLK: begin
                // Ensure that the we start with a new transaction
                fillTransDone = 1'b1;
                popTransDone = 1'b1;
                // Next we are receiving data to from the device
                nextIsSendingPhase = 1'b0;
                transactionDone = 1'b1;

                //TODO reset DPPL?

                nextTransState = PE_WAIT_FOR_TRANSACTION;
            end
            PE_WAIT_FOR_TRANSACTION: begin
                if (transactionStarted) begin
                    if (isHostIn) begin
                        // We are sending data to the host
                        nextIsSendingPhase = 1'b1;
                        // Either IsochI_ISSUE_PACKET or BCINTI_ISSUE_PACKET
                        nextTransState = isEpIsochronous ? IsochI_ISSUE_PACKET : BCINTI_ISSUE_PACKET;
                    end else begin
                        // Read after read -> TODO reset DPPL?

                        // Either IsochO_AWAIT_PACKET or BCINTO_AWAIT_PACKET
                        nextTransState = isEpIsochronous ? IsochO_HANDLE_PACKET : BCINTO_HANDLE_PACKET;
                    end
                end
            end

            // New transaction types
            IsochO_HANDLE_PACKET: begin
                // We are waiting a limited time for the packet to come!
                readTimerRst_o = 1'b0;

                fillTransSuccess = receiveSuccess;
                fillTransDone = receiveDone;

                if (packetWaitTimeout_i || receiveDone) begin
                    // We are done after receiving!
                    nextTransState = PE_RST_RX_CLK;
                end
            end

            // New transaction types
            BCINTO_HANDLE_PACKET: begin
                // We are waiting a limited time for the packet to come!
                readTimerRst_o = 1'b0;

                fillTransSuccess = receiveSuccess;
                fillTransDone = receiveDone;

                if (packetWaitTimeout_i) begin
                    nextTransState = PE_RST_RX_CLK;
                end else if (receiveDone) begin
                    // We are done after receiving!
                    nextTransState = receiveSuccess ? BCINTO_ISSUE_RESPONSE : PE_RST_RX_CLK;

                    // We are sending data to the device
                    nextIsSendingPhase = receiveSuccess;
                end
            end
            BCINTO_ISSUE_RESPONSE: begin
                //TODO this expects the EP response within X cycles to not trigger USB timeouts! //TODO determine X
                nextSendPID = epResponseValid;

                // sendHandshake are set to 1 by default -> overrule EP response to avoid protocol violations... 
                //TODO fix the EP0 implementation to have matching values... and allways assign epResponseIsHandshakePID!
                // sendHandshake = 1'b1;
                // The response may only be a handshake -> thus it is the last byte!
                // nextIsPidLast is set to 1 by default
                //TODO if all endpoints behave correctly, then this might also be replaced by epResponseIsHandshakePID || !readDataAvailable
                //     Yet, that would also increase the chance of failing
                // nextIsPidLast = 1'b1;

                if (epResponseValid) begin
                    nextTransState = BCINTO_WAIT_RESPONSE_SENT;
                end
            end
            BCINTO_WAIT_RESPONSE_SENT: begin
                if (txDoneSending_i) begin
                    // We are done here
                    nextTransState = PE_RST_RX_CLK;
                end
            end

            // New transaction types
            IsochI_ISSUE_PACKET, BCINTI_ISSUE_PACKET: begin
                //TODO this expects the EP response within X cycles to not trigger USB timeouts! //TODO determine X
                nextSendPID = epResponseValid;
                // If its an handshake PID we are done, if the EP signals that its ready to respond but no data is available -> send zero data length packet!
                // Otherwise if the EP want's to indicate that there is no data then it should respond with an NAK and no DATA PID
                nextIsPidLast = epResponseIsHandshakePID || !readDataAvailable;
                sendHandshake = epResponseIsHandshakePID;

                if (epResponseValid) begin
                    // If we have a bulk transfer and the PID is handshake, then there won't be a handshake stage afterwards -> reuse isochronous logic
                    nextTransState = epResponseIsHandshakePID ? IsochI_WAIT_PACKET_SENT : transState + 1;
                end
            end

            IsochI_WAIT_PACKET_SENT: begin
                // We do not care about errors -> always successful
                popTransSuccess = 1'b1;
                popTransDone = txDoneSending_i;

                if (txDoneSending_i) begin
                    // We are done here
                    nextTransState = PE_RST_RX_CLK;
                end
            end

            BCINTI_WAIT_PACKET_SENT: begin
                if (txDoneSending_i) begin
                    // We are done here
                    nextTransState = BCINTI_AWAIT_RESPONSE;
                    nextIsSendingPhase = 1'b0;
                end
            end
            BCINTI_AWAIT_RESPONSE: begin
                // We are waiting a limited time for the packet to come!
                readTimerRst_o = 1'b0;

                // We expect to receive the response in our internal transaction buffer and not to pass it to the EPs!
                forceInternalBuf = 1'b1;
                // Success only when we received an ACK!
                popTransSuccess = receiveSuccess && packetPID == usb_packet_pkg::PID_HANDSHAKE_ACK;
                popTransDone = receiveDone;

                if (packetWaitTimeout_i || receiveDone) begin
                    // We are done after receiving the handshake or a timeout!
                    nextTransState = PE_RST_RX_CLK;

                    // Read after read -> TODO reset DPPL?
                end
            end
        endcase
    end

    always_ff @(posedge clk12_i) begin
        transState <= nextTransState;
        isSendingPhase_o <= nextIsSendingPhase;
    end

//====================================================================================
//===================================LUT Generation===================================
//====================================================================================

genvar epIdx;
generate
    logic [11*ENDPOINTS - 1:0] maxPacketSizeOutLut;

    assign maxPacketSizeOutLut[0 * 11 +: 11] = {3'b0, USB_DEV_EP_CONF.deviceDesc.bMaxPacketSize0};

    for (epIdx = 0; epIdx < USB_DEV_EP_CONF.endpointCount; epIdx++) begin
        if (USB_DEV_EP_CONF.epConfs[epIdx].isControlEP) begin
            assign maxPacketSizeOutLut[(epIdx + 1) * 11 +: 11] = {3'b0, USB_DEV_EP_CONF.epConfs[epIdx].conf.controlEpConf.maxPacketSize};
        end else begin
            assign maxPacketSizeOutLut[(epIdx + 1) * 11 +: 11] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.maxPacketSize;
        end
    end

    assign maxPacketSize = maxPacketSizeOutLut[epSelect * 11 +: 11];
endgenerate

generate
    if (USB_DEV_EP_CONF.endpointCount > 0) begin
        logic [USB_DEV_EP_CONF.endpointCount-1:0] isEpInIsochronousLUT;
        logic [USB_DEV_EP_CONF.endpointCount-1:0] isEpOutIsochronousLUT;

        for (epIdx = 0; epIdx < USB_DEV_EP_CONF.endpointCount; epIdx++) begin
            if (USB_DEV_EP_CONF.epConfs[epIdx].isControlEP) begin
                assign isEpInIsochronousLUT[epIdx] = 1'b0;
                assign isEpOutIsochronousLUT[epIdx] = 1'b0;
            end else begin
                assign isEpInIsochronousLUT[epIdx] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.epTypeDevIn == usb_ep_pkg::ISOCHRONOUS;
                assign isEpOutIsochronousLUT[epIdx] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.epTypeDevOut == usb_ep_pkg::ISOCHRONOUS;
            end
        end

        // assign isEpIsochronous = {(isHostIn ? isEpOutIsochronousLUT : isEpInIsochronousLUT), 1'b0}[epSelect];
        assign isEpIsochronous = (|epSelect) && (isHostIn ? isEpOutIsochronousLUT[epSelect-1] : isEpInIsochronousLUT[epSelect-1]);
    end else begin
        assign isEpIsochronous = 1'b0;
    end
endgenerate

endmodule
