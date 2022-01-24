`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

// USB Serial Interface Engine(SIE)
module usb_sie (
    input logic clk48_i,
    input logic clk12_i,

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
    // General signals that are important for upper protocol layers: synced with clk12_i!
    output logic usbResetDetected_o, // Indicate that a usb reset detect signal was retrieved!
    input logic ackUsbResetDetect_i, // Acknowledge that usb reset was seen and handled!

    // State information: synced with clk12_i
    output logic txDoneSending_o,
    input logic isSendingPhase_i,
    // State information: synced with clk48_i
    output logic rxDPPLGotSignal_o,

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk12_i!
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
);

    // Source: https://beyondlogic.org/usbnutshell/usb2.shtml
    // Pin connected to USB_DP with 1.5K Ohm resistor -> indicate to be a full speed device: 12 Mbit/s
    assign USB_PULLUP_o = 1'b1; //TODO this can be used to force trigger a reattach without power cycling
    // On downstream facing ports, RPD resistors (15 kΩ ±5%) must be connected from D+ and D- to ground
    // -> manually add pull down resistors for USB_DP & USB_DN
    /*  Additional manual connections required at PMOD1 when looking from the side to the FPGA (PMOD1 to the left of the micro USB port)
                                 PMOD1                             Micro-USB Port
        top row left -> 1     2    3  4  5  6 <- top right
                        3.3V  GND          USB_DP
                              ^---15k Ohm---^
                        7     8    9 10 11 12
                        3.3V  GND          USB_DP
                              ^---15k Ohm---^
    */

    logic isValidDPSignal;
    logic dataOutN_reg, dataOutP_reg;
    logic dataInP, dataInP_negedge;
    logic txIsSending;

    logic eopDetected;

    logic ackEOP;
    logic ackEOP_CDC;
    cdc_sync ackEopSync(
        .clk(clk48_i),
        .in(ackEOP),
        .out(ackEOP_CDC)
    );
    logic ackUsbResetDetect_CDC;
    cdc_sync ackUsbRstSync(
        .clk(clk48_i),
        .in(ackUsbResetDetect_i),
        .out(ackUsbResetDetect_CDC)
    );

    logic usbResetDetect;
    cdc_sync usbRstSync(
        .clk(clk12_i),
        .in(usbResetDetect),
        .out(usbResetDetected_o)
    );

    // Serial frontend which handles the differential input and detects differential encoding errors, EOP and USB resets
    usb_serial_frontend usbSerialFrontend (
        .clk48_i(clk48_i),
        .pinP(USB_DP),
        .pinN(USB_DN),
`ifdef RUN_SIM
        .pinP_o(USB_DP_o),
        .pinN_o(USB_DN_o),
`endif
        .dataOutEn_i(txIsSending), // clk12
        .dataOutP_i(dataOutP_reg), // clk12
        .dataOutN_i(dataOutN_reg), // clk12
        .dataInP_o(dataInP),
        .dataInP_negedge_o(dataInP_negedge),

        // Service signals for usb_rx
        .isValidDPSignal_o(isValidDPSignal),
        .eopDetected_o(eopDetected),
        .ackEOP_i(ackEOP_CDC), // rxClk12 -> clk48_i

        // Service signals for usb_pe: ep0
        .usbResetDetected_o(usbResetDetect),  // clk48_i -> clk12
        .ackUsbRst_i(ackUsbResetDetect_CDC)  // clk12 -> clk48_i
    );

    logic isSendingPhaseCDC;
    cdc_sync isSendingPhaseSync(
        .clk(clk48_i),
        .in(isSendingPhase_i),
        .out(isSendingPhaseCDC)
    );
    logic prevIsSendingPhase;
    always_ff @(posedge clk48_i) begin
        prevIsSendingPhase <= isSendingPhaseCDC;
    end

    logic prevTxIsSending;
    logic txIsSendingCDC;
    cdc_sync isSendingSync(
        .clk(clk12_i),
        .in(txIsSending),
        .out(txIsSendingCDC)
    );

    always_ff @(posedge clk12_i) begin
        prevTxIsSending <= txIsSendingCDC;
    end
    initial begin
        // Start in receiving mode
        prevIsSendingPhase = 1'b0;
        prevTxIsSending = 1'b0;
    end

    // TX module is done sending when a negedge of txIsSending was noticeable
    assign txDoneSending_o = prevTxIsSending && !txIsSendingCDC;

    logic rxClkGenRST;
    // Reset on switch to receive mode!
    // -> this allows us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = prevIsSendingPhase && !isSendingPhaseCDC;

    logic rxClk12;

    DPPL #() asyncRxCLK (
        .clk48_i(clk48_i),
        .rst_i(rxClkGenRST),
        .dpPosEdgeSync_i(dataInP),
        .dpNegEdgeSync_i(dataInP_negedge),
        .readCLK12_o(rxClk12),
        .DPPLGotSignal_o(rxDPPLGotSignal_o)
    );

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

    usb_crc crcEngine (
        .clk12_i(clk12_i),
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

    assign {useCRC16, crcReset, crcInput, crcInputValid, bitStuffRst, bitStuffDataIn} = 
        isSendingPhase_i ? 
            {txUseCRC16, txCRCReset, txCRCInput, txCRCInputValid, txBitStuffRst, txBitStuffDataIn}
        :
            {rxUseCRC16, rxCRCReset, rxCRCInput, rxCRCInputValid, rxBitStuffRst, rxBitStuffDataIn};

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12_i(clk12_i),
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

    usb_rx#() usbRxModules (
        .clk12_i(clk12_i),
        .rxClk12_i(rxClk12),

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

        // Data output interface: synced with clk12_i!
        .rxAcceptNewData_i(rxAcceptNewData_i), // Backend indicates that it is able to retrieve the next data byte
        .rxIsLastByte_o(rxIsLastByte_o), // indicates that the current byte at rxData_o is the last one
        .rxDataValid_o(rxDataValid_o), // rxData_o contains valid & new data
        .rxData_o(rxData_o), // data to be retrieved
        .keepPacket_o(keepPacket_o) // should be tested when rxIsLastByte_o set to check whether an retrival error occurred
    );

    // =====================================================================================================
    // TRANSMIT Modules
    // =====================================================================================================

    usb_tx#() usbTxModules (
        // Inputs
        .clk12_i(clk12_i),

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
        .txReqSendPacket_i(txReqSendPacket_i), // Trigger sending a new packet
        .txIsLastByte_i(txIsLastByte_i), // Indicates that the applied sendData is the last byte to send
        .txDataValid_i(txDataValid_i), // Indicates that sendData contains valid & new data
        .txData_i(txData_i), // Data to be send: First byte should be PID, followed by the user data bytes
        // interface output signals
        .txAcceptNewData_o(txAcceptNewData_o) // indicates that the send buffer can be filled
    );

endmodule
