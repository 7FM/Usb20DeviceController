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

`ifdef USE_DEBUG_LEDS
    ,output logic LED_R,
    output logic LED_G,
    output logic LED_B
`endif
);

    logic dataInP;
    logic dataInN;

    usb_dp uut_input(
        .clk48(CLK),
        .pinP(USB_DP),
        .pinP_OUT(),
        .pinN(USB_DN),
        .pinN_OUT(),
        .OUT_EN(outEN_reg),
        .dataOutP(),
        .dataOutN(),
        .dataInP(dataInP),
        .dataInN(dataInN)
    );

    usb_rx uut(
        .clk48(CLK),
        .dataInP(dataInP),
        .dataInN(dataInN),
        .outEN_reg(outEN_reg),
        .ACK_USB_RST(ACK_USB_RST),
        .usbResetDetect(usbResetDetect),
        // Data output interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData), // Backend indicates that it is able to retrieve the next data byte
        .rxIsLastByte(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid(rxDataValid), // rxData contains valid & new data
        .rxData(rxData), // data to be retrieved
        .keepPacket(keepPacket) // should be tested when rxIsLastByte set to check whether an retrival error occurred
`ifdef USE_DEBUG_LEDS
        ,.LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B)
`endif
    );
endmodule
`endif