`include "config_pkg.sv"

// import config_pkg::*;

module sim_top (
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

    top uut(
        .CLK(CLK),
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
