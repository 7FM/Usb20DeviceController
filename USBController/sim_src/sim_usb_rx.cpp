#include <atomic>
#include <csignal>
#include <cstdint>

#define TOP_MODULE Vsim_usb_rx
#include "Vsim_usb_rx.h"       // basic Top header
#include "Vsim_usb_rx__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
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

    void applyUsbSignal(TOP_MODULE *top, const uint8_t *data, std::size_t arraySize) {
        if (signalIdx + 1 < arraySize) {
            delayCnt = (delayCnt + 1) % USB_SIGNAL_LENGTH;
            if (delayCnt == 0) {
                top->USB_DP = data[signalIdx++];
                top->USB_DN = data[signalIdx++];
            }
        }
    }

  public:
    void simReset(TOP_MODULE *top) {
        // Set inputs to valid states
        top->USB_DP = 1;
        top->USB_DN = 0;

        top->rxRST = 0;
        top->rxAcceptNewData = 0;

        // Simulation state
        signalIdx = 0;
        // Here we could test different signal start offsets!
        delayCnt = 0;
    }

    bool stopCondition(TOP_MODULE *top) {
        return (signalIdx >= signalToReceive.size() && rxState.receivedLastByte) || forceStop;
    }

    void onRisingEdge(TOP_MODULE *top) {
        receiveDeserializedInput(top, rxState);
#if APPLY_USB_SIGNAL_ON_RISING_EDGE
        applyUsbSignal(top, signalToReceive.data(), signalToReceive.size());
#endif
    }

    void onFallingEdge(TOP_MODULE *top) {
#if !APPLY_USB_SIGNAL_ON_RISING_EDGE
        applyUsbSignal(top, signalToReceive.data(), signalToReceive.size());
#endif
    }

    bool customInit(int opt) { return false; }
    void sanityChecks(const TOP_MODULE *top) {}

  public:
    // Usb data receive state variables
    UsbReceiveState rxState;
};

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbRxSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    // Execute till stop condition
    while (!sim.run<true>(0));
    // Execute a few more cycles
    sim.run<true, false>(4 * 10);

    std::cout << "Received Data:" << std::endl;
    for (auto data : sim.rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }

    return 0;
}