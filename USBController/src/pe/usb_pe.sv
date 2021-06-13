`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

// USB Protocol Engine (PE)
module usb_pe #(
    parameter ENDPOINTS = 1,
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic clk48,

    input logic usbResetDetected,
    output logic ackUsbResetDetect,

    // State information
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

    // Endpoint interfaces
    input logic [0:ENDPOINTS-1] EP_IN_popData,
    input logic [0:ENDPOINTS-1] EP_IN_popTransDone,
    input logic [0:ENDPOINTS-1] EP_IN_popTransSuccess,
    output logic [0:ENDPOINTS-1] EP_IN_dataAvailable,
    output logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_IN_dataOut,

    input logic [0:ENDPOINTS-1] EP_OUT_dataValid,
    input logic [0:ENDPOINTS-1] EP_OUT_fillTransDone,
    input logic [0:ENDPOINTS-1] EP_OUT_fillTransSuccess,
    output logic [0:ENDPOINTS-1] EP_OUT_full,
    input logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_OUT_dataIn
);

    //logic suspended;
    typedef enum logic[1:0] {
        DEVICE_NOT_RESET = 0, // Ignore all transactions except reset signal
        DEVICE_RESET, // Responds to device and configuration descriptor requests & return information, uses default address
        DEVICE_ADDR_ASSIGNED, // responds to requests to default control pipe with default address as long as no address was assigned
        DEVICE_CONFIGURED // processed a SetConfiguration() request with non zero configuration value & endpoints data toggles are set to DATA0. Now the device functions may be used
    } DeviceState;

    logic [6:0] deviceAddr;

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
      - Dev_do_OUT: if pid == PID_OUT_TOKEN || pid == PID_SETUP_TOKEN
        - Dev_Do_IsochO: if type of selected endpoint (ep_type) == isochronous
        - Dev_Do_BCINTO: if ep_type == interrupt || (not high speed && (ep_type == bulk || ep_type == control))
        (- Dev_HS_BCO) <- For HighSpeed devices: if high speed && (ep_type == bulk || ep_type == control)

      - Dev_do_IN: if pid == PID_IN_TOKEN
        - Dev_Do_IsochI: if ep_type == isochronous
        - Dev_Do_BCINTI: (if ep_type == bulk || ep_type == control || ep_type == interrupt) aka else

      (- Dev_HS_ping: if pid == PID_SPECIAL_PING) <- For HighSpeed devices

*/

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


//====================================================================================
//==============================Endpoint logic========================================
//====================================================================================

    logic [$clog2(ENDPOINTS):0] epSelect; //TODO

    // Used for received data
    logic writeFifoFull;
    logic WRITE_EN; //TODO
    logic [EP_DATA_WID-1:0] wdata; //TODO
    logic fillTransDone; //TODO
    logic fillTransSuccess; //TODO
    // Used for data to be output
    logic readDataAvailable;
    logic READ_EN; //TODO
    logic [EP_DATA_WID-1:0] rdata; //TODO
    logic popTransDone; //TODO
    logic popTransSuccess; //TODO

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

    generate
        genvar i;
        for (i = 0; i < ENDPOINTS; i = i + 1) begin
            BRAM_FIFO #(
                .EP_ADDR_WID(EP_ADDR_WID),
                .EP_DATA_WID(EP_DATA_WID)
            ) fifoXIn(
                .CLK(clk48),

                .dataValid(WRITE_EN && i == epSelect),
                .fillTransDone(fillTransDone),
                .fillTransSuccess(fillTransSuccess),
                .full(EP_IN_full[i]),
                .dataIn(wdata),

                .popData(EP_IN_popData[i]),
                .popTransDone(EP_IN_popTransDone[i]),
                .popTransSuccess(EP_IN_popTransSuccess[i]),
                .dataAvailable(EP_IN_dataAvailable[i]),
                .dataOut(EP_IN_dataOut[i * EP_DATA_WID +: EP_DATA_WID])
            );

            BRAM_FIFO #(
                .EP_ADDR_WID(EP_ADDR_WID),
                .EP_DATA_WID(EP_DATA_WID)
            ) fifoXOut(
                .CLK(clk48),

                .dataValid(EP_OUT_dataValid[i]),
                .fillTransDone(EP_OUT_fillTransDone[i]),
                .fillTransSuccess(EP_OUT_fillTransSuccess[i]),
                .full(EP_OUT_full[i]),
                .dataIn(EP_OUT_dataIn[i * EP_DATA_WID +: EP_DATA_WID]),

                .popData(READ_EN && i == epSelect),
                .popTransDone(popTransDone),
                .popTransSuccess(popTransSuccess),
                .dataAvailable(EP_OUT_dataAvailable[i]),
                .dataOut(EP_OUT_dataOut[i * EP_DATA_WID +: EP_DATA_WID])
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
                receiveSuccess = 1'b0;
            end
            receiveDone <= txIsLastByte;
        end else if (receiveDone) begin
            receiveDone <= 1'b0;
            receiveSuccess = 1'b1;
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

endmodule
