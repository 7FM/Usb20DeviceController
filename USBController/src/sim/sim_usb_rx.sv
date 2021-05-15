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

    logic dataInP;
    logic dataInP_negedge;
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
        .dataInP_negedge(dataInP_negedge),
        .dataInN(dataInN)
    );

    logic rxClkGenRST;
    // TODO we could only reset on switch to receive mode!
    // -> this would allow us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = outEN_reg; //TODO change the rst -> then it can be used for tx as well!
    logic rxClk12;

    DPPL #() asyncRxCLK (
        .clk48(CLK),
        .RST(rxClkGenRST),
        .a(dataInP),
        .b(dataInP_negedge),
        .readCLK12(rxClk12)
    );

    usb_rx uut(
        .clk48(CLK),
        .receiveCLK(rxClk12),

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
    );
endmodule
`endif