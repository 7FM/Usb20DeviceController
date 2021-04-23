// USB Serial Interface Engine(SIE)
module usb_sie(
    input logic clk48,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);

    /*
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
    */
    typedef enum logic[3:0] {
        // TOKEN: last lsb bits are 01
        PID_OUT_TOKEN = 4'b0001,
        PID_IN_TOKEN = 4'b1001,
        PID_SOF_TOKEN = 4'b0101,
        PID_SETUP_TOKEN = 4'b1101,
        // DATA: last lsb bits are 11
        PID_DATA0 = 4'b0011,
        PID_DATA1 = 4'b1011,
        PID_DATA2 = 4'b0111, // unused: High-speed only
        PID_MDATA = 4'b1111, // unused: High-speed only
        // HANDSHAKE: last lsb bits are 10
        PID_HANDSHAKE_ACK = 4'b0010,
        PID_HANDSHAKE_NACK = 4'b1010,
        PID_HANDSHAKE_STALL = 4'b1110,
        PID_HANDSHAKE_NYET = 4'b0110,
        // SPECIAL: last lsb bits are 00
        PID_SPECIAL_PRE__ERR = 4'b1100, // Meaning depends on context
        PID_SPECIAL_SPLIT = 4'b1000, // unused: High-speed only
        PID_SPECIAL_PING = 4'b0100, // unused: High-speed only
        _PID_RESERVED = 4'b0000
    } PID_Types;

    // Source: https://beyondlogic.org/usbnutshell/usb2.shtml
    // Pin connected to USB_DP with 1.5K Ohm resistor -> indicate to be a full speed device: 12 Mbit/s
    assign USB_PULLUP = 1'b1;

    logic dataOutN_reg, dataOutP_reg, dataInP, dataInN, outEN_reg;

    usb_dp usbDifferentialPair(
        .clk48(clk48),
        .pinP(USB_DP),
        .pinN(USB_DN),
        .OUT_EN(outEN_reg),
        .dataOutP(dataOutP_reg),
        .dataOutN(dataOutN_reg),
        .dataInP(dataInP),
        .dataInN(dataInN)
    );

    initial begin
        outEN_reg = 1'b0; // Start in receiving mode
        dataOutP_reg = 1'b1;
        dataOutN_reg = 1'b0;
    end

    //TODO how can we detect that nothing is plugged into our USB port??? / got detached?
    // -> this needs to be considered as state too!

    // =====================================================================================================
    // RECEIVE Modules
    // =====================================================================================================

    typedef enum logic[1:0] {
        RX_WAIT_FOR_SYNC,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_DPLL
    } RxStates;

    // TODO errror handling
    // Error handling relevant signals
    logic receiveBitStuffingError;
    logic pidValid;
    logic isValidCRC;

    logic isValidDPSig;

    assign isValidDPSig = dataInN ^ dataInP;

    // State variables
    RxStates rxState;
    PID_Types rxPID;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!
    logic dropPacket; // Drop reason might be i.e. receive errors!

    // Current signals
    logic receiveCLK;
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    // Detections
    logic nonBitStuffedInput;
    logic eopDetected;
    logic syncDetect;

    // Reset signals
    logic rxInputShiftRegReset;

    logic rxEopDetectorReset; // Requires explicit RST to clear eop flag again
    logic rxBitUnstuffingReset;
    logic rxNRZiDecodeReset;
    logic receiveClkGenRST;

    // TODO we could only reset on switch to receive mode!
    // -> this would allow us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    //TODO is an reset needed before starting receive?
    assign receiveClkGenRST = outEN_reg || rxState == RX_RST_DPLL;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitUnstuffingReset = 1'b0;


    //===================================================
    // Initialization
    //===================================================
    initial begin
        rxState = RX_WAIT_FOR_SYNC;
        dropPacket = 1'b0;
        lastByteValidCRC = 1'b1;
    end

    //===================================================
    // State transitions
    //===================================================
    RxStates next_rxState, rxStateAdd1;
    PID_Types next_rxPID;
    logic next_dropPacket, next_lastByteValidCRC;

    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxEopDetectorReset = 1'b1; // Per default reset EOP detection

        next_rxState = rxState;
        next_rxPID = rxPID;
        next_dropPacket = dropPacket;
        next_lastByteValidCRC = lastByteValidCRC;

        unique case (rxState)
            RX_WAIT_FOR_SYNC: begin
                if (syncDetect) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                    //TODO trigger required resets right before payload data arrives
                    // Input shift register needs valid counter reset to be aligned with the incoming packet content
                    rxInputShiftRegReset = 1'b1;
                end
            end
            RX_GET_PID: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Also there may not be invalid differential pair signals as we expect the PID to be send!
                // Sanity check: was PID correctly received?
                next_dropPacket = dropPacket || receiveBitStuffingError || !isValidDPSig || (inputBufFull && !pidValid);

                if (inputBufFull) begin
                    // Save the PID for further decisions
                    next_rxPID = inputBuf[3:0];
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end
            end
            RX_WAIT_FOR_EOP: begin
                //TODO would be nice to integrate some isValidDPSig checks, but this might break logic very very easily!

                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = dropPacket || receiveBitStuffingError || (eopDetected && !lastByteValidCRC);

                // We need the EOP detection -> clear RST flag
                rxEopDetectorReset = 1'b0;

                if (eopDetected) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end else if (inputBufFull) begin
                    next_lastByteValidCRC = isValidCRC;
                    //TODO further processing is required! i.e. give data to next stage for processing
                    //TODO we probably do not want to give the crc data to the next stage how can we do so? just assume that the backend will ignore it?
                end
            end
            RX_RST_DPLL: begin
                // TODO we should probably publish the final dropPacket value!

                // Trigger some resets
                // TODO is a RST needed for the NRZI decoder?
                rxNRZiDecodeReset = 1'b1;

                // reset drop state
                next_dropPacket = 1'b0;
                // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
                next_lastByteValidCRC = 1'b1;
            end
            default: begin
                // Use default values
            end
        endcase
    end
    always_ff @(posedge receiveCLK) begin
        rxState <= next_rxState;
        rxPID <= next_rxPID;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
    end

    eop_detect eopDetector(
        .clk48(clk48),
        .RST(rxEopDetectorReset),
        .dataInP(dataInP),
        .dataInN(dataInN),
        .eop(eopDetected)
    );

    DPPL #() asyncRxCLK (
        .clk48(clk48),
        .RST(receiveClkGenRST),
        .a(dataInP), //TODO
        .b(dataInN), //TODO
        .readCLK12(receiveCLK),
    );

    //TODO reuse
    nrzi_encoder nrziDecoder(
        .clk12(receiveCLK),
        .RST(rxNRZiDecodeReset),
        .data(dataInP),
        .OUT(nrziDecodedInput)
    );

    //TODO reuse
    usb_bit_unstuff receiveBitUnstuffing(
        .clk12(receiveCLK),
        .RST(rxBitUnstuffingReset),
        .data(nrziDecodedInput),
        .valid(nonBitStuffedInput),
        .error(receiveBitStuffingError)
    );

    logic _syncDetect;
    sync_detect #() packetBeginDetector(
        .receivedData(inputBuf[7:4]),
        .SYNC(_syncDetect)
    );
    assign syncDetect = _syncDetect && rxState == RX_WAIT_FOR_SYNC;

    input_shift_reg #() inputDeserializer(
        .clk12(receiveCLK),
        .RST(rxInputShiftRegReset),
        .EN(nonBitStuffedInput),
        .IN(nrziDecodedInput),
        .dataOut(inputBuf),
        .bufferFull(inputBufFull)
    );

    pid_check #() pidChecker (
        // Order does not matter as the check is actually commutative
        .pidP(inputBuf[7:4]),
        .pidN(inputBuf[3:0]),
        .isValid(pidValid)
    );

    logic useCRC5;
    // Needs thight timing -> use input buffer directly
    // CRC5 is only used for token packets -> identified by 2 lsb bits
    assign useCRC5 = inputBuf[1:0] == 2'b01;

    //TODO reuse
    logic [15:0] _unused_crc16;
    usb_crc crcEngine (
        .clk12(receiveCLK),
        .RST(rxState == RX_GET_PID), // Required at every new packet, can be a wire
        //TODO we need to exclude undesired fields too: this might already work as PID fields are excluded by design of the RST signal being high during PID reception
        .VALID(nonBitStuffedInput), // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
        .crc5_or_16(useCRC5), // Indicate which CRC should type should be calculated/checked, needs to be set when RST is set high
        .data(nrziDecodedInput),
        .validCRC(isValidCRC),
        .crc(_unused_crc16) //TODO only needed for transmission also ensure that it will be send in revere order (MSb first)!
    );


    // =====================================================================================================
    // TRANSMIT Modules
    // =====================================================================================================

    /*
    logic transmitCLK;

    clock_gen #(
        .DIVIDE_LOG_2($clog2(4))
    ) clkDiv4 (
        .inCLK(clk48),
        .outCLK(transmitCLK)
    );

    usb_bit_stuff transmitBitStuffing(
        .clk12(transmitCLK),
        .RST(), //TODO
        .data(), //TODO
        .ready(), //TODO
        .outData() //TODO
    );
    */

    /*
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
