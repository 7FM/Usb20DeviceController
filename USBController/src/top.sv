`include "config_pkg.sv"
`include "usb_ep_pkg.sv"

module top #(
    localparam usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF = usb_ep_pkg::DefaultUsbDeviceEpConfig,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic CLK,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_OUT,
    output logic USB_DN_OUT,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP,

`ifdef RUN_SIM
    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    output logic clk12_o,
    input logic [ENDPOINTS-2:0] EP_IN_popTransDone_i,
    input logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_IN_popData_i,
    output logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o,
    output logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o, // Note the EP dependent timing conditions compared to the EP_IN_dataAvailable_o flag!

    input logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i,
    input logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_OUT_dataValid_i,
    input logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i,
    output logic [ENDPOINTS-2:0] EP_OUT_full_o
`endif
);
    logic clk48;
    logic clk12;

`ifndef FALLBACK_DEVICE
`ifdef LATTICE_ICE_40
    SB_PLL40_2_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(config_pkg::PLL_CLK_DIVR),
        .DIVF(config_pkg::PLL_CLK_DIVF),
        .DIVQ(config_pkg::PLL_CLK_DIVQ),
        .FILTER_RANGE(config_pkg::PLL_CLK_FILTER_RANGE)
    ) clkGen (
        .RESETB(config_pkg::PLL_CLK_RESETB),
        .BYPASS(config_pkg::PLL_CLK_BYPASS),
        .PACKAGEPIN(CLK),
        .PLLOUTGLOBALA(clk12),
        .PLLOUTGLOBALB(clk48)
    );
`else
    // Device not supported
`endif
`else
    assign clk48 = CLK;

    clock_gen #(
        .DIVIDE_LOG_2(2)
    ) clk12Generator (
        .clk_i(clk48),
        .clk_o(clk12)
    );

    assign clk12_o = clk12;
`endif

`ifndef RUN_SIM
    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    logic [ENDPOINTS-2:0] EP_IN_popTransDone_i;
    logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i;
    logic [ENDPOINTS-2:0] EP_IN_popData_i;
    logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o;
    logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o; // Note the EP dependent timing conditions compared to the EP_IN_dataAvailable_o flag!

    logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i;
    logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i;
    logic [ENDPOINTS-2:0] EP_OUT_dataValid_i;
    logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i;
    logic [ENDPOINTS-2:0] EP_OUT_full_o;
`endif

    usb #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) usbDeviceController(
        .clk48_i(clk48),
        .clk12_i(clk12),

        .USB_DN(USB_DN),
        .USB_DP(USB_DP),

`ifdef DEBUG_LEDS
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`endif

`ifdef RUN_SIM
        .USB_DN_o(USB_DN_OUT),
        .USB_DP_o(USB_DP_OUT),
`endif
        .USB_PULLUP_o(USB_PULLUP),

        // Endpoint interfaces
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
