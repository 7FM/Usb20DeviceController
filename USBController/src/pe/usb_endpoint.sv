`include "usb_ep_pkg.sv"

module usb_endpoint#(
    parameter usb_ep_pkg::EndpointConfig EP_CONF
    //TODO more setting possibilities!
)(
    input logic clk48_i,

    input logic gotTransStartPacket_i, //TODO
    input logic [1:0] transStartTokenID_i, //TODO

    // Device IN interface
    input logic EP_IN_fillTransDone_i,
    input logic EP_IN_fillTransSuccess_i,
    input logic EP_IN_dataValid_i,
    input logic [7:0] EP_IN_data_i,
    output logic EP_IN_full_o,

    input logic EP_IN_popTransDone_i,
    input logic EP_IN_popTransSuccess_i,
    input logic EP_IN_popData_i,
    output logic EP_IN_dataAvailable_o,
    output logic [7:0] EP_IN_data_o,

    // Device OUT interface
    input logic EP_OUT_fillTransDone_i,
    input logic EP_OUT_fillTransSuccess_i,
    input logic EP_OUT_dataValid_i,
    input logic [7:0] EP_OUT_data_i,
    output logic EP_OUT_full_o,

    input logic EP_OUT_popTransDone_i,
    input logic EP_OUT_popTransSuccess_i,
    input logic EP_OUT_popData_i,
    output logic EP_OUT_dataAvailable_o,
    output logic EP_OUT_isLastPacketByte_o, //TODO
    output logic [7:0] EP_OUT_data_o,

    output logic respValid_o, //TODO
    output logic respHandshakePID_o, //TODO
    output logic [1:0] respPacketID_o //TODO
);

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    BRAM_FIFO #(
        .EP_ADDR_WID(EP_ADDR_WID),
        .EP_DATA_WID(EP_DATA_WID)
    ) fifoXIn(
        .clk_i(clk48_i),

        .fillTransDone_i(EP_IN_fillTransDone_i),
        .fillTransSuccess_i(EP_IN_fillTransSuccess_i),
        .dataValid_i(EP_IN_dataValid_i),
        .data_i(EP_IN_data_i),
        .full_o(EP_IN_full_o),

        .popTransDone_i(EP_IN_popTransDone_i),
        .popTransSuccess_i(EP_IN_popTransSuccess_i),
        .popData_i(EP_IN_popData_i),
        .dataAvailable_o(EP_IN_dataAvailable_o),
        .data_o(EP_IN_data_o)
    );

    BRAM_FIFO #(
        .EP_ADDR_WID(EP_ADDR_WID),
        .EP_DATA_WID(EP_DATA_WID)
    ) fifoXOut(
        .clk_i(clk48_i),

        .fillTransDone_i(EP_OUT_fillTransDone_i),
        .fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .dataValid_i(EP_OUT_dataValid_i),
        .data_i(EP_OUT_data_i),
        .full_o(EP_OUT_full_o),

        .popTransDone_i(EP_OUT_popTransDone_i),
        .popTransSuccess_i(EP_OUT_popTransSuccess_i),
        .popData_i(EP_OUT_popData_i),
        .dataAvailable_o(EP_OUT_dataAvailable_o),
        .data_o(EP_OUT_data_o)
    );

endmodule
