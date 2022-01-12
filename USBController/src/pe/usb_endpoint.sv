`include "usb_ep_pkg.sv"

module usb_endpoint #(
    parameter usb_ep_pkg::EndpointConfig EP_CONF,
    localparam USB_DEV_CONF_WID = 8
)(
    input logic clk12_i,

    input logic gotTransStartPacket_i,
    input logic isHostIn_i,
    input logic [1:0] transStartTokenID_i,
    // Status bit that indicated whether the next byte is the PID or actual data
    // This information can be simply obtained by watching gotTransStartPacket_i
    // but as this is likely needed for IN endpoints, the logic was centralized
    // to safe resources!
    input logic byteIsData_i,
    input logic [USB_DEV_CONF_WID-1:0] deviceConf_i,
    input logic resetDataToggle_i,

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
    //NOTE: EP_IN_data_o will be delayed by one cycle compared to the corresponding handshake signal!
    //TODO provide parameter to adjust this behaviour: option 1: max. speed -> as described above, option 2: half speed + additional logic to await that the data is read before rising the EP_IN_dataAvailable_o flag
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
        .EP_CONF(EP_CONF)
    ) epXin (
        .clk12_i(clk12_i),

        .gotTransStartPacket_i(gotTransStartPacket_i && !isHostIn_i),
        .transStartTokenID_i(transStartTokenID_i),
        .byteIsData_i(byteIsData_i),
        .deviceConf_i(deviceConf_i),
        .resetDataToggle_i(resetDataToggle_i),

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
        .EP_CONF(EP_CONF)
    ) epXout (
        .clk12_i(clk12_i),

        .gotTransStartPacket_i(gotTransStartPacket_i && isHostIn_i),
        .transStartTokenID_i(transStartTokenID_i),
        .deviceConf_i(deviceConf_i),
        .resetDataToggle_i(resetDataToggle_i),

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

    assign {respValid_o, respHandshakePID_o, respPacketID_o} =  isHostIn_i ? 
           {respValid_OUT, respHandshakePID_OUT, respPacketID_OUT}
        :  {respValid_IN, respHandshakePID_IN, respPacketID_IN};

endmodule
