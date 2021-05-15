`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_top (
    input logic CLK,
    input logic USB_DP,
    output logic USB_DP_OUT,
    input logic USB_DN,
    output logic USB_DN_OUT,
    output logic USB_PULLUP
);

    top uut(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DP_OUT(USB_DP_OUT),
        .USB_DN(USB_DN),
        .USB_DN_OUT(USB_DN_OUT),
        .USB_PULLUP(USB_PULLUP)
    );
endmodule
`endif
