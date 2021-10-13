`include "usb_ep_pkg.sv"

module usb_endpoint #(
    parameter usb_ep_pkg::EndpointConfig EP_CONF,
    localparam USB_DEV_CONF_WID = 8
)(
    input logic clk12_i,

    input logic gotTransStartPacket_i,
    input logic [1:0] transStartTokenID_i,
    input logic [USB_DEV_CONF_WID-1:0] deviceConf_i,

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
    output logic EP_OUT_isLastPacketByte_o,
    output logic [7:0] EP_OUT_data_o,

    output logic respValid_o,
    output logic respHandshakePID_o,
    output logic [1:0] respPacketID_o
);

    logic respValid_IN;
    logic respHandshakePID_IN;
    logic [1:0] respPacketID_IN;

    usb_endpoint_in #(
        .EP_CONF(EP_CONF),
        .USB_DEV_CONF_WID(USB_DEV_CONF_WID)
    ) epXin (
        .clk12_i(clk12_i),

        .gotTransStartPacket_i(gotTransStartPacket_i),
        .transStartTokenID_i(transStartTokenID_i),
        .deviceConf_i(deviceConf_i),

        // Device IN interface
        .EP_IN_fillTransDone_i(EP_IN_fillTransDone_i),
        .EP_IN_fillTransSuccess_i(EP_IN_fillTransSuccess_i),
        .EP_IN_dataValid_i(EP_IN_dataValid_i),
        .EP_IN_data_i(EP_IN_data_i),
        .EP_IN_full_o(EP_IN_full_o),

        .EP_IN_popTransDone_i(EP_IN_popTransDone_i),
        .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i),
        .EP_IN_popData_i(EP_IN_popData_i),
        .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o),
        .EP_IN_data_o(EP_IN_data_o),

        .respValid_o(respValid_IN),
        .respHandshakePID_o(respHandshakePID_IN),
        .respPacketID_o(respPacketID_IN)
    );

    logic respValid_OUT;
    logic respHandshakePID_OUT;
    logic [1:0] respPacketID_OUT;

    usb_endpoint_out #(
        .EP_CONF(EP_CONF),
        .USB_DEV_CONF_WID(USB_DEV_CONF_WID)
    ) epXout (
        .clk12_i(clk12_i),

        .gotTransStartPacket_i(gotTransStartPacket_i),
        .transStartTokenID_i(transStartTokenID_i),
        .deviceConf_i(deviceConf_i),

        // Device OUT interface
        .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i),
        .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .EP_OUT_dataValid_i(EP_OUT_dataValid_i),
        .EP_OUT_data_i(EP_OUT_data_i),
        .EP_OUT_full_o(EP_OUT_full_o),

        .EP_OUT_popTransDone_i(EP_OUT_popTransDone_i),
        .EP_OUT_popTransSuccess_i(EP_OUT_popTransSuccess_i),
        .EP_OUT_popData_i(EP_OUT_popData_i),
        .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable_o),
        .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte_o),
        .EP_OUT_data_o(EP_OUT_data_o),

        .respValid_o(respValid_OUT),
        .respHandshakePID_o(respHandshakePID_OUT),
        .respPacketID_o(respPacketID_OUT)
    );

    logic targetsEpIN; //TODO

    assign {respValid_o, respHandshakePID_o, respPacketID_o} = targetsEpIN ? 
           {respValid_IN, respHandshakePID_IN, respPacketID_IN}
        :  {respValid_OUT, respHandshakePID_OUT, respPacketID_OUT};

endmodule
