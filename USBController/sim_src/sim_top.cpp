#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <string>

#define TOP_MODULE Vsim_top
#include "Vsim_top.h"       // basic Top header
#include "Vsim_top__Syms.h" // all headers to access exposed internal signals

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

class UsbTopSim : public VerilatorTB<UsbTopSim, TOP_MODULE> {

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
        top->rxCLK12 = 0;
        top->txCLK12 = 0;

        top->rxRST = 1;
        // Give modules some time to settle
        constexpr int resetCycles = 10;
        run<false, false, false, false, false>(resetCycles);
        top->rxRST = 0;

        rxState.reset();
        txState.reset();
        fifoFillState.reset();
        fifoEmptyState.reset();

        tx_clk12_counter = 0;
        rx_clk12_counter = clk12Offset;

        // Finally run the us reset procedure
        usbReset();
    }

    bool stopCondition() {
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop
            || (fifoFillState.isEnabled() && fifoFillState.allDone())
            || (fifoEmptyState.isEnabled() && fifoEmptyState.allDone());
    }

    void onRisingEdge() {
        tx_clk12_counter = (tx_clk12_counter + 1) % 2;
        bool posedge = false;
        bool negedge = false;
        if (tx_clk12_counter == 0) {
            top->txCLK12 = !top->txCLK12;
            negedge = !(posedge = top->txCLK12);
        }

        if (posedge) {
            feedTransmitSerializer(top, txState);
        }

        rx_clk12_counter = (rx_clk12_counter + 1) % 2;
        posedge = false;
        negedge = false;
        if (rx_clk12_counter == 0) {
            top->rxCLK12 = !top->rxCLK12;
            negedge = !(posedge = top->rxCLK12);
        }
        receiveDeserializedInput(top, rxState, posedge, negedge);

        fillFIFO(top, fifoFillState);
        emptyFIFO(top, fifoEmptyState);
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

    // EP fifo state variables
    FIFOFillState<1> fifoFillState;
    FIFOEmptyState<1> fifoEmptyState;

    uint8_t clk12Offset = 0;
};

bool getForceStop() {
    return forceStop;
}

static bool compareVec(const std::vector<uint8_t> &expected, const std::vector<uint8_t> &got,
                       const std::string &lengthErrMsg, const std::string &dataErrMsg) {
    if (got.size() != expected.size()) {
        std::cout << lengthErrMsg << std::endl;
        std::cout << "  Expected: " << expected.size() << " but got: " << got.size() << std::endl;
        return true;
    }

    bool failed = false;
    for (int i = 0; i < got.size(); ++i) {
        if (got[i] != expected[i]) {
            failed = true;
            std::cout << "Fifo fill data vs received data does not match at index: " << i << std::endl;
            std::cout << "  Expected: " << expected[i] << " but got: " << got[i] << std::endl;
        }
    }
    return failed;
}

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbTopSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    bool failed = false;

    std::vector<uint8_t> result;
    std::vector<ConfigurationDescriptor> configDescs;
    std::vector<InterfaceDescriptor> ifaceDescs;
    std::vector<EndpointDescriptor> epDescs;
    uint8_t ep0MaxPacketSize = 0;
    uint8_t addr = 0;

    failed |= sendSOF(sim, 0);
    if (failed) {
        goto exitAndCleanup;
    }

    // Execute a few more cycles to give the logic some time between the packages
    sim.template run<true, false>(2);

    failed |= sendSOF(sim, 0xFFFF);
    if (failed) {
        goto exitAndCleanup;
    }

    // Execute a few more cycles to give the logic some time between the packages
    sim.template run<true, false>(2);

    // Read the device descriptor
    // First, only read 8 bytes to determine the ep0MaxPacketSize
    // Afterwards read it all!
    failed |= readDescriptor(result, sim, DESC_DEVICE, 0, ep0MaxPacketSize, addr, 8);

    if (result.size() != 18) {
        std::cout << "Unexpected Descriptor size of " << result.size() << " instead of 18!" << std::endl;
        failed = true;
        goto exitAndCleanup;
    }

    {
        std::cout << "Device Descriptor:" << std::endl;
        prettyPrintDescriptors(result);
        // TODO check content

        const char *stringDescName[] = {
            "Manufacturer Name:",
            "Product Name:",
            "Serial Number:",
            "Configuration Description:",
            "Interface Description:",
        };
        for (int i = 0; !failed && i < sizeof(stringDescName) / sizeof(stringDescName[0]); ++i) {
            sim.issueDummySignal();
            failed |= readDescriptor(result, sim, DESC_STRING, i + 1, ep0MaxPacketSize, addr, 2);
            std::cout << "Read String Descriptor for the " << stringDescName[i] << std::endl;
            prettyPrintDescriptors(result);
            // TODO check content
        }
    }

    if (failed) {
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    std::cout << std::endl << "Lets try reading the configuration descriptor!" << std::endl;

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
    // set configuration value to 1
    std::cout << std::endl << "Selecting device configuration 1 (with wrong addr -> should fail)!" << std::endl;
    // This is expected to fail!
    failed |= !sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr + 1, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    std::cout << std::endl << "Selecting device configuration 1 (correct addr)!" << std::endl;
    failed = sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.txState.actAsNop();
    sim.rxState.actAsNop();

    // fill EP1_OUT fifo / execute fifo filling!
    std::cout << "Filling EP1 OUT fifo" << std::endl;
    for (uint8_t i = 0; i < 32; ++i)
        sim.fifoFillState.epState->data.push_back(i);
    sim.fifoFillState.enable();
    // Execute till stop condition
    while (!sim.template run<true>(0)) {
    }
    sim.fifoFillState.disable();

    {
        std::cout << "Requesting data from EP1" << std::endl;
        std::vector<uint8_t> ep1Res;
        failed = readItAll(ep1Res, sim, addr, sim.fifoFillState.epState->data.size(), ep0MaxPacketSize, 1);

        const auto &sentData = sim.fifoFillState.epState->data;
        failed |= compareVec(
            sentData, ep1Res,
            "Error: Fifo data length & received data does not match!",
            "Fifo fill data vs received data does not match at index: ");
    }

    sim.txState.actAsNop();
    sim.txState.reset();
    sim.rxState.actAsNop();
    sim.rxState.reset();

    if (failed) {
        goto exitAndCleanup;
    }

    {
        std::cout << "Sending data to EP1" << std::endl;
        std::vector<uint8_t> ep1Data;

        int maxPacketSize = epDescs[0].wMaxPacketSize & 0x7FF;
        // Send more data than possible with a single packet -> tests whether data toggle works!
        int upperBound = maxPacketSize + 5;
        // Ensure that we do not exceed our buffer capabilities!
        upperBound = upperBound > 512 ? 512 : upperBound;
        for (int i = 0; i < upperBound; ++i)
            ep1Data.push_back(i);

        // send data to EP1
        bool dataToggleState = false;
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
        sim.txState.reset();
        sim.rxState.actAsNop();
        sim.rxState.reset();

        // check contents of EP1_IN fifo
        sim.fifoEmptyState.enable();
        // Execute till stop condition
        while (!sim.template run<true>(0)) {
        }
        sim.fifoEmptyState.disable();

        failed |= compareVec(
            ep1Data, sim.fifoEmptyState.epState->data,
            "Error: Fifo data length & sent data does not match!",
            "Fifo empty data vs sent data does not match at index: ");
    }

    sim.txState.actAsNop();
    sim.txState.reset();
    sim.rxState.actAsNop();
    sim.rxState.reset();

exitAndCleanup:

    std::cout << std::endl << "Tests ";

    if (forceStop) {
        std::cout << "ABORTED!" << std::endl;
        std::cerr << "The user requested a forced stop!" << std::endl;
    } else if (failed) {
        std::cout << "FAILED!" << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    return 0;
}