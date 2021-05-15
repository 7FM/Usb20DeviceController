`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_usb_rx (
    input logic CLK,
    input logic USB_DP,
    input logic USB_DN,
    input logic outEN_reg,
    input logic ACK_USB_RST,
    output logic usbResetDetect,

    // Data output interface: synced with clk48!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket // should be tested when rxIsLastByte set to check whether an retrival error occurred
);

    sim_usb_rx_connection rxCon (
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),
        .outEN_reg(outEN_reg),
        .ACK_USB_RST(ACK_USB_RST),
        .usbResetDetect(usbResetDetect),
        .rxAcceptNewData(rxAcceptNewData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .rxData(rxData),
        .keepPacket(keepPacket)
    );

endmodule
`endif
