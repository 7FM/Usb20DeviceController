module usb#()(
    input logic clk48,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);

usb_sie #() serialInterfaceEngine (
    .clk48(clk48),
    .USB_DN(USB_DN),
    .USB_DP(USB_DP),
    .USB_PULLUP(USB_PULLUP)
);

endmodule
