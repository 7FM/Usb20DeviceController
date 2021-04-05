module top (
    input logic CLK,
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);
    logic usbCLK;

`ifndef RUN_SIM
    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(`PLL_CLK_DIVR),
        .DIVF(`PLL_CLK_DIVF),
        .DIVQ(`PLL_CLK_DIVQ),
        .FILTER_RANGE(`PLL_CLK_FILTER_RANGE)
    ) clkGen (
        .RESETB(`PLL_CLK_RESETB),
        .BYPASS(`PLL_CLK_BYPASS),
        .PACKAGEPIN(CLK),
        .PLLOUTCORE(usbCLK)
    );
`else
    assign usbCLK = CLK;
`endif


endmodule
