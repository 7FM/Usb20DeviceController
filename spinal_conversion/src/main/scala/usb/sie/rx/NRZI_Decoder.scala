package usb.sie.rx

import spinal.core._
import spinal.lib._

import scala.language.postfixOps

class NRZI_Decoder() extends Component {
  val io = new Bundle {
    val rst = in Bool()
    val dataIn = in Bool()
    val dataOut = out Bool()
  }
  /*
  Differential Signal:
                                __   _     _   _     ____
                          D+ :   \_/ \___/ \_/ \___/
                                  _   ___   _           
                          D- : __/ \_/   \_/ \__________
  Differential decoding:          K J K K J K J 0 0 J J
                                                ^------------ SM0/SE0 with D+=D-=LOW analogously exists SM1/SE1 with D+=D-=HIGH
  NRZI decoding:                  0 0 0 1 0 0 0 ? ? 0 1
  (Non-Return-to-Zero Inverted): logical 0 is transmitted as transition -> either from J to K or from K to J
                                  logical 1 is transmitted as NO transition -> stay at previous level
  */

  val prevData = RegNext(io.dataIn) init(True)
  io.dataOut.setAsReg() init(True)

  when(io.rst) {
    io.dataOut := True
    prevData := True
  }.otherwise {
    io.dataOut := prevData === io.dataIn
  }
}
