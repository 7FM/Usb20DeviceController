package usb.sie

import spinal.core._
import spinal.lib._
import spinal.lib.io._
import usb._
import usb.blackboxes._

import scala.language.postfixOps

case class USBFrontend() extends Bundle with IMasterSlave {
  val dataOutEn = Bool()
  val dataOutP = Bool()
  val dataOutN = Bool()
  val dataInP = Bool()
  val dataInP_negedge = Bool()

  override def asMaster() : Unit = {
    out(dataOutEn, dataOutN, dataOutP)
    in(dataInP, dataInP_negedge)
  }
}

case class USBSignalInfo() extends Bundle with IMasterSlave {
  val isValidDPSignal = Bool()
  val eopDetected = Bool()
  val usbResetDetected = Bool()
  val ackEOP = Bool()
  val ackUsbRst = Bool()

  override def asMaster() : Unit = {
    out(ackEOP, ackUsbRst)
    in(isValidDPSignal, eopDetected, usbResetDetected)
  }
}

class USBSerialFrontend() extends Component {
  val io = new Bundle {
    val USB = master(USB2_0_DATA())
    val frontend = slave(USBFrontend())
    val info = slave(USBSignalInfo())
  }

  val dataInN = Bool()
  io.info.isValidDPSignal := dataInN ^ io.frontend.dataInP

  val pinType = U"1010_00"
  val pinP = new SB_IO(
    captureNegedge = true,
    pullup = False,
    pinType = pinType
  )
  val pinN = new SB_IO(
    captureNegedge = false,
    pullup = False,
    pinType = pinType
  )
  pinP.io.CLOCK_ENABLE := True
  pinN.io.CLOCK_ENABLE := True
  pinP.io.INPUT_CLK := ClockDomain.current.readClockWire
  pinN.io.INPUT_CLK := ClockDomain.current.readClockWire
  pinP.io.OUTPUT_ENABLE := io.frontend.dataOutEn
  pinN.io.OUTPUT_ENABLE := io.frontend.dataOutEn
  pinP.io.D_OUT_0 := io.frontend.dataOutP
  pinN.io.D_OUT_0 := io.frontend.dataOutN

  dataInN := RegNext(pinN.io.D_IN_0)
  io.frontend.dataInP := RegNext(pinP.io.D_IN_0) init(True)
  io.frontend.dataInP_negedge := RegNext(pinP.io.D_IN_1) init(True)

  val detect = new USB_EOP_Reset_Detector()
  detect.io.eopDetected <> io.info.eopDetected
  detect.io.usbResetDetected <> io.info.usbResetDetected
  detect.io.ackEOP <> io.info.ackEOP
  detect.io.ackUsbRst <> io.info.ackUsbRst
  detect.io.dataP := io.frontend.dataInP
  detect.io.dataN <> dataInN
}
