`include "config_pkg.sv"

module sim_usb_tx (
    input logic CLK,
    output logic USB_DN,
    output logic USB_DP,

    input logic usbResetDetect,
    input logic reqSendPacket,

    // synced with slower 12MHz domain!
    output logic txAcceptNewData,
    input logic txIsLastByte,
    input logic txDataValid,
    input logic [7:0] txData,

    output logic sending
);

    logic dataOutN_reg;
    logic dataOutP_reg;

    usb_tx uut(
        .clk48(CLK),
        .usbResetDetect(usbResetDetect),

        .reqSendPacket(reqSendPacket),
        .txAcceptNewData(txAcceptNewData),
        .txIsLastByte(txIsLastByte),
        .txDataValid(txDataValid),
        .txData(txData),

        .sending(sending),

        .dataOutN_reg(dataOutN_reg),
        .dataOutP_reg(dataOutP_reg)
    );

    assign USB_DN = sending ? dataOutN_reg : 1'bx;
    assign USB_DP = sending ? dataOutP_reg : 1'bx;
endmodule
