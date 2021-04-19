// USB Serial Interface Engine(SIE)
module usb_sie(
    input logic clk48,
    inout logic USB_DN,
    inout logic USB_DP,
    output logic USB_PULLUP
);

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

    // =====================================================================================================
    // RECEIVE Modules
    // =====================================================================================================

    logic isValidDPSig;
    assign isValidDPSig = dataInN ^ dataInP;

    logic receiveCLK;
    logic receiveClkGenRST;

    logic eopDetected;

    //TODO how to stall during possible EOP / backtrack read bits (i.e. CRC might be bad)
    eop_detect eopDetector(
        .clk48(clk48),
        .RST(), //TODO Requires explicit RST to clear eop flag again
        .dataInP(dataInP),
        .dataInN(dataInN),
        .eop(eopDetected)
    );

    //TODO is an reset needed before starting receive?
    assign receiveClkGenRST = outEN_reg || eopDetected;

    DPPL #() asyncRxCLK (
        .clk48(clk48),
        .RST(receiveClkGenRST),
        .a(dataInP), //TODO
        .b(dataInN), //TODO
        .readCLK12(receiveCLK),
    );

    logic nrziDecodedInput;

    nrzi_encoder nrziDecoder(
        .clk12(receiveCLK),
        .RST(), //TODO
        .data(dataInP),
        .OUT(nrziDecodedInput)
    );

    // TODO errror handling
    logic nonBitStuffedInput, receiveBitStuffingError;

    usb_bit_unstuff receiveBitUnstuffing(
        .clk12(receiveCLK),
        .RST(), //TODO
        .data(nrziDecodedInput),
        .valid(nonBitStuffedInput),
        .error(receiveBitStuffingError)
    );

    input_shift_reg #() inputDeserializer(
        .clk12(receiveCLK),
        //TODO reset?
        .EN(nonBitStuffedInput),
        .IN(nrziDecodedInput),
        .dataOut() //TODO
    );

    // =====================================================================================================
    // TRANSMIT Modules
    // =====================================================================================================

    logic transmitCLK;

    clock_gen #(DIVIDE_LOG_2=$clog(4)) clkDiv4 (
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
