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
    output logic [0:ENDPOINTS-1] EP_IN_dataAvailable,
    output logic [(EP_DATA_WID-1) * ENDPOINTS:0] EP_IN_dataOut,

    input logic [0:ENDPOINTS-1] EP_OUT_dataValid,
    output logic [0:ENDPOINTS-1] EP_OUT_full,
    input logic [(EP_DATA_WID-1) * ENDPOINTS:0] EP_OUT_dataIn
);

/*
Device Transaction State Machine Hierarchy Overview:

    Device_Process_trans
      - Dev_do_OUT: if pid == PID_OUT_TOKEN || pid == PID_OUT_TOKEN
        - Dev_Do_IsochO
        - Dev_Do_BCINTO
        (- Dev_HS_BCO) <- For HighSpeed devices

      - Dev_do_IN: if pid == PID_IN_TOKEN
        - Dev_Do_IsochI
        - Dev_Do_BCINTI

      (- Dev_HS_ping: if pid == PID_SPECIAL_PING) <- For HighSpeed devices

*/

    logic WRITE_EN; //TODO
    logic READ_EN; //TODO
    logic [$clog2(ENDPOINTS):0] epSelect;

    // Used for received data
    logic [EP_ADDR_WID-1:0] wdata;
    // Used for data to be output
    logic [EP_ADDR_WID-1:0] rdata;

    logic [0:ENDPOINTS-1] EP_IN_dataValid;
    logic [0:ENDPOINTS-1] EP_IN_full;
    logic [(EP_DATA_WID-1) * ENDPOINTS:0] EP_IN_dataIn;

    logic [0:ENDPOINTS-1] EP_OUT_popData;
    logic [0:ENDPOINTS-1] EP_OUT_dataAvailable;
    logic [(EP_DATA_WID-1) * ENDPOINTS:0] EP_OUT_dataOut;

    assign rdata = EP_OUT_dataOut[((epSelect+1) * EP_DATA_WID) - 1:epSelect * EP_DATA_WID];

    generate
        genvar i;
        for (i = 0; i < ENDPOINTS; i = i + 1) begin

            assign EP_IN_dataValid[i] = WRITE_EN && i == epSelect;
            assign EP_IN_dataIn[i] = wdata;
            BRAM_FIFO #(
                .EP_ADDR_WID(EP_ADDR_WID),
                .EP_DATA_WID(EP_DATA_WID)
            ) fifoXIn(
                .CLK(clk48),
                .dataValid(EP_IN_dataValid[i]),
                .full(EP_IN_full[i]),
                .dataIn(EP_IN_dataIn[((i+1) * EP_DATA_WID) - 1:i * EP_DATA_WID]),

                .popData(EP_IN_popData[i]),
                .dataAvailable(EP_IN_dataAvailable[i]),
                .dataOut(EP_IN_dataOut[((i+1) * EP_DATA_WID) - 1:i * EP_DATA_WID])
            );

            assign EP_OUT_popData[i] = READ_EN && i == epSelect;
            BRAM_FIFO #(
                .EP_ADDR_WID(EP_ADDR_WID),
                .EP_DATA_WID(EP_DATA_WID)
            ) fifoXOut(
                .CLK(clk48),
                .dataValid(EP_OUT_dataValid[i]),
                .full(EP_OUT_full[i]),
                .dataIn(EP_OUT_dataIn[((i+1) * EP_DATA_WID) - 1:i * EP_DATA_WID]),

                .popData(EP_OUT_popData[i]),
                .dataAvailable(EP_OUT_dataAvailable[i]),
                .dataOut(EP_OUT_dataOut[((i+1) * EP_DATA_WID) - 1:i * EP_DATA_WID])
            );
        end
    endgenerate

//====================================================================================
//===============================RX Interface=========================================
//====================================================================================

    //localparam RX_BUF_SIZE = 8;
    //logic [7:0] rxBuf [0:RX_BUF_SIZE-1]; //TODO we need to export the data!

    assign wdata = rxData;

    logic canReceive; //TODO

    logic rxHandshake;
    logic packetReceived;

    assign rxHandshake = canReceive && rxDataValid;
    assign packetReceived = rxHandshake && txIsLastByte;
    assign rxAcceptNewData = canReceive;

    logic receiveDone;

    always_comb begin
        WRITE_EN = rxHandshake;
        if (receiveDone) begin
            // After the last byte was received, we need to store the amount of 
        end
    end

    always_ff @(posedge clk48) begin
        if (rxHandshake) begin
            if (EP_IN_full[epSelect]) begin
                //TODO treat overflow as error
            end
            receiveDone <= txIsLastByte;
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

endmodule