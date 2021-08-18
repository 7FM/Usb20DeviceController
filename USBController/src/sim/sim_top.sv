`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_top (
    input logic CLK,
    input logic dummyPin,
    input logic rxRST,

    // Data send interface: synced with clk48!
    input logic txReqSendPacket,
    output logic txAcceptNewData,
    input logic txIsLastByte,
    input logic txDataValid,
    input logic [7:0] txData,

    output logic sending,

    // Data receive interface: synced with clk48!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket
);

    logic USB_DP;
    logic USB_DP_OUT;
    logic USB_DN;
    logic USB_DN_OUT;
    logic USB_PULLUP;

    top uut(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DP_OUT(USB_DP_OUT),
        .USB_DN(USB_DN),
        .USB_DN_OUT(USB_DN_OUT),
        .USB_PULLUP(USB_PULLUP)
    );

    sim_usb_tx_connection hostTxImitator(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),

        // Data send interface: synced with clk48!
        .txReqSendPacket(txReqSendPacket),
        .txAcceptNewData(txAcceptNewData),
        .txIsLastByte(txIsLastByte),
        .txDataValid(txDataValid),
        .txData(txData),

        .sending(sending)
    );

    sim_usb_rx_connection hostRxImitator(
        .CLK(CLK),
        .USB_DP(USB_DP_OUT),
        .USB_DN(USB_DN_OUT),
        .rxRST(rxRST),

        // Data output interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .rxData(rxData),
        .keepPacket(keepPacket)
    );


endmodule
`endif
