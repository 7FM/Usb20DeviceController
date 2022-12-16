package usb.sie

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

case class BitStuffIface() extends Bundle with IMasterSlave {
  val rst = Bool()
  val dataIn = Bool()
  val ready_valid = Bool()
  val error = Bool()

  override def asMaster(): Unit = {
    out(rst, dataIn)
    in(ready_valid, error)
  }

  def mux(sel: Bool, m1 : BitStuffIface, m2 : BitStuffIface): Unit = {
    when(sel) {
      rst <> m1.rst
      dataIn <> m1.dataIn
    }.otherwise {
      rst <> m2.rst
      dataIn <> m2.dataIn
    }

    ready_valid <> m1.ready_valid
    error <> m1.error
    ready_valid <> m2.ready_valid
    error <> m2.error
  }
}

class USB_BitUnStuffing() extends Component {
  val io = slave(BitStuffIface())

  val cnt = Counter(0 to 6)
  io.ready_valid := !cnt.willOverflowIfInc
  io.error := !io.ready_valid && io.dataIn

  when(io.rst || !io.dataIn) {
    cnt.clear()
  }.elsewhen(!cnt.willOverflowIfInc) {
    cnt.increment()
  }
}

class USB_BitStuffingWrapper() extends Component {
  val io = new Bundle {
    val bitStuff = slave(BitStuffIface())
    val isSendingPhase = in Bool ()
    val dataOut = out Bool ()
  }

  val unstuffer = new USB_BitUnStuffing()
  unstuffer.io <> io.bitStuff
  // Fixup the data input to the bit unstuffer!
  unstuffer.io.dataIn.allowOverride
  unstuffer.io.dataIn := (io.isSendingPhase && !unstuffer.io.ready_valid) ? False | io.bitStuff.dataIn

  io.dataOut := unstuffer.io.ready_valid ? io.bitStuff.dataIn | False
}
