`include "config_pkg.sv"

`ifdef RUN_SIM
module sim_usb_tx (
    input logic CLK,

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

    logic USB_DP, USB_DN;

    logic dataOutN_reg;
    logic dataOutP_reg;

    logic txClk12;

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .inCLK(CLK),
        .outCLK(txClk12)
    );

    logic txCRCReset;
    logic txUseCRC16;
    logic txCRCInput;
    logic txCRCInputValid;
    logic [15:0] crc;

    usb_crc crcEngine (
        .clk12(txClk12),
        .RST(txCRCReset),
        .VALID(txCRCInputValid),
        .rxUseCRC16(txUseCRC16),
        .data(txCRCInput),
        /* verilator lint_off PINCONNECTEMPTY */
        .validCRC(),
        /* verilator lint_on PINCONNECTEMPTY */
        .crc(crc)
    );

    usb_tx uut(
        .clk48(CLK),
        .transmitCLK(txClk12),

        .txCRCReset(txCRCReset),
        .txUseCRC16(txUseCRC16),
        .txCRCInput(txCRCInput),
        .txCRCInputValid(txCRCInputValid),
        .reversedCRC16(crc),

        .txReqSendPacket(txReqSendPacket),
        .txAcceptNewData(txAcceptNewData),
        .txIsLastByte(txIsLastByte),
        .txDataValid(txDataValid),
        .txData(txData),

        .sending(sending),

        .dataOutN_reg(dataOutN_reg),
        .dataOutP_reg(dataOutP_reg)
    );

    // assign USB_DP = sending ? dataOutP_reg : 1'bx;
    // assign USB_DN = sending ? dataOutN_reg : 1'bx;
    assign USB_DP = sending ? dataOutP_reg : 1'b1;
    assign USB_DN = sending ? dataOutN_reg : 1'b0;

    sim_usb_rx_connection usbDeserializer(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),
        .rxRST(1'b0),

        // Data output interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .rxData(rxData),
        .keepPacket(keepPacket)
    );
endmodule
`endif
