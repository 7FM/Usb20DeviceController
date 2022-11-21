package usb.sie

import spinal.core._
import spinal.lib._
import spinal.lib.io._
import usb._

import scala.language.postfixOps

class USB_SIE(clk12: ClockDomain, clk48: ClockDomain) extends Component {

  val io = new Bundle {
    //TODO
    // val LED = config.useDebugLED generate new Bundle {
    //   val R = out Bits(1 bits)
    //   val G = out Bits(1 bits)
    //   val B = out Bits(1 bits)
    // }

    val USB = master(USB2_0())
  }

  // TODO

  io.USB.PULLUP := True

  val sampleClockArea = new ClockingArea(clk48) {
    val sie_frontend = new USBSerialFrontend()
    sie_frontend.io.USB <> io.USB.DATA

    //TODO replace with useful logic
    sie_frontend.io.frontend.dataOutEn := False
    sie_frontend.io.frontend.dataOutP := True
    sie_frontend.io.frontend.dataOutN := False
  }

}

