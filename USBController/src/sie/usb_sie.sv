`include "config_pkg.sv"
`include "sie_defs_pkg.sv"

// USB Serial Interface Engine(SIE)
module usb_sie (
    input logic clk48,

    // Raw usb pins
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_OUT,
    output logic USB_DN_OUT,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP,

    // Serial Engine Services:
    // General signals that are important for upper protocol layers: synced with clk48!
    output logic usbResetDetected, // Indicate that a usb reset detect signal was retrieved!
    input logic ackUsbResetDetect, // Acknowledge that usb reset was seen and handled!

    // State information
    input logic isSendingPhase,

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48!
    input logic rxAcceptNewData, // Caller indicates to be able to retrieve the next data byte
    output logic [7:0] rxData, // data to be retrieved
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic keepPacket, // should be tested when rxIsLastByte set to check whether an retrival error occurred

    // Data Transmit Interface: synced with clk48!
    input logic txReqSendPacket, // Caller requests sending a new packet
    input logic txDataValid, // Indicates that txData contains valid & new data
    input logic txIsLastByte, // Indicates that the applied txData is the last byte to send (is read during handshake: txDataValid && txAcceptNewData)
    input logic [7:0] txData, // Data to be send: First byte should be PID, followed by the user data bytes, CRC is calculated and send automagically
    output logic txAcceptNewData // indicates that the send buffer can be filled
    //TODO port to indicate that the packet was sent!
);

    // Source: https://beyondlogic.org/usbnutshell/usb2.shtml
    // Pin connected to USB_DP with 1.5K Ohm resistor -> indicate to be a full speed device: 12 Mbit/s
    assign USB_PULLUP = 1'b1;

    logic isValidDPSignal;

    logic dataOutN_reg, dataOutP_reg, dataInP, dataInP_negedge, dataInN;

    logic txIsSending;

    logic eopDetected;
    logic ACK_EOP;

    // Serial frontend which handles the differential input and detects differential encoding errors, EOP and USB resets
    usb_dp usbDifferentialPair(
        .clk48(clk48),
        .pinP(USB_DP),
        .pinN(USB_DN),
`ifdef RUN_SIM
        .pinP_OUT(USB_DP_OUT),
        .pinN_OUT(USB_DN_OUT),
`endif
        .OUT_EN(txIsSending),
        .dataOutP(dataOutP_reg),
        .dataOutN(dataOutN_reg),
        .dataInP(dataInP),
        .dataInP_negedge(dataInP_negedge),
        // Service signals
        .isValidDPSignal(isValidDPSignal),
        .eopDetected(eopDetected),
        .ACK_EOP(ACK_EOP),
        .usbResetDetected(usbResetDetected),
        .ACK_USB_RST(ackUsbResetDetect)
    );

    logic prevIsSendingPhase;
    always_ff @(posedge clk48) begin
        prevIsSendingPhase <= isSendingPhase;
    end

    initial begin
        prevIsSendingPhase = 1'b0; // Start in receiving mode
    end

    logic rxClkGenRST;
    // Reset on switch to receive mode!
    // -> this allows us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    assign rxClkGenRST = prevIsSendingPhase && ~isSendingPhase;

    logic rxClk12;
    logic txClk12;

    DPPL #() asyncRxCLK (
        .clk48(clk48),
        .RST(rxClkGenRST),
        .a(dataInP),
        .b(dataInP_negedge),
        .readCLK12(rxClk12)
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

    assign useCRC16 = isSendingPhase ? txUseCRC16 : rxUseCRC16;
    assign crcReset = isSendingPhase ? txCRCReset : rxCRCReset;
    assign crcInput = isSendingPhase ? txCRCInput : rxCRCInput;
    assign crcInputValid = isSendingPhase ? txCRCInputValid : rxCRCInputValid;

    usb_crc crcEngine (
        .clk12(rxClk12),
        .RST(crcReset),
        .VALID(crcInputValid),
        .rxUseCRC16(useCRC16),
        .data(crcInput),
        .validCRC(isValidCRC),
        .crc(crc)
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

    assign bitStuffRst = isSendingPhase ? txBitStuffRst : rxBitStuffRst;
    assign bitStuffDataIn = isSendingPhase ? txBitStuffDataIn : rxBitStuffDataIn;

    usb_bit_stuffing_wrapper bitStuffWrap (
        .clk12(rxClk12),
        .RST(bitStuffRst),
        .isSendingPhase(isSendingPhase),
        .dataIn(bitStuffDataIn),
        .ready_valid(bitStuffNot_Expected_Required),
        .dataOut(txBitStuffDataOut),
        .error(rxBitStuffError)
    );

    // =====================================================================================================
    // RECEIVE Modules
    // =====================================================================================================

    logic rxRST = isSendingPhase; //TODO

    usb_rx#() usbRxModules(
        .clk48(clk48),
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

    // =====================================================================================================
    // TRANSMIT Modules
    // =====================================================================================================

    usb_tx#() usbTxModules(
        // Inputs
        .clk48(clk48),
        .transmitCLK(txClk12),

        // CRC interface
        .txCRCReset(txCRCReset),
        .txUseCRC16(txUseCRC16),
        .txCRCInput(txCRCInput),
        .txCRCInputValid(txCRCInputValid),
        .reversedCRC16(crc),

        // Bit stuff interface
        .txBitStuffRst(txBitStuffRst),
        .txBitStuffDataIn(txBitStuffDataIn),
        .txBitStuffDataOut(txBitStuffDataOut),
        .txNoBitStuffingNeeded(txNoBitStuffingNeeded),

        // Data interface
        .txReqSendPacket(txReqSendPacket), // Trigger sending a new packet
        .txIsLastByte(txIsLastByte), // Indicates that the applied sendData is the last byte to send
        .txDataValid(txDataValid), // Indicates that sendData contains valid & new data
        .txData(txData), // Data to be send: First byte should be PID, followed by the user data bytes
        // interface output signals
        .txAcceptNewData(txAcceptNewData), // indicates that the send buffer can be filled

        // Serial frontend interface
        .sending(txIsSending), // indicates that currently data is transmitted
        .dataOutN_reg(dataOutN_reg), 
        .dataOutP_reg(dataOutP_reg)
    );

    /*
    //TODO split collected documentation and move it to the appropriate SV modules!
    Differential Signal:
                                 __   _     _   _     ____
                            D+ :   \_/ \___/ \_/ \___/
                                    _   ___   _           
                            D- : __/ \_/   \_/ \__________
    Differential decoding:          K J K K J K J 0 0 J J
                                                  ^------------ SM0/SE0 with D+=D-=LOW analogously exists SM1/SE1 with D+=D-=HIGH
    NRZI decoding:                  0 0 0 1 0 0 0 ? ? 0 1
    (Non-Return-to-Zero Inverted): logical 0 is transmitted as transition -> either from J to K or from K to J
                                   logical 1 is transmitted as NO transition -> stay at previous level

    //TODO bit stuffing: 7 consequetive 1 bits are considered as error -> 0 are forcefully introduced after 6 ones to change line levels!

    Source: https://beyondlogic.org/usbnutshell/usb3.shtml
    DATA is transmitted with LSb First
    Common USB Packet Fields:
    - 8 Low Bits for sync
    - 8 bits PID: actually only 4 but they are inverted and repeated PID0, PID1, PID2, PID3, ~PID0, ~PID1, ~PID2, ~PID3
        Possible Values:
        Group    | PID[3:0] |  Packet Identifier
        -----------------------------------------------
        Token    |   0001   |  OUT Token
                 |   1001   |  IN Token
                 |   0101   |  SOF Token (Start Of Frame)
                 |   1101   |  Setup Token
        -----------------------------------------------
        Data     |   0011   |  DATA0
                 |   1011   |  DATA1
                 |   0111   |  DATA2 (only in High Speed mode)
                 |   1111   |  MDATA (only in High Speed mode)
        -----------------------------------------------
        Handshake|   0010   |  ACK Handshake
                 |   1010   |  NACK Handshake
                 |   1110   |  STALL Handshake
                 |   0110   |  NYET (No Response Yet)
        -----------------------------------------------
        Special  |   1100   |  PREamble
                 |   1100   |  ERR
                 |   1000   |  Split
                 |   0100   |  Ping
            MSb -----^  ^--------------- LSb
    - 7 bits ADDR: ADDR=0 is invalid for an device, but new devices without an address yet MUST respond to packets addressed to ADDR = 0 (I guess this initiates the device setup)
    - 4 bits ENDP: endpoint field for 16 different endpoints: probably usable for different services within one device?
    - 5 bit CRC -> CRC5: for TOKEN packets CRC are performed on the data within the packet payload
    - 16 bit CRC -> CRC16: for DATA packets CRC are performed on the data within the packet payload
    - 3 bit EOP: End Of Packet, signalled by Single Ended Zero (SE0): pull both lines of differential Pair to 0 for 2 bit durations followed by a J for 1 bit time

    CRC:
        - over all fields except PID,EOP,SYNC
        - CRC is calculated before bit stuffing is performed!

    Packets:
        - Token Packets:          |Sync|PID|ADDR|ENDP|CRC5 |EOP| 8 + 8 + 7 + 4 + 5 + 3 = 8 bits SYNC + 24 bits payload + 3 bits EOP
        - Data Packets:           |Sync|PID|   DATA  |CRC16|EOP| 8 + 8 + 8 * (0-1024) + 16 + 3 = 8 bits SYNC + (8*(0-1024) + 24) bits payload + 3 bits EOP
            Maximum data payload size for low-speed devices is 8 BYTES.
            Maximum data payload size for full-speed devices is 1023 BYTES.
            Maximum data payload size for high-speed devices is 1024 BYTES.
            Data must be sent in multiples of bytes
        - Handshake Packets:      |Sync|PID|EOP| 8 + 8 + 3 = 8 bits SYNC + 8 bits payload + 3 bits EOP
            ACK - Acknowledgment that the packet has been successfully received.
            NAK - Reports that the device temporary cannot send or received data. Also used during interrupt transactions to inform the host there is no data to send.
            STALL - The device finds its in a state that it requires intervention from the host.
        - Start of Frame Packets: |Sync|PID| Frame Number |CRC5 |EOP| 8 + 8 + (7 + 4) + 5 + 3 = 8 bits SYNC + 24 bits payload + 3 bits EOP
            Frame Number = 11 bits
            is sent regulary by the host: every 1ms ± 500ns on a full speed bus or every 125 µs ± 0.0625 µs on a high speed bus
    */


endmodule
