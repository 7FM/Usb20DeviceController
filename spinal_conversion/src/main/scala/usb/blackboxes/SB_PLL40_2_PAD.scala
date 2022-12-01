package usb.blackboxes

import spinal.core._
import spinal.lib._
import spinal.lib.io._

import scala.language.postfixOps

class SB_PLL40_2_PAD(
    feedbackPath: String,
    divr: UInt,
    divf: UInt,
    divq: UInt,
    filterRange: UInt
) extends BlackBox {
  addGeneric("FEEDBACK_PATH", feedbackPath)
  addGeneric("DIVR", divr)
  addGeneric("DIVF", divf)
  addGeneric("DIVQ", divq)
  addGeneric("FILTER_RANGE", filterRange)

  val io = new Bundle {
    val RESETB = in Bool ()
    val BYPASS = in Bool ()
    val PACKAGEPIN = in Bool ()
    val PLLOUTGLOBALA = out Bool ()
    val PLLOUTGLOBALB = out Bool ()
    val LOCK = out Bool ()
  }
  noIoPrefix()
}
