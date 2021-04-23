module usb#()(
    input logic clk48,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);

    //TODO add additional layers for USB protocol and proper interfaces, some might be very very timing & latency sensitive
    usb_sie #() serialInterfaceEngine (
        .clk48(clk48),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
        .USB_PULLUP(USB_PULLUP)
    );

endmodule
