`include "config_pkg.sv"
`include "usb_packet_pkg.sv"
`include "usb_ep_pkg.sv"

// USB Protocol Engine (PE)
module usb_pe #(
    parameter EP_DATA_WID = 8, //TODO this is a pseudo parameter as byte wise data transfers is fixed assumption throughout the code!
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk48_i,

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,

    // State information
    input logic txDoneSending_i, //TODO use
    input logic rxDPPLGotSignal_i,
    output logic isSendingPhase_o, //TODO

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48_i!
    output logic rxAcceptNewData_o,
    input logic [7:0] rxData_i,
    input logic rxIsLastByte_i,
    input logic rxDataValid_i,
    input logic keepPacket_i,

    // Data Transmit Interface: synced with clk48_i!
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
    output logic [EP_DATA_WID*(ENDPOINTS-1) - 1:0] EP_IN_data_o,

    input logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i,
    input logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_OUT_dataValid_i,
    input logic [EP_DATA_WID*(ENDPOINTS-1) - 1:0] EP_OUT_data_i,
    output logic [ENDPOINTS-2:0] EP_OUT_full_o
);

    /* Request Error:
    When a request is received by a device that is not defined for the device, is inappropriate for the current
    setting of the device, or has values that are not compatible with the request, then a Request Error exists.
    The device deals with the Request Error by returning a STALL PID in response to the next Data stage
    transaction or in the Status stage of the message. It is preferred that the STALL PID be returned at the next
    Data stage transaction, as this avoids unnecessary bus activity
    */
    /* Handling of an INVALID Feature Select, Descriptor Type, Request Type
    If an unsupported or invalid request is made to a USB device, the device responds by returning STALL in
    the Data or Status stage of the request. If the device detects the error in the Setup stage, it is preferred that
    the device returns STALL at the earlier of the Data or Status stage. Receipt of an unsupported or invalid
    request does NOT cause the optional Halt feature on the control pipe to be set.
    */

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

    /*
    typedef enum logic[2:0] {
        PE_RST_RX_CLK,
        PE_WAIT_FOR_TRANSACTION,
        PE_DO_OUT_ISO,
        PE_DO_OUT_BCINT,
        PE_DO_IN_ISOCH,
        PE_DO_IN_BCINT
    } PEState;

    typedef enum logic[1:0] {
        BCINTO_RST_RX_CLK,
        BCINTO_AWAIT_PACKET,
        BCINTO_HANDLE_PACKET,
        BCINTO_ISSUE_RESPONSE
    } RX_BCINTState;

    typedef enum logic[1:0] {
        IsochO_RST_RX_CLK,
        IsochO_AWAIT_PACKET,
        IsochO_HANDLE_PACKET
        // Has no handshake phase
    } RX_IsochState;


    typedef enum logic[1:0] {
        BCINTI_ISSUE_PACKET,
        BCINTI_RST_RX_CLK,
        BCINTI_AWAIT_RESPONSE
    } TX_BCINTState;

    typedef enum logic[0:0] {
        IsochI_ISSUE_PACKET
        // Has no handshake phase
    } TX_IsochState;
    */

    //TODO adjust length as needed!
    typedef enum logic[4:0] {
        PE_RST_RX_CLK,
        PE_WAIT_FOR_TRANSACTION,

        // Host sends data: PE_DO_OUT_ISO: page 229 NOTE: No DATA toggle checks!
        IsochO_RST_RX_CLK, //TODO needs timeout handling
        IsochO_AWAIT_PACKET,
        IsochO_HANDLE_PACKET,
        // Has no handshake phase -> can be simulated as transmission error -> nothing is send in return!

        // Host sends data: PE_DO_OUT_BCINT: page 221
        BCINTO_RST_RX_CLK, //TODO needs timeout handling
        BCINTO_AWAIT_PACKET,
        BCINTO_HANDLE_PACKET,
        //BCINTO_ISSUE_RESPONSE,
        // Issue response
        RX_SUCCESS, // Send ACK
        RX_REQUEST_ERROR, // Send STALL
        RX_RECEIVE_ERROR, // Do nothing and go back to the initial state!


        // Device sends data: PE_DO_IN_ISOCH: page 229 NOTE: Always use DATA0 PID!
        IsochI_ISSUE_PACKET,
        // Has no handshake phase -> no wait needed, directly go back to initial state!

        // Device sends data: PE_DO_IN_BCINT: page 221
        BCINTI_ISSUE_PACKET,
        BCINTI_RST_RX_CLK, //TODO needs timeout handling
        BCINTI_AWAIT_RESPONSE,

        TX_NOTHING_AVAILABLE, // Sends NAK instead of data & handshake phase
        TX_STALL // TODO when is this required?

    } TransactionState;

    logic packetWaitTimeout; //TODO use

//====================================================================================
//==============================Endpoint logic========================================
//====================================================================================

    localparam EP_SELECT_WID = $clog2(ENDPOINTS);
    logic [EP_SELECT_WID-1:0] epSelect;
    usb_packet_pkg::PID_Types transStartPID;
    logic gotTransStartPacket;

    // Used for received data
    logic fillTransDone; //TODO
    logic fillTransSuccess; //TODO
    logic EP_WRITE_EN; //TODO
    logic [EP_DATA_WID-1:0] wData;
    logic writeFifoFull;

    // Used for data to be output
    logic popTransDone; //TODO
    logic popTransSuccess; //TODO
    logic EP_READ_EN; //TODO
    logic readDataAvailable;
    logic readIsLastPacketByte;
    logic [EP_DATA_WID-1:0] rData;
    logic epResponseValid;
    logic epResponseIsHandshakePID;
    logic [1:0] epResponsePacketID;

    logic [ENDPOINTS-1:0] EP_IN_full;

    logic [ENDPOINTS-1:0] EP_OUT_dataAvailable;
    logic [ENDPOINTS-1:0] EP_OUT_isLastPacketByte;
    logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_OUT_dataOut;

    logic [ENDPOINTS-1:0] EP_respValid;
    // If epRespHandshakePID == 1'b1 then epRespPacketID is expected to be for a handshake, otherwise a DATA pid is expected
    logic [ENDPOINTS-1:0] EP_respHandshakePID;
    logic [2*ENDPOINTS - 1:0] EP_respPacketID;

    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(EP_DATA_WID)) rDataMux (
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

    `define CREATE_EP_CASE(x)                                                   \
        x: `EP_``x``_MODULE(epConfig) epX (                                     \
            .clk48_i(clk48_i),                                                  \
                                                                                \
            /* Device IN interface */                                           \
            .EP_IN_fillTransDone_i(fillTransDone),                              \
            .EP_IN_fillTransSuccess_i(fillTransSuccess),                        \
            .EP_IN_dataValid_i(EP_WRITE_EN && isEpSelected),                    \
            .EP_IN_data_i(wData),                                               \
            .EP_IN_full_o(EP_IN_full[x]),                                       \
                                                                                \
            .EP_IN_popTransDone_i(EP_IN_popTransDone_i[x-1]),                   \
            .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i[x-1]),             \
            .EP_IN_popData_i(EP_IN_popData_i[x-1]),                             \
            .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o[x-1]),                 \
            .EP_IN_data_o(EP_IN_data_o[(x-1) * EP_DATA_WID +: EP_DATA_WID]),    \
                                                                                \
            /* Device OUT interface */                                          \
            .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i[x-1]),               \
            .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i[x-1]),         \
            .EP_OUT_dataValid_i(EP_OUT_dataValid_i[x-1]),                       \
            .EP_OUT_data_i(EP_OUT_data_i[(x-1) * EP_DATA_WID +: EP_DATA_WID]),  \
            .EP_OUT_full_o(EP_OUT_full_o[x-1]),                                 \
                                                                                \
            .EP_OUT_popTransDone_i(popTransDone),                               \
            .EP_OUT_popTransSuccess_i(popTransSuccess),                         \
            .EP_OUT_popData_i(EP_READ_EN && isEpSelected),                      \
            .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[x]),                   \
            .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[x]),             \
            .EP_OUT_data_o(EP_OUT_dataOut[x * EP_DATA_WID +: EP_DATA_WID]),     \
                                                                                \
            .respValid_o(EP_respValid[x]),                                      \
            .respHandshakePID_o(EP_respHandshakePID[x]),                        \
            .respPacketID_o(EP_respPacketID[x * 2 +: 2])                        \
        )


    localparam USB_DEV_ADDR_WID = 7;
    localparam USB_DEV_CONF_WID = 8;
    logic [USB_DEV_ADDR_WID-1:0] deviceAddr;
    logic [USB_DEV_CONF_WID-1:0] deviceConf;
    generate

        // Endpoint 0 has its own implementation as it has to handle some unique requests!
        logic isEp0Selected;
        assign isEp0Selected = epSelect == 0;
        `EP_0_MODULE(USB_DEV_ADDR_WID, USB_DEV_CONF_WID, USB_DEV_EP_CONF) ep0 (
            .clk48_i(clk48_i),

            // Endpoint 0 handles the decice state!
            .usbResetDetected_i(usbResetDetected_i),
            .ackUsbResetDetect_o(ackUsbResetDetect_o),
            .deviceAddr_o(deviceAddr),
            .deviceConf_o(deviceConf),

            .transStartTokenID_i(transStartPID[3:2]),
            .gotTransStartPacket_i(gotTransStartPacket),

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
            .EP_IN_data_o(EP_IN_data_o[0 * EP_DATA_WID +: EP_DATA_WID]),
            */

            // Device OUT interface
            /*
            .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i[0]),
            .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i[0]),
            .EP_OUT_dataValid_i(EP_OUT_dataValid_i[0]),
            .EP_OUT_data_i(EP_OUT_data_i[0 * EP_DATA_WID +: EP_DATA_WID]),
            .EP_OUT_full_o(EP_OUT_full_o[0]),
            */

            .EP_OUT_popTransDone_i(popTransDone),
            .EP_OUT_popTransSuccess_i(popTransSuccess),
            .EP_OUT_popData_i(EP_READ_EN && isEp0Selected),
            .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[0]),
            .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[0]),
            .EP_OUT_data_o(EP_OUT_dataOut[0 * EP_DATA_WID +: EP_DATA_WID]),
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
//===============================RX Interface=========================================
//====================================================================================


    logic transactionStarted; //TODO

    // This buffer is used to receive the first packet that might initiate a transaction
    localparam TRANS_START_BUF_MAX_BIT_IDX = usb_packet_pkg::INIT_TRANS_PACKET_BUF_LEN-1;
    logic [TRANS_START_BUF_MAX_BIT_IDX:0] transStartPacketBuf;
    logic transStartPacketBufFull;

    logic transBufRst; //TODO
    assign transBufRst = receiveDone;
    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(usb_packet_pkg::INIT_TRANS_PACKET_BUF_BYTE_COUNT),
        .INITIALIZE_BUF_IDX(1)
    ) transStartBufWrapper (
        .clk_i(clk48_i),
        .rst_i(transBufRst),

        .data_i(wData),
        .dataValid_i(!transactionStarted && rxDataValid_i),

        .buffer_o(transStartPacketBuf),
        .isFull_o(transStartPacketBufFull)
    );

    initial begin
        transactionStarted = 1'b0;
    end

    // Based on transactionStarted we need to switch between the Endpoint FIFOs and the internal buffer to receive i.e. Token Packets that might start an transaction

    // Endpoint FIFO connections
    logic receiveDone;
    logic receiveSuccess;
    //TODO use these flags to issue a receive response, i.e. ACK!
    initial begin
        receiveDone = 1'b0;
        receiveSuccess = 1'b1;
    end

    // Serial frontend connections
    logic rxHandshake;
    logic packetReceived;

    //TODO on wait for handshake, the local buffer is used too

    assign fillTransSuccess = receiveSuccess;
    assign fillTransDone = transactionStarted && receiveDone;
    assign EP_WRITE_EN = transactionStarted && rxHandshake; //TODO we neither want to store token packets nor PIDs here!
    assign wData = rxData_i;

    logic rxBufFull;
    assign rxBufFull = transactionStarted ? writeFifoFull : transStartPacketBufFull;
    assign rxAcceptNewData_o = !receiveDone && !rxBufFull;
    assign rxHandshake = rxAcceptNewData_o && rxDataValid_i;
    assign packetReceived = rxHandshake && rxIsLastByte_i;

    usb_packet_pkg::PacketHeader packetHeader;
    assign packetHeader = usb_packet_pkg::PacketHeader'(transStartPacketBuf[usb_packet_pkg::PACKET_HEADER_OFFSET +: usb_packet_pkg::PACKET_HEADER_BITS]);
    usb_packet_pkg::TokenPacket tokenPacketPart;
    assign tokenPacketPart = usb_packet_pkg::TokenPacket'(transStartPacketBuf[usb_packet_pkg::TOKEN_PACKET_OFFSET +: usb_packet_pkg::TOKEN_PACKET_BITS]);

    assign transStartPID = packetHeader.pid;

    logic isTokenPID;
    assign isTokenPID = packetHeader.pid[usb_packet_pkg::PACKET_TYPE_MASK_OFFSET +: usb_packet_pkg::PACKET_TYPE_MASK_LENGTH] == usb_packet_pkg::TOKEN_PACKET_MASK_VAL;

    //TODO this flag should be state dependent! -> only activate if a new transaction is expected
    assign gotTransStartPacket = !transactionStarted && receiveDone && receiveSuccess;

    always_ff @(posedge clk48_i) begin
        if (rxHandshake) begin
            //TODO if writeFifoFull is set then rxHandshake will never be true!
            //TODO we need to avoid missing the last byte signal -> we may not block & wait for fifo to become available!
            if (rxBufFull || (rxIsLastByte_i && !keepPacket_i)) begin
                // treat full buffer as error -> not all data could be stored!
                // Otherwise if this is the last byte and keepPacket_i is set low there was some transmission error -> receive failed!
                receiveSuccess <= 1'b0;
            end
            receiveDone <= rxIsLastByte_i;
        end else if (receiveDone) begin
            receiveDone <= 1'b0;
            receiveSuccess <= 1'b1;

            // check that the endptSel is in bounds!
            if (tokenPacketPart.endptSel < ENDPOINTS[3:0]) begin
                //TODO needs to consider PID & device state!
                transactionStarted <= 1'b1; //TODO needs to be cleared too!
                epSelect <= tokenPacketPart.endptSel[EP_SELECT_WID-1:0];
            end
        end
    end

//====================================================================================
//===============================TX Interface=========================================
//====================================================================================

//TODO output logic txReqSendPacket_o
//TODO handshake phase is handled with the local buffer here!
    assign txData_o = rData;
    assign txDataValid_o = readDataAvailable;
    assign txIsLastByte_o = readIsLastPacketByte;
    assign EP_READ_EN = txAcceptNewData_i;

// Needs to wait for Handshake / Timeout!
//TODO logic popTransDone;
//TODO logic popTransSuccess;
    //assign popTransSuccess = !packetWaitTimeout &&;
//TODO

//====================================================================================

    logic clk12;
    clock_gen #(
        .DIVIDE_LOG_2(2)
    ) clk12Generator (
        .clk_i(clk48_i),
        .clk_o(clk12)
    );

    logic readTimerRst; //TODO
    assign readTimerRst = isSendingPhase_o || receiveDone;
    usb_timeout readTimer(
        .clk48_i(clk48_i),
        .clk12_i(clk12),
        .rst_i(readTimerRst),
        .rxGotSignal_i(rxDPPLGotSignal_i),
        .rxTimeout_o(packetWaitTimeout)
    );

endmodule
