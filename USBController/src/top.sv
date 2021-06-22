`include "config_pkg.sv"

module top (
    input logic CLK,
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_OUT,
    output logic USB_DN_OUT,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP
);
    logic clk48;

`ifndef FALLBACK_DEVICE
`ifdef LATTICE_ICE_40
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
    // Device not supported
`endif
`else
    assign clk48 = CLK;
`endif

    usb #() usbDeviceController(
        .clk48_i(clk48),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
`ifdef RUN_SIM
        .USB_DN_o(USB_DN_OUT),
        .USB_DP_o(USB_DP_OUT),
`endif
        .USB_PULLUP_o(USB_PULLUP)
    );

endmodule
