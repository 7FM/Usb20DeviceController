#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <string>

#define TOP_MODULE Vsim_echo
#include "Vsim_echo.h"       // basic Top header
#include "Vsim_echo__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/fifo_utils.hpp"
#include "common/print_utils.hpp"
#include "common/usb_transactions.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class UsbEchoSim : public VerilatorTB<UsbEchoSim, TOP_MODULE> {

  private:
    uint8_t rx_clk12_counter;
    uint8_t tx_clk12_counter;

  public:
    void simReset() {
        // Data send/transmit interface
        top->txReqSendPacket = 0;
        top->txIsLastByte = 0;
        top->txDataValid = 0;
        top->txData = 0;
        // Data receive interface
        top->rxAcceptNewData = 0;
        top->rxClk12 = 0;
        top->txClk12 = 0;

        rxState.reset();
        txState.reset();
        rxState.actAsNop();
        txState.actAsNop();

        tx_clk12_counter = 0;
        rx_clk12_counter = clk12Offset;

        top->rxRST = 1;
        // Give modules some time to settle
        constexpr int resetCycles = 10;
        run<true, false, false, false, false>(resetCycles);
        top->rxRST = 0;

        // Finally run the us reset procedure
        usbReset();
    }

    bool stopCondition() {
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop;
    }

    void onRisingEdge() {
        tx_clk12_counter = (tx_clk12_counter + 1) % 2;
        bool posedge = false;
        bool negedge = false;
        if (tx_clk12_counter == 0) {
            top->txClk12 = !top->txClk12;
            negedge = !(posedge = top->txClk12);
        }

        if (posedge) {
            feedTransmitSerializer(top, txState);
        }

        rx_clk12_counter = (rx_clk12_counter + 1) % 2;
        posedge = false;
        negedge = false;
        if (rx_clk12_counter == 0) {
            top->rxClk12 = !top->rxClk12;
            negedge = !(posedge = top->rxClk12);
        }
        receiveDeserializedInput(*this, top, rxState, posedge, negedge);
    }

    void issueDummySignal() {
        top->dummyPin = 1;
        run<true, false, false, false, false>(1);
        top->dummyPin = 0;
    }

    void usbReset() {
        top->forceSE0 = 1;
        // Run with the reset signal for some time //TODO how many cycles exactly???
        run<true, false>(200);
        top->forceSE0 = 0;
    }

    bool customInit(int opt) { return false; }
    void onFallingEdge() {}
    void sanityChecks() {}

  public:
    // Usb data receive state variables
    UsbReceiveState rxState;
    UsbTransmitState txState;

    uint8_t clk12Offset = 0;
};

bool getForceStop() {
    return forceStop;
}

static bool compareVec(const std::vector<uint8_t> &expected, const std::vector<uint8_t> &got,
                       const std::string &lengthErrMsg, const std::string &dataErrMsg) {
    bool failed = false;
    if (got.size() != expected.size()) {
        std::cout << lengthErrMsg << std::endl;
        std::cout << "  Expected: " << expected.size() << " but got: " << got.size() << std::endl;
        failed = true;
    }

    IosFlagSaver _(std::cout);
    int minSize = std::min(got.size(), expected.size());
    for (int i = 0; i < minSize; ++i) {
        if (got[i] != expected[i]) {
            failed = true;
            std::cout << dataErrMsg << std::dec << i << std::endl;
            std::cout << "  Expected: 0x" << std::hex << static_cast<int>(expected[i]) << " but got: 0x" << static_cast<int>(got[i]) << std::endl;
        }
    }
    return failed;
}

/******************************************************************************/

int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbEchoSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    sim.issueDummySignal();

    bool failed = false;
    std::vector<uint8_t> result;
    std::vector<ConfigurationDescriptor> configDescs;
    std::vector<InterfaceDescriptor> ifaceDescs;
    std::vector<EndpointDescriptor> epDescs;
    uint8_t ep0MaxPacketSize = 0;
    uint8_t addr = 0;

    // Device setup!

    // Read the device descriptor
    // First, only read 8 bytes to determine the ep0MaxPacketSize
    // Afterwards read it all!
    failed |= readDescriptor(result, sim, DESC_DEVICE, 0, ep0MaxPacketSize, addr, 8);

    if (result.size() != 18) {
        std::cout << "Unexpected Descriptor size of " << result.size() << " instead of 18!" << std::endl;
        failed = true;
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    std::cout << std::endl;
    std::cout << "Lets try reading the configuration descriptor!" << std::endl;

    // Read the default configuration
    failed |= readDescriptor(result, sim, DESC_CONFIGURATION, 0, ep0MaxPacketSize, addr, 9, getConfigurationDescriptorSize);

    std::cout << "Result size: " << result.size() << std::endl;

    prettyPrintDescriptors(result, &epDescs, &ifaceDescs, &configDescs);
    // TODO check content

    if (failed) {
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    // set address to 42
    std::cout << "Setting device address to 42!" << std::endl;
    failed |= sendValueSetRequest(sim, DEVICE_SET_ADDRESS, 42, ep0MaxPacketSize, 0, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    addr = 42;

    sim.issueDummySignal();
    std::cout << std::endl;
    std::cout << "Selecting device configuration 1 (correct addr)!" << std::endl;
    failed = sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.txState.actAsNop();
    sim.txState.reset();
    sim.rxState.actAsNop();
    sim.rxState.reset();

    {
        int testSize = 1 + (sim.getRand() & (512 - 1));
        std::cout << "Sending data to EP1: " << testSize << std::endl;
        std::vector<uint8_t> ep1Data;

        for (int i = 0; i < testSize; ++i) {
            ep1Data.push_back(sim.getRand());
        }

        // send data to EP1
        bool dataToggleState = false;
        int maxPacketSize = epDescs[0].wMaxPacketSize & 0x7FF;
        if (maxPacketSize == 0) {
            failed = true;
            std::cout << "Extracted invalid wMaxPacketSize from EP1 descriptor" << std::endl;
            goto exitAndCleanup;
        }

        failed = sendItAll(ep1Data, dataToggleState, sim, addr, maxPacketSize, 1);
        if (failed) {
            goto exitAndCleanup;
        }

        sim.txState.actAsNop();
        sim.rxState.actAsNop();

        // wait some cycles to let the echo implementation transfer the data from the receive FIFO to the send FIFO
        sim.template run<true, false>(ep1Data.size());

        std::cout << "Requesting data from EP1" << std::endl;
        std::vector<uint8_t> ep1Res;
        failed = readItAll(ep1Res, sim, addr, ep1Data.size(), ep0MaxPacketSize, 1);

        failed |= compareVec(
            ep1Data, ep1Res,
            "Error: Echoed data length & sent data does not match!",
            "Echoed data vs sent data does not match at index: ");
    }

    sim.txState.actAsNop();
    sim.txState.reset();
    sim.rxState.actAsNop();
    sim.rxState.reset();

exitAndCleanup:

    std::cout << std::endl;
    std::cout << "Tests ";

    if (forceStop) {
        std::cout << "ABORTED!" << std::endl;
        std::cerr << "The user requested a forced stop!" << std::endl;
    } else if (failed) {
        std::cout << "FAILED! Seed: " << sim.getSeed() << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    return 0;
}