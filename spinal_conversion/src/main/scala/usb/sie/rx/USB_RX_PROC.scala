package usb.sie.rx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._
import usb.sie._

import scala.language.postfixOps

//TODO create interface? this would be really nice if we can mux entire interface connections!
case class USB_RX_Iface() extends Bundle {
  val done = Bool()
  val keep = Bool()
  val data = Bits(8 bits)
}

class USB_RX_PROC() extends Component {
  val io = new Bundle {
    //TODO
    val sampleStream = slave Stream(Bits(3 bits))
    val crc = master(USB_CRC_Iface())
    val bitStuff = master(BitStuffIface())
    val rxIface = master Stream(USB_RX_Iface())
  }

  io.sampleStream.ready := True
  val dataP = io.sampleStream.valid ? io.sampleStream.payload(2) | True
  val validDPSignal = io.sampleStream.valid ? io.sampleStream.payload(1) | False
  val eopDetected = io.sampleStream.valid ? io.sampleStream.payload(0) | False

  //TODO
}
