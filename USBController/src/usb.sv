`include "config_pkg.sv"

module usb#()(
    input logic clk48,
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

    //TODO add additional layers for USB protocol and proper interfaces, some might be very very timing & latency sensitive
    usb_sie #() serialInterfaceEngine (
        .clk48(clk48),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
`ifdef RUN_SIM
        .USB_DN_OUT(USB_DN_OUT),
        .USB_DP_OUT(USB_DP_OUT),
`endif
        .USB_PULLUP(USB_PULLUP)
    );

endmodule
