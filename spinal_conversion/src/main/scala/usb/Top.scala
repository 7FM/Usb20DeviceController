package usb

import spinal.core._
import spinal.lib._
import spinal.lib.io._
import usb.blackboxes._

import scala.language.postfixOps

// Companion object for static vals
object TopModule {
  val clockDomainConfig = ClockDomainConfig(
    clockEdge = RISING,
    resetKind = ASYNC,
    resetActiveLevel = HIGH,
    softResetActiveLevel = HIGH
  )
  val MySpinalConfig =
    SpinalConfig(defaultConfigForClockDomains = clockDomainConfig);
}

//Hardware definition
class TopModule(config: USBModuleConfig) extends Component {
  val io = new Bundle {
    val LED = config.useDebugLED generate (new Bundle {
      val R = out Bits (1 bits)
      val G = out Bits (1 bits)
      val B = out Bits (1 bits)
    })

    val clk = in Bool ()
    val USB = master(USB2_0())
  }

  // TODO instanciate stuff!

  // Create an Area to manage all clocks and reset things
  val clkCtrl = new Area {
    // Instantiate and drive the PLL
    val pll = new SB_PLL40_2_PAD(
      feedbackPath = "SIMPLE",
      divr = U"0000",
      divf = U"011_1111",
      divq = U"100",
      filterRange = U"001"
    )
    pll.io.RESETB := True
    pll.io.BYPASS := False
    pll.io.PACKAGEPIN := io.clk

    // Create a new clock domain named 'core'
    val clk12MHzDomain = ClockDomain.internal(
      name = "clk12",
      frequency = FixedFrequency(12 MHz)
    )
    val clk48MHzDomain = ClockDomain.internal(
      name = "clk48",
      frequency = FixedFrequency(48 MHz)
    )

    // Drive clock and reset signals of the coreClockDomain previously created
    clk12MHzDomain.clock := pll.io.PLLOUTGLOBALA
    clk48MHzDomain.clock := pll.io.PLLOUTGLOBALB
    clk12MHzDomain.reset := ResetCtrl.asyncAssertSyncDeassert(
      input = ClockDomain.current.readResetWire || !pll.io.LOCK,
      clockDomain = clk12MHzDomain
    )
    clk48MHzDomain.reset := ResetCtrl.asyncAssertSyncDeassert(
      input = ClockDomain.current.readResetWire || !pll.io.LOCK,
      clockDomain = clk48MHzDomain
    )
  }

  val usb = new USBTop(config, clkCtrl.clk12MHzDomain, clkCtrl.clk48MHzDomain)
  if (config.useDebugLED) {
    io.LED.R <> usb.io.LED.R
    io.LED.G <> usb.io.LED.G
    io.LED.B <> usb.io.LED.B
  }
  io.USB <> usb.io.USB
}

//Generate the MyTopLevel's Verilog
object MyTopLevelVerilog {
  def main(args: Array[String]) {
    val config = USBModuleConfig(
      _isSim = false
      // _useDebugLED = true // TODO disable!
    )
    TopModule.MySpinalConfig
      .generateVerilog(InOutWrapper(new TopModule(config)))
      .printPruned()
  }
}
object MySimTopLevelVerilog {
  def main(args: Array[String]) {
    val config = USBModuleConfig(
      _isSim = true,
      _useDebugLED = true
    )
    // TODO do we want to use the InOutWrapper?
    TopModule.MySpinalConfig
      .generateVerilog(InOutWrapper(new TopModule(config)))
      .printPruned()
  }
}
