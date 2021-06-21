`include "config_pkg.sv"
`include "usb_packet_pkg.sv"
`include "usb_ep_pkg.sv"

// USB Protocol Engine (PE)
module usb_pe #(
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8, //TODO this is a pseudo parameter as byte wise data transfers is fixed assumption throughout the code!
    usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF = usb_ep_pkg::DefaultUsbDeviceEpConfig,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk48,

    input logic usbResetDetected,
    output logic ackUsbResetDetect,

    // State information
    input logic txDoneSending, //TODO use
    input logic rxDPPLGotSignal,
    output logic isSendingPhase, //TODO

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48!
    output logic rxAcceptNewData,
    input logic [7:0] rxData,
    input logic rxIsLastByte,
    input logic rxDataValid,
    input logic keepPacket,

    // Data Transmit Interface: synced with clk48!
    output logic txReqSendPacket,
    output logic txDataValid,
    output logic txIsLastByte,
    output logic [7:0] txData,
    input logic txAcceptNewData,

    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    input logic [ENDPOINTS-1:0] EP_IN_popTransDone,
    input logic [ENDPOINTS-1:0] EP_IN_popTransSuccess,
    input logic [ENDPOINTS-1:0] EP_IN_popData,
    output logic [ENDPOINTS-1:0] EP_IN_dataAvailable,
    output logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_IN_dataOut,

    input logic [ENDPOINTS-1:0] EP_OUT_fillTransDone,
    input logic [ENDPOINTS-1:0] EP_OUT_fillTransSuccess,
    input logic [ENDPOINTS-1:0] EP_OUT_dataValid,
    input logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_OUT_dataIn,
    output logic [ENDPOINTS-1:0] EP_OUT_full
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

    typedef enum logic[3:0] {
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

    logic [$clog2(ENDPOINTS):0] epSelect; //TODO

    // Used for received data
    logic fillTransDone; //TODO
    logic fillTransSuccess; //TODO
    logic EP_WRITE_EN; //TODO
    logic [EP_DATA_WID-1:0] wdata; //TODO
    logic writeFifoFull;

    // Used for data to be output
    logic popTransDone; //TODO
    logic popTransSuccess; //TODO
    logic EP_READ_EN; //TODO
    logic readDataAvailable;
    logic [EP_DATA_WID-1:0] rdata; //TODO

    logic [ENDPOINTS-1:0] EP_IN_full;

    logic [ENDPOINTS-1:0] EP_OUT_dataAvailable;
    logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_OUT_dataOut;

    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(EP_DATA_WID)) rdataMux (
        .dataSelect(epSelect),
        .dataVec(EP_OUT_dataOut),
        .data(rdata)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) fifoFullMux (
        .dataSelect(epSelect),
        .dataVec(EP_IN_full),
        .data(writeFifoFull)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) readDataAvailableMux (
        .dataSelect(epSelect),
        .dataVec(EP_OUT_dataAvailable),
        .data(readDataAvailable)
    );

    localparam USB_DEV_ADDR_WID = 7;
    localparam USB_DEV_CONF_WID = 8;
    logic [USB_DEV_ADDR_WID-1:0] deviceAddr;
    logic [USB_DEV_CONF_WID-1:0] deviceConf;
    generate

        // Endpoint 0 has its own implementation as it has to handle some unique requests!
        logic isEp0Selected;
        assign isEp0Selected = !(|epSelect);
        usb_endpoint_0 #(
            .USB_DEV_ADDR_WID(USB_DEV_ADDR_WID),
            .USB_DEV_CONF_WID(USB_DEV_CONF_WID),
            .EP_CONF(USB_DEV_EP_CONF.ep0Conf)
        ) ep0 (
            .clk48(clk48),

            // Endpoint 0 handles the decice state!
            .usbResetDetected(usbResetDetected),
            .ackUsbResetDetect(ackUsbResetDetect),
            .deviceAddr(deviceAddr),
            .deviceConf(deviceConf),

            .transStartPID(transStartPID),
            .gotTransStartPacket(gotTransStartPacket),

            // Device IN interface
            .EP_IN_fillTransDone(fillTransDone),
            .EP_IN_fillTransSuccess(fillTransSuccess),
            .EP_IN_dataValid(EP_WRITE_EN && isEp0Selected),
            .EP_IN_dataIn(wdata),
            .EP_IN_full(EP_IN_full[0]),

            /*
            .EP_IN_popTransDone(EP_IN_popTransDone[0]),
            .EP_IN_popTransSuccess(EP_IN_popTransSuccess[0]),
            .EP_IN_popData(EP_IN_popData[0]),
            .EP_IN_dataAvailable(EP_IN_dataAvailable[0]),
            .EP_IN_dataOut(EP_IN_dataOut[0 * EP_DATA_WID +: EP_DATA_WID]),
            */

            // Device OUT interface
            /*
            .EP_OUT_fillTransDone(EP_OUT_fillTransDone[0]),
            .EP_OUT_fillTransSuccess(EP_OUT_fillTransSuccess[0]),
            .EP_OUT_dataValid(EP_OUT_dataValid[0]),
            .EP_OUT_dataIn(EP_OUT_dataIn[0 * EP_DATA_WID +: EP_DATA_WID]),
            .EP_OUT_full(EP_OUT_full[0]),
            */

            .EP_OUT_popTransDone(popTransDone),
            .EP_OUT_popTransSuccess(popTransSuccess),
            .EP_OUT_popData(EP_READ_EN && isEp0Selected),
            .EP_OUT_dataAvailable(EP_OUT_dataAvailable[0]),
            .EP_OUT_isLastPacketByte(EP_OUT_isLastPacketByte[0]),
            .EP_OUT_dataOut(EP_OUT_dataOut[0 * EP_DATA_WID +: EP_DATA_WID])
        );

        genvar i;
        for (i = 1; i < ENDPOINTS; i = i + 1) begin

            localparam usb_ep_pkg::EndpointConfig epConfig = USB_DEV_EP_CONF.epConfs[i-1];

            if (epConfig.epType == usb_ep_pkg::NONE) begin 
                $fatal("Wrong number of endpoints specified! Got endpoint type NONE for ep%i", i);
            end

            logic isEpSelected;
            assign isEpSelected = i == epSelect;

            usb_endpoint #(
                .EP_CONF(epConfig)
            ) epX (
                .clk48(clk48),

                // Device IN interface
                .EP_IN_fillTransDone(fillTransDone),
                .EP_IN_fillTransSuccess(fillTransSuccess),
                .EP_IN_dataValid(EP_WRITE_EN && isEpSelected),
                .EP_IN_dataIn(wdata),
                .EP_IN_full(EP_IN_full[i]),

                .EP_IN_popTransDone(EP_IN_popTransDone[i]),
                .EP_IN_popTransSuccess(EP_IN_popTransSuccess[i]),
                .EP_IN_popData(EP_IN_popData[i]),
                .EP_IN_dataAvailable(EP_IN_dataAvailable[i]),
                .EP_IN_dataOut(EP_IN_dataOut[i * EP_DATA_WID +: EP_DATA_WID]),

                // Device OUT interface
                .EP_OUT_fillTransDone(EP_OUT_fillTransDone[i]),
                .EP_OUT_fillTransSuccess(EP_OUT_fillTransSuccess[i]),
                .EP_OUT_dataValid(EP_OUT_dataValid[i]),
                .EP_OUT_dataIn(EP_OUT_dataIn[i * EP_DATA_WID +: EP_DATA_WID]),
                .EP_OUT_full(EP_OUT_full[i]),

                .EP_OUT_popTransDone(popTransDone),
                .EP_OUT_popTransSuccess(popTransSuccess),
                .EP_OUT_popData(EP_READ_EN && isEpSelected),
                .EP_OUT_dataAvailable(EP_OUT_dataAvailable[i]),
                .EP_OUT_isLastPacketByte(EP_OUT_isLastPacketByte[i]),
                .EP_OUT_dataOut(EP_OUT_dataOut[i * EP_DATA_WID +: EP_DATA_WID])
            );
        end
    endgenerate

//====================================================================================
//===============================RX Interface=========================================
//====================================================================================

    //localparam RX_BUF_SIZE = 8;
    //logic [7:0] rxBuf [0:RX_BUF_SIZE-1]; //TODO we need to export the data!

    // Endpoint FIFO connections
    logic receiveDone;
    logic receiveSuccess;
    //TODO use these flags to issue a receive response, i.e. ACK!

    initial begin
        receiveDone = 1'b0;
        receiveSuccess = 1'b1;
    end
    assign fillTransSuccess = receiveSuccess;
    assign fillTransDone = receiveDone;
    assign WRITE_EN = rxHandshake;
    assign wdata = rxData;

    // Serial frontend connections
    logic rxHandshake;
    logic packetReceived;

    assign rxAcceptNewData = !writeFifoFull && !receiveDone;
    assign rxHandshake = rxAcceptNewData && rxDataValid;
    assign packetReceived = rxHandshake && txIsLastByte;

    always_ff @(posedge clk48) begin
        if (rxHandshake) begin
            if (writeFifoFull || (txIsLastByte && !keepPacket)) begin
                // treat full buffer as error -> not all data could be stored!
                // Otherwise if this is the last byte and keepPacket is set low there was some transmission error -> receive failed!
                receiveSuccess <= 1'b0;
            end
            receiveDone <= txIsLastByte;
        end else if (receiveDone) begin
            receiveDone <= 1'b0;
            receiveSuccess <= 1'b1;
        end
    end

//====================================================================================
//===============================TX Interface=========================================
//====================================================================================

//TODO
//TODO
//TODO
//TODO
//TODO

//====================================================================================

    logic clk12;
    clock_gen #(
        .DIVIDE_LOG_2(2)
    ) clk12Generator (
        .inCLK(clk48),
        .outCLK(clk12)
    );

    logic readTimerRst; //TODO
    assign readTimerRst = isSendingPhase || receiveDone;
    usb_timeout readTimer(
        .clk48(clk48),
        .clk12(clk12),
        .RST(readTimerRst),
        .rxGotSignal(rxDPPLGotSignal),
        .rxTimeout(packetWaitTimeout)
    );

endmodule
