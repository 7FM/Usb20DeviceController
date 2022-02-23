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

/* Linus USB error codes: https://www.kernel.org/doc/html/latest/driver-api/usb/error-codes.html and https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/errno.h and https://github.com/torvalds/linux/blob/master/tools/include/uapi/asm-generic/errno-base.h
SUCCESS = 0
    Transfer completed successfully

-ENOENT = -2
    URB was synchronously unlinked by usb_unlink_urb()

-EINPROGRESS = -115
    URB still pending, no results yet (That is, if drivers see this it’s a bug.)

-EPROTO = -71
    bitstuff error
    no response packet received within the prescribed bus turn-around time
    unknown USB error

-EILSEQ = -84
    CRC mismatch
    no response packet received within the prescribed bus turn-around time
    unknown USB error
    Note that often the controller hardware does not distinguish among cases a), b), and c), so a driver cannot tell whether there was a protocol error, a failure to respond (often caused by device disconnect), or some other fault.

-ETIME = -62
    No response packet received within the prescribed bus turn-around time. This error may instead be reported as -EPROTO or -EILSEQ.

-ETIMEDOUT = -110
    Synchronous USB message functions use this code to indicate timeout expired before the transfer completed, and no other error was reported by HC.

-EPIPE = -32
    Endpoint stalled. For non-control endpoints, reset this status with usb_clear_halt().

-ECOMM = -70
    During an IN transfer, the host controller received data from an endpoint faster than it could be written to system memory

-ENOSR = -63
    During an OUT transfer, the host controller could not retrieve data from system memory fast enough to keep up with the USB data rate

-EOVERFLOW = -75
    The amount of data returned by the endpoint was greater than either the max packet size of the endpoint or the remaining buffer size. “Babble”.

-EREMOTEIO = -121
    The data read from the endpoint did not fill the specified buffer, and URB_SHORT_NOT_OK was set in urb->transfer_flags.

-ENODEV = -19
    Device was removed. Often preceded by a burst of other errors, since the hub driver doesn’t detect device removal events immediately.

-EXDEV = -18
    ISO transfer only partially completed (only set in iso_frame_desc[n].status, not urb->status)

-EINVAL = -22
    ISO madness, if this happens: Log off and go home

-ECONNRESET = -104
    URB was asynchronously unlinked by usb_unlink_urb()

-ESHUTDOWN = -108
    The device or host controller has been disabled due to some problem that could not be worked around, such as a physical disconnect.

*/

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
        top->rxClk12 = 0;
        top->txClk12 = 0;

        rxState.reset();
        txState.reset();
        rxState.actAsNop();
        txState.actAsNop();
        fifoFillState.reset(top);
        fifoEmptyState.reset(top);

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
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop
            || (fifoFillState.isEnabled() && fifoFillState.allDone())
            || (fifoEmptyState.isEnabled() && fifoEmptyState.allDone());
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

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbTopSim sim;
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
            "String Desc 0:",
            "Manufacturer Name:",
            "Product Name:",
            "Serial Number:",
            "Configuration Description:",
            "Interface Description:",
        };
        for (int i = 0; !failed && i < sizeof(stringDescName) / sizeof(stringDescName[0]); ++i) {
            sim.issueDummySignal();
            failed |= readDescriptor(result, sim, DESC_STRING, i, ep0MaxPacketSize, addr, 2);
            std::cout << "Read String Descriptor for the " << stringDescName[i] << std::endl;
            prettyPrintDescriptors(result);
            // TODO check content
        }
    }

    if (failed) {
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
    // select a random address
    addr = sim.getRand() & ((1 << 7) - 1);
    if (addr == 0) {
        ++addr;
    }
    std::cout << "Setting device address to " << static_cast<int>(addr) << '!' << std::endl;
    failed |= sendValueSetRequest(sim, DEVICE_SET_ADDRESS, addr, ep0MaxPacketSize, 0, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    // set configuration value to 1
    std::cout << std::endl;
    std::cout << "Selecting device configuration 1 (with wrong addr -> should fail)!" << std::endl;
    // This is expected to fail!
    failed |= !sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr + 1, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.issueDummySignal();
    std::cout << std::endl;
    std::cout << "Selecting device configuration 1 (correct addr)!" << std::endl;
    failed = sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    sim.txState.actAsNop();
    sim.rxState.actAsNop();

    {
        // fill EP1_OUT fifo / execute fifo filling!
        int testSize = 1 + (sim.getRand() & (512 - 1));
        std::cout << "Filling EP1 OUT fifo: " << testSize << std::endl;
        for (int i = 0; i < testSize; ++i) {
            sim.fifoFillState.epState->data.push_back(sim.getRand());
        }
        sim.fifoFillState.enable();
        // Execute till stop condition
        while (!sim.template run<true>(0)) {
        }
        sim.fifoFillState.disable();

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