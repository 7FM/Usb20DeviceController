`include "usb_ep_pkg.sv"

//TODO remove
`include "util_macros.sv"

module usb_endpoint_in #(
`MUTE_LINT(UNUSED) //TODO remove
    parameter usb_ep_pkg::EndpointConfig EP_CONF,
`UNMUTE_LINT(UNUSED) //TODO remove
    //TODO more setting possibilities!
    localparam USB_DEV_CONF_WID = 8
)(
    input logic clk12_i,

`MUTE_LINT(UNUSED) //TODO remove
    input logic gotTransStartPacket_i, //TODO
    input logic [1:0] transStartTokenID_i, //TODO
    input logic [USB_DEV_CONF_WID-1:0] deviceConf_i, //TODO ?
`UNMUTE_LINT(UNUSED) //TODO remove

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

    `MUTE_LINT(UNDRIVEN) //TODO remove
    output logic respValid_o, //TODO
    output logic respHandshakePID_o, //TODO
    output logic [1:0] respPacketID_o //TODO
    `UNMUTE_LINT(UNDRIVEN) //TODO remove
);

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    BRAM_FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) fifoXIn(
        .clk_i(clk12_i),

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

endmodule
