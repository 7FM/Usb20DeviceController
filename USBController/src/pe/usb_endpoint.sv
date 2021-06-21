`include "usb_ep_pkg.sv"

module usb_endpoint#(
    parameter usb_ep_pkg::EndpointConfig EP_CONF
    //TODO more setting possibilities!
)(
    input logic clk48,

    // Device IN interface
    input logic EP_IN_fillTransDone,
    input logic EP_IN_fillTransSuccess,
    input logic EP_IN_dataValid,
    input logic [7:0] EP_IN_dataIn,
    output logic EP_IN_full,

    input logic EP_IN_popTransDone,
    input logic EP_IN_popTransSuccess,
    input logic EP_IN_popData,
    output logic EP_IN_dataAvailable,
    output logic [7:0] EP_IN_dataOut,

    // Device OUT interface
    input logic EP_OUT_fillTransDone,
    input logic EP_OUT_fillTransSuccess,
    input logic EP_OUT_dataValid,
    input logic [7:0] EP_OUT_dataIn,
    output logic EP_OUT_full,

    input logic EP_OUT_popTransDone,
    input logic EP_OUT_popTransSuccess,
    input logic EP_OUT_popData,
    output logic EP_OUT_dataAvailable,
    output logic EP_OUT_isLastPacketByte, //TODO
    output logic [7:0] EP_OUT_dataOut
);

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    BRAM_FIFO #(
        .EP_ADDR_WID(EP_ADDR_WID),
        .EP_DATA_WID(EP_DATA_WID)
    ) fifoXIn(
        .CLK(clk48),

        .fillTransDone(EP_IN_fillTransDone),
        .fillTransSuccess(EP_IN_fillTransSuccess),
        .dataValid(EP_IN_dataValid),
        .dataIn(EP_IN_dataIn),
        .full(EP_IN_full),

        .popTransDone(EP_IN_popTransDone),
        .popTransSuccess(EP_IN_popTransSuccess),
        .popData(EP_IN_popData),
        .dataAvailable(EP_IN_dataAvailable),
        .dataOut(EP_IN_dataOut)
    );

    BRAM_FIFO #(
        .EP_ADDR_WID(EP_ADDR_WID),
        .EP_DATA_WID(EP_DATA_WID)
    ) fifoXOut(
        .CLK(clk48),

        .fillTransDone(EP_OUT_fillTransDone),
        .fillTransSuccess(EP_OUT_fillTransSuccess),
        .dataValid(EP_OUT_dataValid),
        .dataIn(EP_OUT_dataIn),
        .full(EP_OUT_full),

        .popTransDone(EP_OUT_popTransDone),
        .popTransSuccess(EP_OUT_popTransSuccess),
        .popData(EP_OUT_popData),
        .dataAvailable(EP_OUT_dataAvailable),
        .dataOut(EP_OUT_dataOut)
    );

endmodule
