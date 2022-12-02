package usb.sie.rx

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

class SYNC_Detect() extends Component {
  val io = new Bundle {
    val data = in Bits(8 bits)
    val syncDetect = out Bool()
  }
  // SYNC sequence is KJKJ_KJKK
  // NRZI decoded:    0000_0001
  //              ------ time ---->
  // For robustness we only want to detect the last 4 bits sent: 4b0001 -> as LSb is expected -> 4b1000
  io.syncDetect := io.data(7 downto 4) === (B"1000_0000"(7 downto 4))
}
