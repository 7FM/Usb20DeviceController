package usb.sie.rx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._

import scala.language.postfixOps

//TODO create interface? this would be really nice if we can mux entire interface connections!

class DPPL() extends Component {
  val io = new Bundle {
    val reset = in Bool ()
    val dataInP = in Bool ()
    val dataInP_negedge = in Bool ()
    val rxClk = out Bool ()
    val DPPLGotSignal = out Bool ()
  }

  object DPPLStates extends SpinalEnum {
    val STATE_C, STATE_D, STATE_B, STATE_F, STATE_5, STATE_7, STATE_6, STATE_4,
        STATE_1, STATE_3, STATE_2, STATE_0 = newElement()

    defaultEncoding = SpinalEnumEncoding("staticEncoding")(
      STATE_C -> 0xc,
      STATE_D -> 0xd,
      STATE_B -> 0xb,
      STATE_F -> 0xf,
      STATE_5 -> 0x5,
      STATE_7 -> 0x7,
      STATE_6 -> 0x6,
      STATE_4 -> 0x4,
      STATE_1 -> 0x1,
      STATE_3 -> 0x3,
      STATE_2 -> 0x2,
      STATE_0 -> 0x0
    )
  }

  val fsmState = RegInit(DPPLStates.STATE_C.asBits)
  val fsmStateAsEnum = DPPLStates()
  fsmStateAsEnum.assignFromBits(fsmState)

  io.rxClk := fsmState(1)
  io.DPPLGotSignal := fsmStateAsEnum === DPPLStates.STATE_D || fsmState.asUInt <= DPPLStates.STATE_3.asBits.asUInt

  // graycode counter
  fsmState := fsmState(3 downto 2) ## fsmState(0) ## (fsmState(1) ^ True)

  switch(fsmStateAsEnum) {
    is(DPPLStates.STATE_C) {
      when(fsmState(0) ^ io.dataInP_negedge) {
        fsmState := fsmState
      }
    }
    is(DPPLStates.STATE_D) {
      when(fsmState(0) ^ io.dataInP_negedge) {
        fsmState := fsmState
      }.otherwise {
        fsmState := False ## fsmState(2 downto 0)
      }
    }
    // Swap side transitions
    is(DPPLStates.STATE_F, DPPLStates.STATE_B) {
      // Keep changes of the grayCode but clear the MSB bit
      fsmState(3) := False
    }
    is(DPPLStates.STATE_7, DPPLStates.STATE_3) {
      when(fsmState(2) ^ io.dataInP) {
        // if in state 7: Get to state B
        // if in state 3: Get to state F
        // both lower bits are 1 -> order does not matter but maybe the synthesis can use this to combine paths for STATE 7,3 & 6,2
        fsmState := ~fsmState(3) ## ~fsmState(2) ## fsmState(0) ## fsmState(1)
      }
    }
    is(DPPLStates.STATE_6, DPPLStates.STATE_2) {
      when(fsmState(2) ^ io.dataInP) {
        // if in state 6: Get to state 1
        // if in state 2: Get to state 5
        fsmState := fsmState(3) ## ~fsmState(3) ## fsmState(0) ## fsmState(1)
      }
    }
    is(DPPLStates.STATE_4, DPPLStates.STATE_0) {
      when(fsmState(2) ^ io.dataInP) {
        // if in state 4: Get to state 1
        // if in state 0: Get to state 5
        fsmState(2) := ~fsmState(2);
      }
    }
  }

  when(io.reset) {
    fsmState := DPPLStates.STATE_C.asBits
  }
}
