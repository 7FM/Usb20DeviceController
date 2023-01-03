package usb.sie.tx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._
import usb.sie._
import usb.constants._

import scala.language.postfixOps

case class USB_TX_Iface() extends Bundle {
  val isLast = Bool()
  val data = Bits(8 bits)
}

class USB_TX() extends Component {
  val io = new Bundle {
    // TODO
    val crc = master(USB_CRC_Iface())
    val bitStuff = master(BitStuffIface())
    val bitStuffedData = in Bool ()

    val reqSendPacket = in Bool ()
    val tx = slave(Stream(USB_TX_Iface()))

    // Serial Frontend
    // TODO use interface!
    val sending = out Bool ()
    val dataOutN = out Bool ()
    val dataOutP = out Bool ()
  }

  val txPID = Reg(Bits(4 bits))
  val sendingLastDataByte = RegInit(False)
  io.dataOutN.setAsReg() init (False)
  io.dataOutP.setAsReg() init (True)
  io.sending.setAsReg() init (False)

  val txNoBitStuffingNeeded = io.bitStuff.ready_valid
  val txDataBufNewByte = Reg(Bits(8 bits))
  val txFetchedDataIsLast = RegInit(False)
  val waitingForNewSendReq = Bool()

  val crc5 = io.crc.crc(4 downto 0).subdivideIn(1 bits).reverse.asBits
  val crc16 = io.crc.crc.subdivideIn(1 bits).reverse.asBits

  // Only Data Packets use CRC16!
  val useCRC16 = txPID(
    packet.PACKET_TYPE_MASK_OFFSET,
    packet.PACKET_TYPE_MASK_LENGTH bits
  ) === packet.DATA_PACKET_MASK_VAL
  // Either a Handshake or ERR/PRE
  val noDataAndCrcStage = txPID(
    packet.PACKET_TYPE_MASK_OFFSET,
    packet.PACKET_TYPE_MASK_LENGTH bits
  ) === packet.HANDSHAKE_PACKET_MASK_VAL || txPID === packet.PID_Types.PID_SPECIAL_PRE__ERR

  val txReqNewData = Bool()
  val txGotNewData = Bool()
  val txNRZiEncodedData = Bool()
  val txSendSingleEnded = Bool()
  val txDataOut = Bool()
  val txRstModules = waitingForNewSendReq
  val txDataSerializerIn = Bits(8 bits)
  val crc5PatchNow = Bool()
  val crc5Patch = Bool()

  // This could be used to MUX special cases as EOP which should not mess with NRZI encoding
  txDataOut := txNRZiEncodedData
  // Fallback values
  txSendSingleEnded := False
  txGotNewData := txReqNewData // Trigger automatically if the buffer gets empty
  txDataSerializerIn := txDataBufNewByte
  sendingLastDataByte := (sendingLastDataByte ^ txReqNewData) && txFetchedDataIsLast
  crc5Patch := False;

  when(useCRC16) {
    when(sendingLastDataByte) {
      // the final byte is currently sent -> hence we get our final crc value
      // Start sending the lower crc16 byte
      txDataSerializerIn := crc16(7 downto 0)
    }
  }.elsewhen(!noDataAndCrcStage && sendingLastDataByte && crc5PatchNow) {
    // CRC5 needs special treatment as the last data byte has only 3 data bits & the crc is appended!
    // We need to patch the data that will be read as the last byte already contains the crc5!
    // TODO the final CRC5 is calculated while the byte that contains the crc itself is currently send -> we need to patch the shift register content!
    txDataSerializerIn(4 downto 0) := crc5
    // Mid sending patch...
    txGotNewData := True
    crc5Patch := True
  }

  val txFsm = new StateMachine {
    val TX_WAIT_SEND_REQ = makeInstantEntry()
    val TX_SEND_SYNC, TX_SEND_PID, TX_SEND_DATA, TX_SEND_CRC16_LOWER,
        TX_SEND_CRC16_UPPER, TX_EOP_BITSTUFFING_EDGECASE, TX_SEND_EOP_1,
        TX_SEND_EOP_2, TX_SEND_EOP_3, TX_RST_REGS = new State

    TX_WAIT_SEND_REQ.whenIsActive {
      // force load SYNC_VALUE to start sending a packet!
      txDataSerializerIn := packet.SYNC_VALUE
      txGotNewData := io.reqSendPacket

      when(io.reqSendPacket) {
        goto(TX_SEND_SYNC)
      }
    }
    TX_SEND_SYNC.whenIsActive {
      // As PID will be sent next, it should be safe to assume that it is currently in txDataBufNewByte or will be set during this time
      txPID := txDataBufNewByte(3 downto 0)

      // We can continue after SYNC was sent
      when(txReqNewData) {
        goto(TX_SEND_PID)
      }
    }
    TX_SEND_PID.whenIsActive {
      when(txReqNewData) {
        // If there is no data & crc stage then the EOP bit stuffing edge case can not arrise!
        when(noDataAndCrcStage) {
          goto(TX_EOP_BITSTUFFING_EDGECASE)
        }.elsewhen(sendingLastDataByte) {
          // Edge case for 0 length data packet -> if this flag is set in this state we can be sure it is crc16 for a data packet
          goto(TX_SEND_CRC16_LOWER)
        }.otherwise {
          goto(TX_SEND_DATA)
        }
      }
    }
    TX_SEND_DATA.whenIsActive {
      when(txReqNewData) {
        // Loop in this state until the last byte will be sent next
        when(sendingLastDataByte) {
          when(useCRC16) {
            goto(TX_SEND_CRC16_LOWER)
          }.otherwise {
            goto(TX_EOP_BITSTUFFING_EDGECASE)
          }
        }
      }
    }
    TX_SEND_CRC16_LOWER.whenIsActive {
      when(txReqNewData) {
        // CRC16 byte 1: Lower crc16 byte was send
        goto(TX_SEND_CRC16_UPPER)
      }
    }
    TX_SEND_CRC16_UPPER.whenIsActive {
      when(txReqNewData) {
        // CRC5: We can continue after CRC5 with remaining 3 data bits was sent
        // CRC16 byte 2: the second CRC16 byte was sent (is reused)
        goto(TX_EOP_BITSTUFFING_EDGECASE)
      }
    }
    TX_EOP_BITSTUFFING_EDGECASE.whenIsActive {
      // Ensure that the last bit is sent as expected
      when(txNoBitStuffingNeeded) {
        // no bit stuffing -> we can start sending EOP signal next!
        goto(TX_SEND_EOP_1)
      }
      // otherwise:
      // We need bit stuffing! -> stay in this state to ensure that the stuffed bit is send too
    }
    TX_SEND_EOP_1.whenIsActive {
      // special handling for SE0 signals
      txDataOut := False
      txSendSingleEnded := True
      goto(TX_SEND_EOP_2)
    }
    TX_SEND_EOP_2.whenIsActive {
      // special handling for SE0 signals
      txDataOut := False
      txSendSingleEnded := True
      goto(TX_SEND_EOP_3)
    }
    TX_SEND_EOP_3.whenIsActive {
      txDataOut := True
      goto(TX_RST_REGS)
    }
    TX_RST_REGS.whenIsActive {
      // Reset important state register: should be same as after a RST or in the initial block
      goto(TX_WAIT_SEND_REQ)
    }
  }

  val isResetRegState = txFsm.isActive(txFsm.TX_RST_REGS)

  // Output data
  // due to the encoding pipeline, starting and stopping has some latency! and this needs to be accounted for
  // As this is only one stage, we can easily account for the latency by making the 'sending_o' signal a register instead of a wire
  io.dataOutN := !waitingForNewSendReq && !isResetRegState
  io.dataOutP := txDataOut
  io.sending := txSendSingleEnded === txDataOut

  // =======================================================
  // ======================= Stage 0 =======================
  // =======================================================

  val outShiftReg = new OutputShiftReg()
  outShiftReg.io.en := txNoBitStuffingNeeded
  outShiftReg.io.dataValid := txGotNewData
  outShiftReg.io.crc5Patch := crc5Patch
  outShiftReg.io.dataIn := txDataSerializerIn
  val txSerializerOut = outShiftReg.io.dataOut
  txReqNewData := outShiftReg.io.bufferEmpty
  crc5PatchNow := outShiftReg.io.crc5PatchNow

  // CRC signals
  io.crc.newPacket := txFsm.isActive(txFsm.TX_SEND_PID)
  io.crc.valid := txNoBitStuffingNeeded
  io.crc.data := txSerializerOut
  io.crc.useCRC16 := useCRC16

  // Bit stuffing signals
  io.bitStuff.rst := txRstModules
  io.bitStuff.dataIn := txSerializerOut

  // =======================================================
  // ======================= Stage 1 =======================
  // =======================================================

  val nrziEncoder = new NRZI_Encoder()
  nrziEncoder.io.rst := txRstModules
  nrziEncoder.io.dataIn := io.bitStuffedData
  txNRZiEncodedData := nrziEncoder.io.dataOut

//=========================================================================================
//=====================================Interface Start=====================================
//=========================================================================================

  val txHasDataFetched = RegInit(True)
  io.tx.ready := !txHasDataFetched
  waitingForNewSendReq := txFsm.isActive(txFsm.TX_WAIT_SEND_REQ)

  // If we have data fetched and new one is required -> clear fetched status as it will be transfered to the shift buffer
  // BUT: this bit may not be cleared if we are waiting for a new write request!
  //      and do not clear while the last byte is sent -> wait for packet to end before starting with new data
  // To avoid a race condition, we should always clear once we switch to sending the SYNC signal
  // Else if we do not have data fetched but the new data is valid -> handshake succeeds -> set fetched status
  // Avoid mutliple clears by only clearing on negedge of txReqNewData
  txHasDataFetched := (txHasDataFetched ?
    // Negated clear condition of txHasDataFetched
    (waitingForNewSendReq ? !io.reqSendPacket | (txFetchedDataIsLast || !txReqNewData))
    // Set condition of txHasDataFetched
    | io.tx.valid)

  // Data handshake condition
  when(io.tx.fire) {
    txDataBufNewByte := io.tx.payload.data
    txFetchedDataIsLast := io.tx.payload.isLast
  }.elsewhen(sendingLastDataByte) {
    // During this state the final byte will be sent -> hence we get our final crc value
    txDataBufNewByte := crc16(15 downto 8)
  }

  when(isResetRegState) {
    // Reset important state register: should be the same as in the initial block or after a RST
    txFetchedDataIsLast := False
  }
}
