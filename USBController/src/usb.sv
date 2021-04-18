module usb(
    input logic CLK,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);

usb_sie #() serialInterfaceEngine (
    .CLK(CLK),
    .USB_DN(USB_DN),
    .USB_DP(USB_DP),
    .USB_PULLUP(USB_PULLUP)
);

endmodule
