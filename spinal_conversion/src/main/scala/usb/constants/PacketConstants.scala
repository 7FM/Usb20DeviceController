package usb.constants

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

package object packet {

//TODO NOTE that SV structs are MSB first where as in SpinalHDL they are LSB first

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
  val PACKET_TYPE_MASK_OFFSET = 0
  val PACKET_TYPE_MASK_LENGTH = 2

  def TOKEN_PACKET_MASK_VAL = B"01"
  def DATA_PACKET_MASK_VAL = B"11"
  def HANDSHAKE_PACKET_MASK_VAL = B"10"
  def SPECIAL_PACKET_MASK_VAL = B"00"

  val DATA_0_1_TOGGLE_OFFSET = 3

  object Handshakes {
    def RES_ACK = B"00"
    def RES_NAK = B"10"
    def RES_STALL = B"11"
    def RES_NYET = B"01"
  }

  // TODO we want enums here!
  object PID_Types {
    // TOKEN: last lsb bits are 01
    def PID_OUT_TOKEN = B"00" ## TOKEN_PACKET_MASK_VAL
    def PID_IN_TOKEN = B"10" ## TOKEN_PACKET_MASK_VAL
    def PID_SOF_TOKEN = B"01" ## TOKEN_PACKET_MASK_VAL
    def PID_SETUP_TOKEN = B"11" ## TOKEN_PACKET_MASK_VAL
    // DATA: last lsb bits are 11
    def PID_DATA0 = B"00" ## DATA_PACKET_MASK_VAL
    def PID_DATA1 = B"10" ## DATA_PACKET_MASK_VAL
    def PID_DATA2 = B"01" ## DATA_PACKET_MASK_VAL // unused: High-speed only
    def PID_MDATA = B"11" ## DATA_PACKET_MASK_VAL // unused: High-speed only
    // HANDSHAKE: last lsb bits are 10
    def PID_HANDSHAKE_ACK = Handshakes.RES_ACK ## HANDSHAKE_PACKET_MASK_VAL
    def PID_HANDSHAKE_NAK = Handshakes.RES_NAK ## HANDSHAKE_PACKET_MASK_VAL
    def PID_HANDSHAKE_STALL = Handshakes.RES_STALL ## HANDSHAKE_PACKET_MASK_VAL
    def PID_HANDSHAKE_NYET = Handshakes.RES_NYET ## HANDSHAKE_PACKET_MASK_VAL
    // SPECIAL: last lsb bits are 00
    def PID_SPECIAL_PRE__ERR =
      B"11" ## SPECIAL_PACKET_MASK_VAL // Meaning depends on context
    def PID_SPECIAL_SPLIT =
      B"10" ## SPECIAL_PACKET_MASK_VAL // unused: High-speed only
    def PID_SPECIAL_PING =
      B"01" ## SPECIAL_PACKET_MASK_VAL // unused: High-speed only
    def _PID_RESERVED = B"00" ## SPECIAL_PACKET_MASK_VAL
  }

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

  val PACKET_HEADER_OFFSET = 0
  val PACKET_HEADER_BITS = 4 + 4
  case class PacketHeader() extends Bundle {
    // val pid = PID_Types() //TODO we want this!
    val pid = Bits(4 bits)
    val _pidNeg = Bits(4 bits)
  }

  val USB_DEV_ADDR_WID = 7

  val TOKEN_PACKET_OFFSET = 8
  val TOKEN_PACKET_BITS = 7 + 4
  case class TokenPacket() extends Bundle {
    val devAddr = Bits(USB_DEV_ADDR_WID bits)
    val endptSel = Bits(4 bits) // There can be at most 16 endpoints
  }
  val _TOKEN_LENGTH = PACKET_HEADER_BITS + TOKEN_PACKET_BITS

  val SOF_PACKET_OFFSET = 8
  val SOF_PACKET_BITS = 11
  case class StartOfFramePacket() extends Bundle {
    val frameNum = Bits(SOF_PACKET_BITS bits)
  }

  val _SOF_LENGTH = PACKET_HEADER_BITS + SOF_PACKET_BITS

  val _MAX_INIT_TRANS_PACKET_LEN =
    if (_SOF_LENGTH > _TOKEN_LENGTH) _SOF_LENGTH else _TOKEN_LENGTH
  // Round buffer length up to the next byte boundary!
  val INIT_TRANS_PACKET_BUF_BYTE_COUNT =
    (_MAX_INIT_TRANS_PACKET_LEN + 8 - 1) / 8
  val INIT_TRANS_PACKET_BUF_LEN = INIT_TRANS_PACKET_BUF_BYTE_COUNT * 8
}
