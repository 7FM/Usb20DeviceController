package usb.sie

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._

import scala.language.postfixOps

class USB_EOP_Reset_Detector() extends Component {
  val io = new Bundle {
    val eopDetected = out Bool ()
    val usbResetDetected = out Bool ()
    val ackEOP = in Bool ()
    val ackUsbRst = in Bool ()

    val dataP = in Bool ()
    val dataN = in Bool ()
  }

  val eopDetected = RegInit(False)
  io.eopDetected := eopDetected
  val usbResetDetected = RegInit(False)
  io.usbResetDetected := usbResetDetected

  val se0, j = Bool()
  se0 := !(io.dataP || io.dataN)
  j := io.dataP && !io.dataN

  val softResetFSM = Bool()
  softResetFSM := False
  val softResetable = ClockDomain(
    clock = ClockDomain.current.readClockWire,
    reset = ClockDomain.current.readResetWire,
    softReset =
      if (ClockDomain.current.hasSoftResetSignal)
        ClockDomain.current.readSoftResetWire && softResetFSM
      else softResetFSM,
    clockEnable = ClockDomain.current.readClockEnableWire
  )
  val eopFSM = softResetable(new StateMachine {
    val IDLE = makeInstantEntry()
    val FIRST_SE0, SECOND_SE0, THIRD_SE0, LAST_CHANCE = new State

    IDLE.whenIsActive {
      when(se0) {
        goto(FIRST_SE0)
      }
    }
    FIRST_SE0.whenIsActive {
      when(se0) {
        goto(SECOND_SE0)
      }.otherwise {
        goto(IDLE)
      }
    }
    SECOND_SE0.whenIsActive {
      when(se0) {
        goto(THIRD_SE0)
      }.otherwise {
        goto(IDLE)
      }
    }
    THIRD_SE0.whenIsActive {
      eopDetected := j
      when(se0) {
        goto(THIRD_SE0)
      }.elsewhen(j) {
        goto(IDLE)
      }.otherwise {
        goto(LAST_CHANCE)
      }
    }
    LAST_CHANCE.whenIsActive {
      eopDetected := j
      goto(IDLE)
    }
  })

  when(io.ackEOP || usbResetDetected) {
    softResetFSM := True
    eopDetected := False
  }

  val USB_RESET_REQUIRED_SE0_CYCLES = 120
  val se0_counter = Counter(0 to USB_RESET_REQUIRED_SE0_CYCLES)

  when(se0 && !se0_counter.willOverflowIfInc) {
    se0_counter.increment()
  }

  when(se0_counter.willOverflowIfInc) {
    usbResetDetected := True
  }

  when(!se0 && io.ackUsbRst) {
    usbResetDetected := False
    se0_counter.clear()
  }
}
