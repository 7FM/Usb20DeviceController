`include "config_pkg.sv"
`include "util_macros.sv"

`ifdef RUN_SIM
module sim_vcd_replay #(
    localparam usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF = usb_ep_pkg::DefaultUsbDeviceEpConfig,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic CLK,
    input logic forceSE0,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_OUT,
    output logic USB_DN_OUT,
    output logic USB_PULLUP
);

    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    logic EP_CLK12;
    logic [ENDPOINTS-2:0] EP_IN_popTransDone_i;
    logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i;
    logic [ENDPOINTS-2:0] EP_IN_popData_i;
    logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o;
    logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o;

    logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i;
    logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i;
    logic [ENDPOINTS-2:0] EP_OUT_dataValid_i;
    logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i;
    logic [ENDPOINTS-2:0] EP_OUT_full_o;

    `TOP_EP_CONSUMER(USB_DEV_EP_CONF) epConsumer (
        .clk12_i(EP_CLK12),

        .EP_IN_popTransDone_o(EP_IN_popTransDone_i),
        .EP_IN_popTransSuccess_o(EP_IN_popTransSuccess_i),
        .EP_IN_popData_o(EP_IN_popData_i),
        .EP_IN_dataAvailable_i(EP_IN_dataAvailable_o),
        .EP_IN_data_i(EP_IN_data_o),

        .EP_OUT_fillTransDone_o(EP_OUT_fillTransDone_i),
        .EP_OUT_fillTransSuccess_o(EP_OUT_fillTransSuccess_i),
        .EP_OUT_dataValid_o(EP_OUT_dataValid_i),
        .EP_OUT_data_o(EP_OUT_data_i),
        .EP_OUT_full_i(EP_OUT_full_o)
    );

    top uut(
        .CLK(CLK),
        .USB_DP(forceSE0 ? 1'b0 : USB_DP),
        .USB_DP_OUT(USB_DP_OUT),
        .USB_DN(forceSE0 ? 1'b0 : USB_DN),
        .USB_DN_OUT(USB_DN_OUT),
        .USB_PULLUP(USB_PULLUP),

`ifdef DEBUG_LEDS
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`endif
        // Endpoint interfaces
        .clk12_o(EP_CLK12),
        .EP_IN_popData_i(EP_IN_popData_i),
        .EP_IN_popTransDone_i(EP_IN_popTransDone_i),
        .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i),
        .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o),
        .EP_IN_data_o(EP_IN_data_o),

        .EP_OUT_dataValid_i(EP_OUT_dataValid_i),
        .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i),
        .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .EP_OUT_full_o(EP_OUT_full_o),
        .EP_OUT_data_i(EP_OUT_data_i)
    );

endmodule
`endif
