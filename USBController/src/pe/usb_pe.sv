`include "config_pkg.sv"
`include "usb_packet_pkg.sv"
`include "usb_dev_req_pkg.sv"
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

    logic [usb_packet_pkg::USB_DEV_ADDR_WID-1:0] deviceAddr;
    logic [10:0] maxPacketSize;
    logic isEpIsochronous;

    usb_endpoint_arbiter #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) epArbiter (
        .clk12_i(clk12_i),

        // Serial interface
        .usbResetDetected_i(usbResetDetected_i),
        .ackUsbResetDetect_o(ackUsbResetDetect_o),

        // Index used to select the endpoint
        .epSelect(epSelect),
        .upperTransStartPID(upperTransStartPID),
        .gotTransStartPacket(gotTransStartPacket),
        .isHostIn(isHostIn),

        // Used for received data
        .fillTransSuccess(fillTransSuccess),
        .fillTransDone(fillTransDone),
        .EP_WRITE_EN(EP_WRITE_EN),
        .wData(wData),
        .writeFifoFull(writeFifoFull),

        // Used for data to be output
        .popTransDone(popTransDone),
        .popTransSuccess(popTransSuccess),
        .EP_READ_EN(EP_READ_EN),
        .readDataAvailable(readDataAvailable),
        .readIsLastPacketByte(readIsLastPacketByte),
        .rData(rData),
        .epResponseValid(epResponseValid),
        .epResponseIsHandshakePID(epResponseIsHandshakePID),
        .epResponsePacketID(epResponsePacketID),

        // Device state output
        .deviceAddr(deviceAddr),
        .maxPacketSize(maxPacketSize),
        .isEpIsochronous(isEpIsochronous),

        // External endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
        // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
        .EP_IN_popTransDone_i(EP_IN_popTransDone_i),
        .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i),
        .EP_IN_popData_i(EP_IN_popData_i),
        .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o),
        .EP_IN_data_o(EP_IN_data_o),

        .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i),
        .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .EP_OUT_dataValid_i(EP_OUT_dataValid_i),
        .EP_OUT_data_i(EP_OUT_data_i),
        .EP_OUT_full_o(EP_OUT_full_o)
    );

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

    usb_packet_pkg::TokenPacket tokenPacketPart;
    assign tokenPacketPart = usb_packet_pkg::TokenPacket'(transStartPacketBuf[usb_packet_pkg::TOKEN_PACKET_OFFSET +: usb_packet_pkg::TOKEN_PACKET_BITS]);
    usb_packet_pkg::PID_Types packetPID;
    assign packetPID = usb_packet_pkg::PID_Types'(transStartPacketBuf[usb_packet_pkg::PACKET_HEADER_OFFSET +: usb_packet_pkg::PACKET_HEADER_BITS / 2]);
    assign upperTransStartPID = packetPID[3:2];

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

    // Start of Frame (SOF)
    logic isSOF;
    assign isSOF = upperTransStartPID == usb_packet_pkg::PID_SOF_TOKEN[3:2];
    logic isTokenPID;
    assign isTokenPID = packetPID[usb_packet_pkg::PACKET_TYPE_MASK_OFFSET +: usb_packet_pkg::PACKET_TYPE_MASK_LENGTH] == usb_packet_pkg::TOKEN_PACKET_MASK_VAL;

    logic isValidTransStartPacket;
    assign isValidTransStartPacket = receiveDone && receiveSuccess && isTokenPID && !isSOF
         && tokenPacketPart.endptSel < ENDPOINTS[3:0] && tokenPacketPart.devAddr == deviceAddr;

    // treat full buffer as error -> not all data could be stored!
    // Otherwise if this is the last byte and keepPacket_i is set low there was some transmission error -> receive failed!
    //TODO if receive failed because a buffer was full, we should rather respond with an NAK (as described in the spec) for OUT tokens instead of no response at all (which is typically used to indicate transmission errors, i.e. invalid CRC)
    //TODO !keepPacket can also have multiple reasons: byte was not received (similar to rxBufFull), CRC error, DP signal error
    logic rxFailCondition;
    assign rxFailCondition = rxBufFull || !keepPacket_i;

`ifdef DEBUG_LEDS
    logic inv_LED_R;
    logic inv_LED_G;
    logic inv_LED_B;
    initial begin
        inv_LED_R = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_G = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_B = 1'b0; // a value of 1 turns the LEDs off!
    end
    //TODO check why the simulation triggers these error conditions & refine conditions / fix issues
    always_ff @(posedge clk12_i) begin
        inv_LED_R <= inv_LED_R || (receiveDone && !receiveSuccess);
        inv_LED_G <= inv_LED_G || usbResetDetected_i;
        inv_LED_B <= inv_LED_B || packetWaitTimeout_i;
    end

    assign LED_R = !inv_LED_R;
    assign LED_G = !inv_LED_G;
    assign LED_B = !inv_LED_B;
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

    // This counter is used to ensure that we do not send more than max. packet size many bytes!
    logic [10:0] maxBytesLeft;

    logic prevIsSendingPhase;
    assign txReqSendPacket_o = !prevIsSendingPhase && isSendingPhase_o;
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

    logic nextIsSendingPhase;
    initial begin
        transState = PE_WAIT_FOR_TRANSACTION;
        isSendingPhase_o = 1'b0;
        prevIsSendingPhase = 1'b0;
    end

    assign isHostIn = upperTransStartPID == usb_packet_pkg::PID_IN_TOKEN[3:2];

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
                // Next we are receiving data to from the device
                nextIsSendingPhase = 1'b0;
                transactionDone = 1'b1;

                //TODO reset DPPL?

                nextTransState = PE_WAIT_FOR_TRANSACTION;
            end
            PE_WAIT_FOR_TRANSACTION: begin
                if (gotTransStartPacket) begin
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

                fillTransSuccess = receiveDone && receiveSuccess;
                fillTransDone = packetWaitTimeout_i || receiveDone;

                if (packetWaitTimeout_i || receiveDone) begin
                    // We are done after receiving!
                    nextTransState = PE_RST_RX_CLK;
                end
            end

            // New transaction types
            BCINTO_HANDLE_PACKET: begin
                // We are waiting a limited time for the packet to come!
                readTimerRst_o = 1'b0;

                fillTransSuccess = receiveDone && receiveSuccess;
                fillTransDone = packetWaitTimeout_i || receiveDone;

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
                popTransSuccess = receiveDone && receiveSuccess && packetPID == usb_packet_pkg::PID_HANDSHAKE_ACK;
                popTransDone = receiveDone || packetWaitTimeout_i;

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
        prevIsSendingPhase <= isSendingPhase_o;
    end

endmodule
