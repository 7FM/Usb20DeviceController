`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_usb_tx (
    input logic CLK,
    output logic USB_DP,
    output logic USB_DN,

    input logic usbResetDetect,
    input logic reqSendPacket,

    // Data send interface
    // synced with slower 12MHz domain!
    output logic txAcceptNewData,
    input logic txIsLastByte,
    input logic txDataValid,
    input logic [7:0] txData,

    output logic sending
);

    logic dataOutN_reg;
    logic dataOutP_reg;

    logic txClk12;

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .inCLK(CLK),
        .outCLK(txClk12)
    );

    usb_tx uut(
        .clk48(CLK),
        .transmitCLK(txClk12),
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

    assign USB_DP = sending ? dataOutP_reg : 1'bx;
    assign USB_DN = sending ? dataOutN_reg : 1'bx;
endmodule
`endif
