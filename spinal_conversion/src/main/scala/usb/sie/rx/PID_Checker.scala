package usb.sie.rx

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

class PID_Checker() extends Component {
  val io = new Bundle {
    val pidP = in Bits(4 bits)
    val pidN = in Bits(4 bits)
    val isValid = out Bool()
  }
  io.isValid := (io.pidP ^ io.pidN).andR
}
