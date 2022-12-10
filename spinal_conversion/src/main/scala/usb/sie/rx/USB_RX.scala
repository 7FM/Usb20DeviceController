package usb.sie.rx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._
import usb.sie._
import usb.constants._

import scala.language.postfixOps

//TODO create interface? this would be really nice if we can mux entire interface connections!
case class USB_RX_Iface() extends Bundle {
  val done = Bool()
  val keep = Bool()
  val data = Bits(8 bits)
}

class USB_RX() extends Component {
  val io = new Bundle {
    // TODO
    val sampleStream = slave Stream (SampleResult())
    val crc = master(USB_CRC_Iface())
    val bitStuff = master(BitStuffIface())
    val rxIface = master Stream (USB_RX_Iface())
  }

  // TODO is a RST even needed? sync signal should automagically cause the required resets
  io.bitStuff.rst := False

  // TODO check that all signals are defined & set

  io.sampleStream.ready := True
  val dataP = io.sampleStream.valid ? io.sampleStream.payload.dataP | True
  val validDPSignal =
    io.sampleStream.valid ? io.sampleStream.payload.isValidDPSignal | False
  val eopDetected =
    io.sampleStream.valid ? io.sampleStream.payload.eopDetected | False

  // Stage 0
  val nrziDecoder = new NRZI_Decoder()
  val nrziDecoderReset = nrziDecoder.io.rst
  nrziDecoder.io.dataIn := dataP
  val nrziDecodedInput = nrziDecoder.io.dataOut
  // We need to delay validDPSignal because our nrzi decoder introduces a delay to the decoded signal too
  val gotInvalidDPSignal = RegNext(!validDPSignal)
  val signalError = gotInvalidDPSignal || io.bitStuff.error

  // Stage 1
  val expectNonBitStuffedInput = io.bitStuff.ready_valid

  val shiftReg = new InputShiftReg()
  val inputBuf = shiftReg.io.data
  val inputBufFull = shiftReg.io.full
  shiftReg.io.dataBit := nrziDecodedInput
  val rxInputShiftRegReset = shiftReg.io.rst
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
  byteGotSignalError := byteGotSignalError || signalError
  when(inputBufFull) {
    byteGotSignalError := signalError
  }
  val lastByteValidCRC = RegInit(True)
  val needCRC16Handling = Reg(Bool())
  val gotNewInput = Bool()
  val gotEOP = Bool()

  // Needs tight timing -> use input buffer directly
  // Only Data Packets use CRC16!
  // Packet types are identifiable by 2 lsb bits, which are at this stage not yet at the lsb location
  io.crc.useCRC16 := inputBuf(2 downto 1) === packet.DATA_PACKET_MASK_VAL
  io.crc.valid := expectNonBitStuffedInput
  io.crc.data := nrziDecodedInput

  // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to satisfy the bit stuffing condition
  val defaultNextDropPacket =
    dropPacket || (inputBufFull && (byteGotSignalError || io.bitStuff.error))

  // default values
  io.crc.newPacket := False
  nrziDecoderReset := False
  rxInputShiftRegReset := False

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

      when(inputBufFull) {
        goto(RX_WAIT_FOR_EOP)
      }.otherwise {
        // If inputBufFull is set, we already receive the first data bit -> hence crc needs to receive this bit -> but CRC reset low
        io.crc.newPacket := True
        // As during CRC reset the io.crc.useCRC16 flag is evaluated we can use it for our purposes too
        needCRC16Handling := io.crc.useCRC16
      }
    }

    RX_WAIT_FOR_EOP.whenIsActive {
      // After Sync was detected, we always need valid bit stuffing!
      // Sanity check: does the CRC match?
      dropPacket := defaultNextDropPacket || (eopDetected && !lastByteValidCRC)

      when(eopDetected) {
        goto(RX_RST_PHASE)
      }.elsewhen(inputBufFull) {
        // Update is valid crc flag after each byte such that when we receive EOP we can check if the crc was correct for the last byte -> the entire packet!
        lastByteValidCRC := io.crc.validCRC
      }
    }

    RX_RST_PHASE.whenIsActive {
      // Go back to the initial state
      goto(RX_WAIT_FOR_SYNC)

      // Trigger some resets
      // TODO is a RST needed for the NRZI decoder?
      nrziDecoderReset := True

      // We need to clear the content to ensure that the currently stored data won't be detected as sync
      rxInputShiftRegReset := True

      // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
      lastByteValidCRC := True
    }
  }

  // ===================================================================================================================================
  // ===================================================================================================================================
  // ===================================================================================================================================

  // Output interface
  val isByteData =
    rxFSM.isActive(rxFSM.RX_GET_PID) || rxFSM.isActive(rxFSM.RX_WAIT_FOR_EOP)
  val rxGotNewInput = isByteData && inputBufFull
  val gotEopDetect = eopDetected && rxFSM.isActive(rxFSM.RX_WAIT_FOR_EOP)
  // TODO ackEOP???

  val byteWasNotReceived = RegInit(False)
  val fifoDepth = 2
  val rxDataFifo = StreamFifo(
    dataType = Bits(8 bits),
    depth = fifoDepth
  )
  val keepPacket = !(dropPacket || byteWasNotReceived)
  // For CRC5 packets all bytes contain data -> we do not need to hold any data back!
  // Else if we are waiting until the FIFO is empty
  val fifoFull = rxDataFifo.io.occupancy === fifoDepth
  val allowFifoPop = rxGotNewInput && fifoFull
  // for CRC16 packets flush the entire fifo as the last 2 bytes are the CRC!
  // we can drop keep flushing the fifo if we do not want to keep the packet anyway!
  val flushFifo = (gotEopDetect && needCRC16Handling) || !keepPacket
  val rxDone = False
  rxDataFifo.io.flush := flushFifo
  rxDataFifo.io.push.valid := rxGotNewInput
  val fifoAcceptInput = rxDataFifo.io.push.ready
  rxDataFifo.io.push.payload := inputBuf
  rxDataFifo.io.pop.ready := allowFifoPop && io.rxIface.ready
  val fifoDataAvailable = rxDataFifo.io.pop.valid

  io.rxIface.payload.data := rxDataFifo.io.pop.payload
  io.rxIface.payload.done := rxDone
  io.rxIface.payload.keep := keepPacket
  io.rxIface.valid := allowFifoPop && fifoDataAvailable

  when(!fifoAcceptInput && rxGotNewInput) {
    byteWasNotReceived := True
  }

  val flushFifoTimeout = Timeout(3)
  val rxIfaceFSM = new StateMachine {
    val KEEP_FILLED = makeInstantEntry()
    val WAIT_UNTIL_EMPTY = new State

    KEEP_FILLED.whenIsActive {
      flushFifoTimeout.clear()
      when(gotEopDetect) {
        goto(WAIT_UNTIL_EMPTY)
      }
    }

    WAIT_UNTIL_EMPTY.whenIsActive {
      when(flushFifoTimeout) {
        // Timeout, set error bit! To prevent a deadlock.
        byteWasNotReceived := True
      }.elsewhen(!fifoDataAvailable) {
        // Signal that all bytes of this packet were received!
        rxDone := True
        // We are done for this packet -> clear the error flag
        byteWasNotReceived := False
        goto(KEEP_FILLED)
      }
    }
  }
}
