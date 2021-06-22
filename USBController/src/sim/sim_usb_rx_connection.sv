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
        .clk48_i(CLK),
        .pinP(USB_DP),
        `MUTE_PIN_CONNECT_EMPTY(pinP_o),
        .pinN(USB_DN),
        `MUTE_PIN_CONNECT_EMPTY(pinN_o),
        .dataOutEn_i(1'b0),
        `MUTE_PIN_CONNECT_EMPTY(dataOutP_i),
        `MUTE_PIN_CONNECT_EMPTY(dataOutN_i),
        .dataInP_o(dataInP),
        .dataInP_negedge_o(dataInP_negedge),
        // Service signals
        .isValidDPSignal_o(isValidDPSignal),
        .eopDetected_o(eopDetected),
        .ackEOP_i(ACK_EOP),
        `MUTE_PIN_CONNECT_EMPTY(usbResetDetected_o),
        `MUTE_PIN_CONNECT_EMPTY(ackUsbRst_i)
    );

    logic rxClkGenRST;
    // TODO we could only reset on switch to receive mode!
    // -> this would allow us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = rxRST; //TODO change the rst -> then it can be used for tx as well!
    logic rxClk12;

    DPPL #() asyncRxCLK (
        .clk48_i(CLK),
        .rst_i(rxClkGenRST),
        .dpPosEdgeSync_i(dataInP),
        .dpNegEdgeSync_i(dataInP_negedge),
        .readCLK12_o(rxClk12),
        `MUTE_PIN_CONNECT_EMPTY(DPPLGotSignal_o)
    );

    logic rxCRCReset;
    logic rxUseCRC16;
    logic rxCRCInput;
    logic rxCRCInputValid;
    logic isValidCRC;

    usb_crc crcEngine (
        .clk12_i(rxClk12),
        .rst_i(rxCRCReset),
        .valid_i(rxCRCInputValid),
        .useCRC16_i(rxUseCRC16),
        .data_i(rxCRCInput),
        .validCRC_o(isValidCRC),
        `MUTE_PIN_CONNECT_EMPTY(crc_o)
    );

    logic rxBitStuffRst;
    logic rxNoBitStuffExpected;
    logic rxBitStuffError;
    logic rxBitStuffDataIn;

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12_i(rxClk12),
        .rst_i(rxBitStuffRst),
        .isSendingPhase_i(1'b0),
        .data_i(rxBitStuffDataIn),
        .ready_valid_o(rxNoBitStuffExpected),
        `MUTE_PIN_CONNECT_EMPTY(data_o),
        .error_o(rxBitStuffError)
    );

    usb_rx uut(
        .clk48_i(CLK),
        .receiveCLK_i(rxClk12),
        .rxRST_i(rxRST),

        // CRC interface
        .rxCRCReset_o(rxCRCReset),
        .rxUseCRC16_o(rxUseCRC16),
        .rxCRCInput_o(rxCRCInput),
        .rxCRCInputValid_o(rxCRCInputValid),
        .isValidCRC_i(isValidCRC),

        // Bit stuff interface
        .rxBitStuffRst_o(rxBitStuffRst),
        .rxBitStuffData_o(rxBitStuffDataIn),
        .expectNonBitStuffedInput_i(rxNoBitStuffExpected),
        .rxBitStuffError_i(rxBitStuffError),

        // Serial frontend interface
        .dataInP_i(dataInP),
        .isValidDPSignal_i(isValidDPSignal),
        .eopDetected_i(eopDetected),
        .ackEOP_o(ACK_EOP),

        // Data output interface: synced with clk48!
        .rxAcceptNewData_i(rxAcceptNewData), // Backend indicates that it is able to retrieve the next data byte
        .rxIsLastByte_o(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid_o(rxDataValid), // rxData contains valid & new data
        .rxData_o(rxData), // data to be retrieved
        .keepPacket_o(keepPacket) // should be tested when rxIsLastByte set to check whether an retrival error occurred
    );
endmodule
`endif
