`include "config_pkg.sv"

module top (
    input logic CLK,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
`ifdef USE_DEBUG_LEDS
    ,output logic LED_R,
    output logic LED_G,
    output logic LED_B
`endif
);
    logic clk48;

`ifndef RUN_SIM
    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(config_pkg::PLL_CLK_DIVR),
        .DIVF(config_pkg::PLL_CLK_DIVF),
        .DIVQ(config_pkg::PLL_CLK_DIVQ),
        .FILTER_RANGE(config_pkg::PLL_CLK_FILTER_RANGE)
    ) clkGen (
        .RESETB(config_pkg::PLL_CLK_RESETB),
        .BYPASS(config_pkg::PLL_CLK_BYPASS),
        .PACKAGEPIN(CLK),
        .PLLOUTCORE(clk48)
    );
`else
    assign clk48 = CLK;
`endif

    usb #() usbDeviceController(
        .clk48(clk48),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
        .USB_PULLUP(USB_PULLUP)
    `ifdef USE_DEBUG_LEDS
        ,.LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B)
    `endif
    );

endmodule
