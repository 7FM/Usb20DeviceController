package usb.sie.tx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._
import usb.sie._

import scala.language.postfixOps

//TODO create interface? this would be really nice if we can mux entire interface connections!

class USB_TX() extends Component {
  val io = new Bundle {
    // TODO
    val crc = master(USB_CRC_Iface())
    val bitStuff = master(BitStuffIface())
    val bitStuffedData = in Bool()
  }

}
