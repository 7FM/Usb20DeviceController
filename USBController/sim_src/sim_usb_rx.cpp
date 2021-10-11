#include <atomic>
#include <csignal>
#include <cstdint>

#define TOP_MODULE Vsim_usb_rx
#include "Vsim_usb_rx.h"       // basic Top header
#include "Vsim_usb_rx__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/print_utils.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

#ifndef USB_SIGNAL_LENGTH
#define USB_SIGNAL_LENGTH 4
#endif

#define APPLY_USB_SIGNAL_ON_RISING_EDGE 0

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}
/******************************************************************************/

class UsbRxSim : public VerilatorTB<UsbRxSim, TOP_MODULE> {
  private:
    static constexpr auto signalToReceive = constructSignal(usbSyncSignal, nrziEncode<true, PID_DATA0, static_cast<uint8_t>(0xDE), static_cast<uint8_t>(0xAD), static_cast<uint8_t>(0xBE), static_cast<uint8_t>(0xEF)>(), usbEOPSignal);

    int signalIdx;
    uint8_t delayCnt;

    uint8_t clk12_counter;

    void applyUsbSignal(const uint8_t *data, std::size_t arraySize) {
        if (signalIdx + 1 < arraySize) {
            delayCnt = (delayCnt + 1) % USB_SIGNAL_LENGTH;
            if (delayCnt == 0) {
                top->USB_DP = data[signalIdx++];
                top->USB_DN = data[signalIdx++];
            }
        }
    }

  public:
    void simReset() {
        // Set inputs to valid states
        top->USB_DP = 1;
        top->USB_DN = 0;

        top->rxRST = 0;
        top->rxAcceptNewData = 0;
        top->CLK12 = 0;

        // Simulation state
        signalIdx = 0;
        // Here we could test different signal start offsets!
        delayCnt = 0;

        clk12_counter = clk12Offset;

        rxState.reset();
    }

    bool stopCondition() {
        return (signalIdx >= signalToReceive.size() && rxState.receivedLastByte) || forceStop;
    }

    void onRisingEdge() {

        clk12_counter = (clk12_counter + 1) % 2;
        bool posedge = false;
        bool negedge = false;
        if (clk12_counter == 0) {
            top->CLK12 = !top->CLK12;
            negedge = !(posedge = top->CLK12);
        }
        receiveDeserializedInput(top, rxState, posedge, negedge);

#if APPLY_USB_SIGNAL_ON_RISING_EDGE
        applyUsbSignal(signalToReceive.data(), signalToReceive.size());
#endif
    }

    void onFallingEdge() {
#if !APPLY_USB_SIGNAL_ON_RISING_EDGE
        applyUsbSignal(signalToReceive.data(), signalToReceive.size());
#endif
    }

    bool customInit(int opt) { return false; }
    void sanityChecks() {}

  public:
    // Usb data receive state variables
    UsbReceiveState rxState;

    uint8_t clk12Offset = 0;
};

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbRxSim sim;
    sim.init(argc, argv);

    for (sim.clk12Offset = 0; sim.clk12Offset < 4; ++sim.clk12Offset) {
        std::cout << "Use CLK12 offset of " << static_cast<int>(sim.clk12Offset) << std::endl;

        // start things going
        sim.reset();

        // Execute till stop condition
        while (!sim.run<true>(0));
        // Execute a few more cycles
        sim.run<true, false>(4 * 10);

        {
            IosFlagSaver flagSaver(std::cout);
            std::cout << "Received Data:" << std::endl;
            for (auto data : sim.rxState.receivedData) {
                std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
            }
        }
    }

    return 0;
}