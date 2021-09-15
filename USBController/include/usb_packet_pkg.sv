`ifndef USB_PACKET_PKG_SV
`define USB_PACKET_PKG_SV

package usb_packet_pkg;

    /*
    Source: https://beyondlogic.org/usbnutshell/usb3.shtml
    DATA is transmitted with LSb First
    Common USB Packet Fields:
    - 8 Low Bits for sync
    - 8 bits PID: actually only 4 but they are inverted and repeated PID0, PID1, PID2, PID3, ~PID0, ~PID1, ~PID2, ~PID3
        Possible Values:                                      LSb ---^                                                ^--- MSb
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
                 |   1010   |  NAK Handshake
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
    localparam PACKET_TYPE_MASK_OFFSET = 0;
    localparam PACKET_TYPE_MASK_LENGTH = 2;

    localparam TOKEN_PACKET_MASK_VAL = 2'b01;
    localparam DATA_PACKET_MASK_VAL = 2'b11;
    localparam HANDSHAKE_PACKET_MASK_VAL = 2'b10;
    localparam SPECIAL_PACKET_MASK_VAL = 2'b00;

    localparam DATA_0_1_TOGGLE_OFFSET = 3;

    typedef enum logic[1:0] {
        RES_ACK = 2'b00,
        RES_NAK = 2'b10,
        RES_STALL = 2'b11,
        RES_NYET = 2'b01
    } Handshakes;

    typedef enum logic[3:0] {
        // TOKEN: last lsb bits are 01
        PID_OUT_TOKEN = {2'b00, TOKEN_PACKET_MASK_VAL},
        PID_IN_TOKEN = {2'b10, TOKEN_PACKET_MASK_VAL},
        PID_SOF_TOKEN = {2'b01, TOKEN_PACKET_MASK_VAL},
        PID_SETUP_TOKEN = {2'b11, TOKEN_PACKET_MASK_VAL},
        // DATA: last lsb bits are 11
        PID_DATA0 = {2'b00, DATA_PACKET_MASK_VAL},
        PID_DATA1 = {2'b10, DATA_PACKET_MASK_VAL},
        PID_DATA2 = {2'b01, DATA_PACKET_MASK_VAL}, // unused: High-speed only
        PID_MDATA = {2'b11, DATA_PACKET_MASK_VAL}, // unused: High-speed only
        // HANDSHAKE: last lsb bits are 10
        PID_HANDSHAKE_ACK = {RES_ACK, HANDSHAKE_PACKET_MASK_VAL},
        PID_HANDSHAKE_NAK = {RES_NAK, HANDSHAKE_PACKET_MASK_VAL},
        PID_HANDSHAKE_STALL = {RES_STALL, HANDSHAKE_PACKET_MASK_VAL},
        PID_HANDSHAKE_NYET = {RES_NYET, HANDSHAKE_PACKET_MASK_VAL},
        // SPECIAL: last lsb bits are 00
        PID_SPECIAL_PRE__ERR = {2'b11, SPECIAL_PACKET_MASK_VAL}, // Meaning depends on context
        PID_SPECIAL_SPLIT = {2'b10, SPECIAL_PACKET_MASK_VAL}, // unused: High-speed only
        PID_SPECIAL_PING = {2'b01, SPECIAL_PACKET_MASK_VAL}, // unused: High-speed only
        _PID_RESERVED = {2'b00, SPECIAL_PACKET_MASK_VAL}
    } PID_Types;

    /*
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

    localparam PACKET_HEADER_OFFSET = 0;
    localparam PACKET_HEADER_BITS = 4 + 4;
    typedef struct packed {
        logic [3:0] _pidNeg;
        PID_Types pid;
    } PacketHeader;

    localparam TOKEN_PACKET_OFFSET = 8;
    localparam TOKEN_PACKET_BITS = 7 + 4;
    typedef struct packed {
        logic [3:0] endptSel; // There can be at most 16 endpoints
        logic [6:0] devAddr;
    } TokenPacket;
    localparam _TOKEN_LENGTH = PACKET_HEADER_BITS + TOKEN_PACKET_BITS;

    localparam SOF_PACKET_OFFSET = 8;
    localparam SOF_PACKET_BITS = 11;
    typedef struct packed {
        logic [10:0] frameNum;
    } StartOfFramePacket;
    localparam _SOF_LENGTH = PACKET_HEADER_BITS + SOF_PACKET_BITS;

    localparam _MAX_INIT_TRANS_PACKET_LEN = _SOF_LENGTH > _TOKEN_LENGTH ? _SOF_LENGTH : _TOKEN_LENGTH;
    // Round buffer length up to the next byte boundary!
    localparam INIT_TRANS_PACKET_BUF_BYTE_COUNT = (_MAX_INIT_TRANS_PACKET_LEN + 8 - 1) / 8;
    localparam INIT_TRANS_PACKET_BUF_LEN = INIT_TRANS_PACKET_BUF_BYTE_COUNT * 8;

endpackage

`endif
