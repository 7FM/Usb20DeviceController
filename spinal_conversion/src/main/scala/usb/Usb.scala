package usb

import spinal.core._
import spinal.lib._
import spinal.lib.io._

import usb.sie._

import scala.language.postfixOps

case class USBModuleConfig(
    _isSim: Boolean = false,
    _useDebugLED: Boolean = false
) {
  val isSim = _isSim
  val useDebugLED = _useDebugLED
}

case class USB2_0_DATA() extends Bundle with IMasterSlave {
  val DP = Analog(Bool())
  val DN = Analog(Bool())

  override def asMaster(): Unit = {
    inout(DP, DN)
  }
}

case class USB2_0() extends Bundle with IMasterSlave {
  val DATA = USB2_0_DATA()
  val PULLUP = Bool()

  override def asMaster(): Unit = {
    out(PULLUP)
    master(DATA)
  }
}

//Hardware definition
class USBTop(config: USBModuleConfig, clk12: ClockDomain, clk48: ClockDomain)
    extends Component {

  val io = new Bundle {
    // TODO
    val LED = config.useDebugLED generate new Bundle {
      val R = out Bits (1 bits)
      val G = out Bits (1 bits)
      val B = out Bits (1 bits)
    }

    val USB = master(USB2_0())
  }

  // TODO
  if (config.useDebugLED) {
    io.LED.R := 0
    io.LED.G := 0
    io.LED.B := 0
  }

  val sie = new USB_SIE(clk12, clk48)
  sie.io.USB <> io.USB
}
