package usb.sie.tx

import spinal.core._
import spinal.lib._
import spinal.lib.fsm._

import scala.language.postfixOps

class OutputShiftReg() extends Component {
  val length = 8

  val io = new Bundle {
    val en = in Bool ()
    val dataValid = in Bool ()
    val crc5Patch = in Bool ()
    val dataIn = in Bits (length bits)
    val dataOut = out Bool ()
    val bufferEmpty = out Bool ()
    val crc5PatchNow = out Bool ()
  }

  // val dataBuf = RegInit(B(length bits, default -> True))
  val dataBuf = Vec(Reg(Bool) init (True), length)
  val bitsLeft = Reg(UInt(log2Up(length) bits)) init (0)
  // The buffer is empty (single cycle tick) if the bitsLeft are 0 (last bit will be send next) and en_i is set (last bit will be send THIS cycle)
  io.bufferEmpty := bitsLeft === 0 && io.en
  // Signal when crc5 patching should happen, this has to consider bitstuffing (en_i), similar to bufferEmpty_o
  io.crc5PatchNow := bitsLeft === 5 && io.en

  val defaultNextBitsLeft = UInt(log2Up(length) bits)
  defaultNextBitsLeft := bitsLeft
  when(!io.bufferEmpty && io.en) {
    defaultNextBitsLeft := bitsLeft - 1
  }

  io.dataOut := dataBuf(0)

  when(io.dataValid) {
    dataBuf.asBits := io.dataIn
    // As the crc5PatchNow_o condition contains en_i we know that
    // if crc5Patch_i is set then en_i will be set too, we also know that
    // !bufferEmpty_o is true -> Hence we can use the default bitsLeft update value!
    // Otherwise on an normal dataBuf update we simply set the new bits left to LENGTH - 1
    bitsLeft := io.crc5Patch ? defaultNextBitsLeft | length - 1
  }.otherwise {
    bitsLeft := defaultNextBitsLeft

    when(io.en) {
      dataBuf(length - 1) := True
      for (i <- 1 to (length - 1)) {
        dataBuf(i - 1) := dataBuf(i)
      }
    }
  }
}
