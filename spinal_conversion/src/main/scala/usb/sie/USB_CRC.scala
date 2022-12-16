package usb.sie

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

case class USB_CRC_Iface() extends Bundle with IMasterSlave {
  val newPacket = in Bool () // Required at every new packet, can be a wire
  val valid =
    in Bool () // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
  val data = in Bool ()
  val useCRC16 =
    in Bool () // Indicate which CRC should type should be calculated/checked, needs to be set when newPacket is set high
  val validCRC = out Bool ()
  val crc = out Bits (16 bits)

  override def asMaster(): Unit = {
    out(newPacket, valid, data, useCRC16)
    in(validCRC, crc)
  }

  def mux(sel: Bool, m1 : USB_CRC_Iface, m2 : USB_CRC_Iface): Unit = {
    when(sel) {
      newPacket <> m1.newPacket
      valid <> m1.valid
      data <> m1.data
      useCRC16 <> m1.useCRC16
    }.otherwise {
      newPacket <> m2.newPacket
      valid <> m2.valid
      data <> m2.data
      useCRC16 <> m2.useCRC16
    }

    validCRC <> m1.validCRC
    crc <> m1.crc
    validCRC <> m2.validCRC
    crc <> m2.crc
  }
}

class USB_CRC() extends Component {
  val io = slave(USB_CRC_Iface())

  val nextCRC = Bits(16 bits)
  // When the last bit of the checked field is sent, the CRC in the generator is inverted and sent to the checker MSb first
  // Due to timing requirements, we need to forward the calculation result instead of the register itself
  io.crc := ~nextCRC
  val useCRC16 = Reg(Bool())
  val crcReg = RegNext(nextCRC)
  val crc5_in = crcReg(4) ^ io.data
  val crc16_in = crcReg(15) ^ io.data
  val crcX_in = (useCRC16 ? crc16_in | crc5_in).asBits

  nextCRC := crcReg
  // CRC calculation magic:
  // For each data bit sent or received, the high order bit of the current remainder is XORed with
  // the data bit and then the remainder is shifted left one bit and the low-order bit set to zero. If the result of
  // that XOR is one, then the remainder is XORed with the generator polynomial.
  when(!io.newPacket && io.valid) {
    // Shift and XOR with polynomial if crcX_in is 1 -> XOR with crcX_in
    // CRC5  polynomial: 0b0000_0000_0000_0101
    // CRC16 polynomial: 0b1000_0000_0000_0101
    // -> lower bits are identical
    // -> as we ignore the upper most bits for CRC5 we can always xor at the locations of CRC16 polynomial with an 1
    nextCRC := (crcReg(14).asBits ^ crcX_in) ##
      crcReg(13 downto 2) ##
      (crcReg(1).asBits ^ crcX_in) ##
      crcReg(0) ##
      crcX_in
  }

  when(io.newPacket) {
    // For CRC generation and checking, the shift registers in the generator and checker are seeded with an all ones pattern.
    crcReg.setAll()
    useCRC16 := io.useCRC16
  }

  val CRC16_RESIDUAL = B"1000_0000_0000_1101"
  val CRC5_RESIDUAL = B"0_1100"
  val crc16_valid = crcReg(15 downto 0) === CRC16_RESIDUAL
  val crc5_valid = crcReg(4 downto 0) === CRC5_RESIDUAL
  io.validCRC := useCRC16 ? crc16_valid | crc5_valid;
}
