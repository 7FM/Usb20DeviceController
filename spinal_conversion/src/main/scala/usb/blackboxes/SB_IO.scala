package usb.blackboxes

import spinal.core._
import spinal.lib._
import spinal.lib.io._

import scala.language.postfixOps

class SB_IO(captureNegedge: Boolean = false, pullup: Bool, pinType: UInt)
    extends BlackBox {
  addGeneric("PULLUP", pullup)
  addGeneric("PIN_TYPE", pinType)

  val io = new Bundle {
    val OUTPUT_ENABLE = in Bool ()
    val PACKAGE_PIN = inout(Analog(Bool()))
    val D_IN_0 = out Bool ()
    val D_IN_1 = captureNegedge generate out(Bool())
    val D_OUT_0 = in Bool ()
    val CLOCK_ENABLE = in Bool ()
    val INPUT_CLK = in Bool ()
  }
  noIoPrefix()
}
