`include "config_pkg.sv"
`include "util_macros.sv"

`ifdef RUN_SIM
module sim_usb_tx (
    input logic CLK,

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

    logic USB_DP, USB_DN;

    logic dataOutN_reg;
    logic dataOutP_reg;

    logic txClk12;

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .clk_i(CLK),
        .clk_o(txClk12)
    );

    logic txCRCReset;
    logic txUseCRC16;
    logic txCRCInput;
    logic txCRCInputValid;
    logic [15:0] crc;

    usb_crc crcEngine (
        .clk12_i(txClk12),
        .rst_i(txCRCReset),
        .valid_i(txCRCInputValid),
        .useCRC16_i(txUseCRC16),
        .data_i(txCRCInput),
        `MUTE_PIN_CONNECT_EMPTY(validCRC_o),
        .crc_o(crc)
    );

    logic txBitStuffRst;
    logic txNoBitStuffingNeeded;
    logic txBitStuffDataIn;
    logic txBitStuffDataOut;

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12_i(txClk12),
        .rst_i(txBitStuffRst),
        .isSendingPhase_i(1'b1),
        .data_i(txBitStuffDataIn),
        .ready_valid_o(txNoBitStuffingNeeded),
        .data_o(txBitStuffDataOut),
        `MUTE_PIN_CONNECT_EMPTY(error_o)
    );


    usb_tx uut(
        .clk48_i(CLK),
        .transmitCLK_i(txClk12),

        // CRC interface
        .txCRCReset_o(txCRCReset),
        .txUseCRC16_o(txUseCRC16),
        .txCRCInput_o(txCRCInput),
        .txCRCInputValid_o(txCRCInputValid),
        .reversedCRC16_i(crc),

        // Bit stuff interface
        .txBitStuffRst_o(txBitStuffRst),
        .txBitStuffDataIn_o(txBitStuffDataIn),
        .txBitStuffDataOut_i(txBitStuffDataOut),
        .txNoBitStuffingNeeded_i(txNoBitStuffingNeeded),

        // Data interface
        .txReqSendPacket_i(txReqSendPacket),
        .txAcceptNewData_o(txAcceptNewData),
        .txIsLastByte_i(txIsLastByte),
        .txDataValid_i(txDataValid),
        .txData_i(txData),

        // Serial frontend interface
        .sending_o(sending),
        .dataOutN_reg_o(dataOutN_reg),
        .dataOutP_reg_o(dataOutP_reg)
    );

    assign USB_DP = sending ? dataOutP_reg : 1'b1;
    assign USB_DN = sending ? dataOutN_reg : 1'b0;

    sim_usb_rx_connection usbDeserializer(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),
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
