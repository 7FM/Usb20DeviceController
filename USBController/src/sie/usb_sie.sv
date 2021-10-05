`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

// USB Serial Interface Engine(SIE)
module usb_sie (
    input logic clk48_i,

    // Raw usb pins
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_o,
    output logic USB_DN_o,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP_o,

    // Serial Engine Services:
    // General signals that are important for upper protocol layers: synced with clk48_i!
    output logic usbResetDetected_o, // Indicate that a usb reset detect signal was retrieved!
    input logic ackUsbResetDetect_i, // Acknowledge that usb reset was seen and handled!

    // State information
    output logic txDoneSending_o,
    output logic rxDPPLGotSignal_o,
    input logic isSendingPhase_i,

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48_i!
    input logic rxAcceptNewData_i, // Caller indicates to be able to retrieve the next data byte
    output logic [7:0] rxData_o, // data to be retrieved
    output logic rxIsLastByte_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic keepPacket_o, // should be tested when rxIsLastByte_o set to check whether an retrival error occurred

    // Data Transmit Interface: synced with clk12_i!
    input logic txReqSendPacket_i, // Caller requests sending a new packet
    input logic txDataValid_i, // Indicates that txData_i contains valid & new data
    input logic txIsLastByte_i, // Indicates that the applied txData_i is the last byte to send (is read during handshake: txDataValid_i && txAcceptNewData_o)
    input logic [7:0] txData_i, // Data to be send: First byte should be PID, followed by the user data bytes, CRC is calculated and send automagically
    output logic txAcceptNewData_o // indicates that the send buffer can be filled
    //TODO port to indicate that the packet was sent!
);

    // Source: https://beyondlogic.org/usbnutshell/usb2.shtml
    // Pin connected to USB_DP with 1.5K Ohm resistor -> indicate to be a full speed device: 12 Mbit/s
    assign USB_PULLUP_o = 1'b1; //TODO this can be used to force trigger a reattach without power cycling

    logic isValidDPSignal;

    logic dataOutN_reg, dataOutP_reg, dataInP, dataInP_negedge;

    logic txIsSending;

    logic eopDetected;
    logic ackEOP;

    // Serial frontend which handles the differential input and detects differential encoding errors, EOP and USB resets
    usb_serial_frontend usbSerialFrontend(
        .clk48_i(clk48_i),
        .pinP(USB_DP),
        .pinN(USB_DN),
`ifdef RUN_SIM
        .pinP_o(USB_DP_o),
        .pinN_o(USB_DN_o),
`endif
        .dataOutEn_i(txIsSending),
        .dataOutP_i(dataOutP_reg),
        .dataOutN_i(dataOutN_reg),
        .dataInP_o(dataInP),
        .dataInP_negedge_o(dataInP_negedge),
        // Service signals
        .isValidDPSignal_o(isValidDPSignal),
        .eopDetected_o(eopDetected),
        .ackEOP_i(ackEOP),
        .usbResetDetected_o(usbResetDetected_o),
        .ackUsbRst_i(ackUsbResetDetect_i)
    );

    logic prevTxIsSending;
    logic prevIsSendingPhase;
    always_ff @(posedge clk48_i) begin
        prevTxIsSending <= txIsSending;
        prevIsSendingPhase <= isSendingPhase_i;
    end
    initial begin
        // Start in receiving mode
        prevIsSendingPhase = 1'b0;
        prevTxIsSending = 1'b0;
    end

    // TX module is done sending when a negedge of txIsSending was noticeable
    assign txDoneSending_o = prevTxIsSending && !txIsSending;

    logic rxClkGenRST;
    // Reset on switch to receive mode!
    // -> this allows us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = prevIsSendingPhase && !isSendingPhase_i;

    logic rxClk12;
    logic txClk12;

    DPPL #() asyncRxCLK (
        .clk48_i(clk48_i),
        .rst_i(rxClkGenRST),
        .dpPosEdgeSync_i(dataInP),
        .dpNegEdgeSync_i(dataInP_negedge),
        .readCLK12_o(rxClk12),
        .DPPLGotSignal_o(rxDPPLGotSignal_o)
    );

    assign txClk12 = rxClk12;

    logic crcReset;
    logic rxCRCReset;
    logic txCRCReset;

    logic useCRC16;
    logic rxUseCRC16;
    logic txUseCRC16;

    logic crcInput;
    logic rxCRCInput;
    logic txCRCInput;

    logic crcInputValid;
    logic rxCRCInputValid;
    logic txCRCInputValid;

    logic isValidCRC;
    logic [15:0] crc;

    assign useCRC16 = isSendingPhase_i ? txUseCRC16 : rxUseCRC16;
    assign crcReset = isSendingPhase_i ? txCRCReset : rxCRCReset;
    assign crcInput = isSendingPhase_i ? txCRCInput : rxCRCInput;
    assign crcInputValid = isSendingPhase_i ? txCRCInputValid : rxCRCInputValid;

    usb_crc crcEngine (
        .clk12_i(rxClk12),
        .rst_i(crcReset),
        .valid_i(crcInputValid),
        .useCRC16_i(useCRC16),
        .data_i(crcInput),
        .validCRC_o(isValidCRC),
        .crc_o(crc)
    );

    logic bitStuffRst;
    logic rxBitStuffRst;
    logic txBitStuffRst;

    logic bitStuffNot_Expected_Required;
    logic rxNoBitStuffExpected;
    assign rxNoBitStuffExpected = bitStuffNot_Expected_Required;
    logic txNoBitStuffingNeeded;
    assign txNoBitStuffingNeeded = bitStuffNot_Expected_Required;

    logic rxBitStuffError;

    logic bitStuffDataIn;
    logic rxBitStuffDataIn;
    logic txBitStuffDataIn;

    logic txBitStuffDataOut;

    assign bitStuffRst = isSendingPhase_i ? txBitStuffRst : rxBitStuffRst;
    assign bitStuffDataIn = isSendingPhase_i ? txBitStuffDataIn : rxBitStuffDataIn;

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12_i(rxClk12),
        .rst_i(bitStuffRst),
        .isSendingPhase_i(isSendingPhase_i),
        .data_i(bitStuffDataIn),
        .ready_valid_o(bitStuffNot_Expected_Required),
        .data_o(txBitStuffDataOut),
        .error_o(rxBitStuffError)
    );

    // =====================================================================================================
    // RECEIVE Modules
    // =====================================================================================================

    usb_rx#() usbRxModules(
        .clk48_i(clk48_i),
        .receiveCLK_i(rxClk12),

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
        .ackEOP_o(ackEOP),

        // Data output interface: synced with clk48_i!
        .rxAcceptNewData_i(rxAcceptNewData_i), // Backend indicates that it is able to retrieve the next data byte
        .rxIsLastByte_o(rxIsLastByte_o), // indicates that the current byte at rxData_o is the last one
        .rxDataValid_o(rxDataValid_o), // rxData_o contains valid & new data
        .rxData_o(rxData_o), // data to be retrieved
        .keepPacket_o(keepPacket_o) // should be tested when rxIsLastByte_o set to check whether an retrival error occurred
    );

    // =====================================================================================================
    // TRANSMIT Modules
    // =====================================================================================================

    logic txReqSendPacket_o;
    logic txDataValid_o;
    logic txIsLastByte_o;
    logic [7:0] txData_o;
    logic txAcceptNewData_i;

    usb_tx#() usbTxModules(
        // Inputs
        .clk12_i(txClk12),

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

        // Serial frontend interface
        .sending_o(txIsSending), // indicates that currently data is transmitted
        .dataOutN_reg_o(dataOutN_reg),
        .dataOutP_reg_o(dataOutP_reg),

        // Data interface
        .txReqSendPacket_i(txReqSendPacket_o), // Trigger sending a new packet
        .txIsLastByte_i(txIsLastByte_o), // Indicates that the applied sendData is the last byte to send
        .txDataValid_i(txDataValid_o), // Indicates that sendData contains valid & new data
        .txData_i(txData_o), // Data to be send: First byte should be PID, followed by the user data bytes
        // interface output signals
        .txAcceptNewData_o(txAcceptNewData_i) // indicates that the send buffer can be filled
    );

    cdc_tx txInterfaceClockDomainCrosser(
        .clk1(clk48_i), //TODO this will be changed to an 12 MHz clock later on!
        .txReqSendPacket_i(txReqSendPacket_i),
        .txDataValid_i(txDataValid_i),
        .txIsLastByte_i(txIsLastByte_i),
        .txData_i(txData_i),
        .txAcceptNewData_o(txAcceptNewData_o),

        .clk2(txClk12),
        .txReqSendPacket_o(txReqSendPacket_o),
        .txDataValid_o(txDataValid_o),
        .txIsLastByte_o(txIsLastByte_o),
        .txData_o(txData_o),
        .txAcceptNewData_i(txAcceptNewData_i)
    );

endmodule
