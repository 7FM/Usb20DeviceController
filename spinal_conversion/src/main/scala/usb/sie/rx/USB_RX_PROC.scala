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
    // TODO
    val sampleStream = slave Stream (SampleResult())
    val crc = master(USB_CRC_Iface())
    val bitStuff = master(BitStuffIface())
    val rxIface = master Stream (USB_RX_Iface())
  }

  io.sampleStream.ready := True
  val dataP = io.sampleStream.valid ? io.sampleStream.payload.dataP | True
  val validDPSignal = io.sampleStream.valid ? io.sampleStream.payload.isValidDPSignal | False
  val eopDetected = io.sampleStream.valid ? io.sampleStream.payload.eopDetected | False

  // Stage 0
  val nrziDecoder = new NRZI_Decoder()
  val nrziDecoderReset = nrziDecoder.io.rst
  nrziDecoder.io.dataIn := dataP
  val nrziDecodedInput = nrziDecoder.io.dataOut

  // Stage 1
  val expectNonBitStuffedInput = Bool() //TODO

  val shiftReg = new InputShiftReg()
  val inputBuf = shiftReg.io.data
  val inputBufFull = shiftReg.io.full
  shiftReg.io.dataBit := nrziDecodedInput
  val rxInputShiftRegReset = False
  shiftReg.io.rst := rxInputShiftRegReset
  shiftReg.io.valid := expectNonBitStuffedInput

  val syncDetector = new SYNC_Detect()
  val syncDetect = syncDetector.io.syncDetect
  syncDetector.io.data := inputBuf

  val pidCheck = new PID_Checker()
  pidCheck.io.pidP := inputBuf(7 downto 4)
  pidCheck.io.pidN := inputBuf(3 downto 0)
  val pidValid = pidCheck.io.isValid

  val dropPacket = RegInit(False)
  val byteGotSignalError = RegInit(False)
  val needCRC16Handling = Bool()
  val gotNewInput = Bool()
  val gotEOP = Bool()

  // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to satisfy the bit stuffing condition
  val defaultNextDropPacket =
    dropPacket || (inputBufFull && (byteGotSignalError || io.bitStuff.error))

  val rxFSM = new StateMachine {
    val RX_WAIT_FOR_SYNC = makeInstantEntry()
    val RX_GET_PID, RX_WAIT_FOR_EOP, RX_RST_PHASE = new State

    RX_WAIT_FOR_SYNC.whenIsActive {
      when(syncDetect) {
        // Input shift register needs valid counter reset to be aligned with the incoming packet content
        rxInputShiftRegReset := True
        // reset error signals
        dropPacket := False
        byteGotSignalError := False
        // go to the next state
        goto(RX_GET_PID)
      }
    }

    RX_GET_PID.whenIsActive {
      // After Sync was detected, we always need valid bit stuffing!
      // Also there may not be invalid differential pair signals as we expect the PID to be send!
      // Sanity check: was PID correctly received?
      dropPacket := defaultNextDropPacket || (inputBufFull && !pidValid)

    }

    // TODO remaining states!
  }

}
