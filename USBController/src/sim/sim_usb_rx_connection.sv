`include "config_pkg.sv"
`include "util_macros.sv"

`ifdef RUN_SIM
module sim_usb_rx_connection (
    input logic CLK,
    input logic USB_DP,
    input logic USB_DN,
    input logic rxRST,

    // Data output interface: synced with clk48!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket // should be tested when rxIsLastByte set to check whether an retrival error occurred
);

    logic dataInP;
    logic dataInP_negedge;

    logic isValidDPSignal;
    logic eopDetected;
    logic ACK_EOP;

    usb_serial_frontend uut_input(
        .clk48(CLK),
        .pinP(USB_DP),
        `MUTE_PIN_CONNECT_EMPTY(pinP_OUT),
        .pinN(USB_DN),
        `MUTE_PIN_CONNECT_EMPTY(pinN_OUT),
        .OUT_EN(1'b0),
        `MUTE_PIN_CONNECT_EMPTY(dataOutP),
        `MUTE_PIN_CONNECT_EMPTY(dataOutN),
        .dataInP(dataInP),
        .dataInP_negedge(dataInP_negedge),
        // Service signals
        .isValidDPSignal(isValidDPSignal),
        .eopDetected(eopDetected),
        .ACK_EOP(ACK_EOP),
        `MUTE_PIN_CONNECT_EMPTY(usbResetDetected),
        `MUTE_PIN_CONNECT_EMPTY(ACK_USB_RST)
    );

    logic rxClkGenRST;
    // TODO we could only reset on switch to receive mode!
    // -> this would allow us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = rxRST; //TODO change the rst -> then it can be used for tx as well!
    logic rxClk12;

    DPPL #() asyncRxCLK (
        .clk48(CLK),
        .RST(rxClkGenRST),
        .a(dataInP),
        .b(dataInP_negedge),
        .readCLK12(rxClk12),
        `MUTE_PIN_CONNECT_EMPTY(DPPLGotSignal)
    );

    logic rxCRCReset;
    logic rxUseCRC16;
    logic rxCRCInput;
    logic rxCRCInputValid;
    logic isValidCRC;

    usb_crc crcEngine (
        .clk12(rxClk12),
        .RST(rxCRCReset),
        .VALID(rxCRCInputValid),
        .rxUseCRC16(rxUseCRC16),
        .data(rxCRCInput),
        .validCRC(isValidCRC),
        `MUTE_PIN_CONNECT_EMPTY(crc)
    );

    logic rxBitStuffRst;
    logic rxNoBitStuffExpected;
    logic rxBitStuffError;
    logic rxBitStuffDataIn;

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12(rxClk12),
        .RST(rxBitStuffRst),
        .isSendingPhase(1'b0),
        .dataIn(rxBitStuffDataIn),
        .ready_valid(rxNoBitStuffExpected),
        `MUTE_PIN_CONNECT_EMPTY(dataOut),
        .error(rxBitStuffError)
    );

    usb_rx uut(
        .clk48(CLK),
        .receiveCLK(rxClk12),
        .rxRST(rxRST),

        // CRC interface
        .rxCRCReset(rxCRCReset),
        .rxUseCRC16(rxUseCRC16),
        .rxCRCInput(rxCRCInput),
        .rxCRCInputValid(rxCRCInputValid),
        .isValidCRC(isValidCRC),

        // Bit stuff interface
        .rxBitStuffRst(rxBitStuffRst),
        .rxBitStuffData(rxBitStuffDataIn),
        .expectNonBitStuffedInput(rxNoBitStuffExpected),
        .rxBitStuffError(rxBitStuffError),

        // Serial frontend interface
        .dataInP(dataInP),
        .isValidDPSignal(isValidDPSignal),
        .eopDetected(eopDetected),
        .ACK_EOP(ACK_EOP),

        // Data output interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData), // Backend indicates that it is able to retrieve the next data byte
        .rxIsLastByte(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid(rxDataValid), // rxData contains valid & new data
        .rxData(rxData), // data to be retrieved
        .keepPacket(keepPacket) // should be tested when rxIsLastByte set to check whether an retrival error occurred
    );
endmodule
`endif
