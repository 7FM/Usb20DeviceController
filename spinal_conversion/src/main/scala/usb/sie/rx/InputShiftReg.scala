package usb.sie.rx

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

class InputShiftReg(val length: Int = 8) extends Component {
  val io = new Bundle {
    val rst = in Bool ()
    val valid = in Bool ()
    val dataBit = in Bool ()
    val data = out Bits (length bits)
    val full = out Bool ()
  }

  val data = RegInit(B(length bits, default -> True))
  io.data := data
  val validEntryCounter = Reg(UInt(log2Up(length + 1) bits)) init (0)
  io.full := validEntryCounter === length

  when(io.full || io.rst) {
    data.setAll()
    validEntryCounter := (io.valid ? U(1) | U(0)).resized
  }.elsewhen(io.valid) {
    validEntryCounter := validEntryCounter + 1
    data := io.dataBit ## data(length - 1 downto 1)
  }
}
