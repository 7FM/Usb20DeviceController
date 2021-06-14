`ifndef USB_PACKET_PKG_SV
`define USB_PACKET_PKG_SV

package usb_packet_pkg;
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
        sie_defs_pkg::PID_Types pid;
    } PacketHeader;

    localparam TOKEN_PACKET_OFFSET = 8;
    localparam TOKEN_PACKET_BITS = 7 + 4;
    typedef struct packed {
        logic [6:0] devAddr;
        logic [3:0] endptSel; // There can be at most 16 endpoints
    } TokenPacket;
    localparam _TOKEN_LENGTH = PACKET_HEADER_BITS + TOCKEN_PACKET_BITS;

    localparam SOF_PACKET_OFFSET = 8;
    localparam SOF_PACKET_BITS = 11;
    typedef struct packed {
        logic [10:0] frameNum;
    } StartOfFramePacket;
    localparam _SOF_LENGTH = PACKET_HEADER_BITS + SOF_PACKET_BITS;

    localparam _MAX_INIT_TRANS_PACKET_LEN = _SOF_LENGTH > _TOKEN_LENGTH ? _SOF_LENGTH : _TOKEN_LENGTH;
    // Round buffer length up to the next byte boundary!
    localparam INIT_TRANS_PACKET_BUF_LEN = _MAX_INIT_TRANS_PACKET_LEN + (_MAX_INIT_TRANS_PACKET_LEN % 8);
    localparam INIT_TRANS_PACKET_BUF_BYTE_COUNT = INIT_TRANS_PACKET_BUF_LEN / 8;
    localparam INIT_TRANS_PACKET_IDX_LEN = $clog2(INIT_TRANS_PACKET_BUF_BYTE_COUNT) + 1;

endpackage

`endif
