`ifndef SIE_DEFS_PKG_SV
`define SIE_DEFS_PKG_SV

package sie_defs_pkg;


    /*
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

    localparam PACKET_TYPE_MASK_OFFSET = 0;
    localparam PACKET_TYPE_MASK_LENGTH = 2;

    localparam TOKEN_PACKET_MASK_VAL = 2'b01;
    localparam DATA_PACKET_MASK_VAL = 2'b11;
    localparam HANDSHAKE_PACKET_MASK_VAL = 2'b10;
    localparam SPECIAL_PACKET_MASK_VAL = 2'b00;

    // SYNC sequence is KJKJ_KJKK
    // NRZI decoded:    0000_0001
    //              ------ time ---->
    // Is send LSB first
    localparam SYNC_VALUE = 8'b1000_0000;

endpackage

`endif
