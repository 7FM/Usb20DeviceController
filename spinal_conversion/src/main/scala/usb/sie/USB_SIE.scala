package usb.sie

import spinal.core._
import spinal.lib._
import spinal.lib.io._
import usb._
import usb.sie.rx._
import usb.sie.tx._

import scala.language.postfixOps

case class SampleResult() extends Bundle {
  val dataP = Bool()
  val isValidDPSignal = Bool()
  val eopDetected = Bool()
}

class USB_SIE(clk12: ClockDomain, clk48: ClockDomain) extends Component {

  val io = new Bundle {
    // TODO
    // val LED = config.useDebugLED generate new Bundle {
    //   val R = out Bits(1 bits)
    //   val G = out Bits(1 bits)
    //   val B = out Bits(1 bits)
    // }

    val USB = master(USB2_0())
    val rxIface = master Stream (USB_RX_Iface())
    val isSendingPhase = in Bool()
  }

  // TODO

  io.USB.PULLUP := True

  val dataTypes = SampleResult()
  val sampleClockArea = new ClockingArea(clk48) {
    val sampleStream = Stream(dataTypes)
    val dppl = new DPPL()
    val sie_frontend = new USBSerialFrontend()
    dppl.io.dataInP <> sie_frontend.io.frontend.dataInP
    dppl.io.dataInP_negedge <> sie_frontend.io.frontend.dataInP_negedge
    sie_frontend.io.USB <> io.USB.DATA

    // TODO replace with useful logic
    sie_frontend.io.frontend.dataOutEn := False
    sie_frontend.io.frontend.dataOutP := True
    sie_frontend.io.frontend.dataOutN := False

    val prevRxCLK = RegInit(False)
    prevRxCLK := dppl.io.rxClk
    sampleStream.valid := !prevRxCLK && dppl.io.rxClk
    sampleStream.payload.dataP := dppl.io.dataInP
    sampleStream.payload.isValidDPSignal := sie_frontend.io.info.isValidDPSignal
    sampleStream.payload.eopDetected := sie_frontend.io.info.eopDetected
  }

  val clk12Area = new ClockingArea(clk12) {
    val crc = new USB_CRC()
    val bitstuffingWrapper = new USB_BitStuffingWrapper()
    val rx = new USB_RX()
    io.rxIface <> rx.io.rxIface
    val tx = new USB_TX()

    val sampleStream = rx.io.sampleStream
    bitstuffingWrapper.io.isSendingPhase <> io.isSendingPhase
    bitstuffingWrapper.io.dataOut <> tx.io.bitStuffedData
    bitstuffingWrapper.io.bitStuff.mux(io.isSendingPhase, tx.io.bitStuff, rx.io.bitStuff)
    crc.io.mux(io.isSendingPhase, tx.io.crc, rx.io.crc)
  }

  val cdcFifo = StreamFifoCC(
    dataType = dataTypes,
    depth = 8,
    pushClock = clk48,
    popClock = clk12
  )
  cdcFifo.io.push << sampleClockArea.sampleStream
  cdcFifo.io.pop >> clk12Area.sampleStream
}
