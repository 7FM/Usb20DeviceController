`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_usb_rx (
    input logic CLK,
    input logic CLK12,
    input logic USB_DP,
    input logic USB_DN,
    input logic rxRST,

    // Data output interface: synced with clk12!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket, // should be tested when rxIsLastByte set to check whether an retrival error occurred

    // Timeout interface
    input logic resetTimeout,
    output logic gotTimeout
);

    sim_usb_rx_connection rxCon (
        .CLK(CLK),
        .CLK12(CLK12),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),
        .rxRST(rxRST),
        .rxAcceptNewData(rxAcceptNewData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .rxData(rxData),
        .keepPacket(keepPacket),

        .resetTimeout(resetTimeout),
        .gotTimeout(gotTimeout)
    );

endmodule
`endif
