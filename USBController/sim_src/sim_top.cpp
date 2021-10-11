#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <functional>

#define TOP_MODULE Vsim_top
#include "Vsim_top.h"       // basic Top header
#include "Vsim_top__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/print_utils.hpp"
#include "common/usb_descriptors.hpp"
#include "common/usb_packets.hpp"
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

        tx_clk12_counter = 0;
        rx_clk12_counter = clk12Offset;
    }

    bool stopCondition() {
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop;
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
    }

    void issueDummySignal() {
        top->dummyPin = 1;
        run<true, false, false, false, false>(1);
        top->dummyPin = 0;
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

template <class T>
static void fillVector(std::vector<uint8_t> &vec, const T &data) {
    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&data);
    for (int i = 0; i < sizeof(T); ++i) {
        vec.push_back(*rawPtr);
        ++rawPtr;
    }
}

static bool sendStuff(UsbTopSim &sim, std::function<void()> fillSendData) {
    // Disable receive logic
    sim.rxState.actAsNop();

    // Reset done sending flag
    sim.txState.reset();

    fillSendData();

    // Execute till stop condition
    while (!sim.run<true>(0));

    assert(sim.txState.doneSending);

    return forceStop;
}

static bool receiveStuff(UsbTopSim &sim, const char *errMsg) {
    // Enable timeout for receiving a response
    sim.rxState.reset();
    sim.rxState.enableTimeout = true;

    // Disable sending logic
    sim.txState.actAsNop();

    // Execute till stop condition
    while (!sim.run<true>(0));

    if (sim.rxState.timedOut) {
        std::cerr << errMsg << std::endl;
        return true;
    }
    assert(sim.rxState.receivedLastByte);

    return forceStop;
}

class InTransaction {
    /*
    In Transaction:
    1. Send Token packet
    2. Receive Data packet / Timeout
    3. (Send Handshake)
    */
  public:
    TokenPacket inTokenPacket;
    PID_Types handshakeToken;

    bool send(UsbTopSim &sim) {
        //=========================================================================
        // 1. Send Token packet
        sim.issueDummySignal();
        std::cout << "Send IN token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, inTokenPacket);
        })) return true;

        //=========================================================================
        // 2. Receive Data packet / Timeout
        sim.issueDummySignal();
        std::cout << "Receive IN data!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for input data!"))
            return true;

        //=========================================================================
        // 3. (Send Handshake)
        sim.issueDummySignal();
        std::cout << "Send handshake!" << std::endl;

        if(sendStuff(sim, [&]{
            sim.txState.dataToSend.push_back(handshakeToken);
        })) return true;

        return false;
    }
};

class OutTransaction {
    /*
    Out Transaction:
    1. Send Token packet
    2. Send Data packet
    3. Receive Handshake / Timeout
    */
  public:
    TokenPacket outTokenPacket;
    std::vector<uint8_t> dataPacket;

    bool send(UsbTopSim &sim) {
        //=========================================================================
        // 1. Send Token packet
        sim.issueDummySignal();
        std::cout << "Send OUT token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, outTokenPacket);
        })) return true;

        // Execute a few more cycles to give the logic some time between the packages
        sim.run<true, false>(10);

        //=========================================================================
        // 2. Send Data packet
        sim.issueDummySignal();
        std::cout << "Send OUT data!" << std::endl;

        if(sendStuff(sim, [&]{
            for (uint8_t data : dataPacket) {
                sim.txState.dataToSend.push_back(data);
            }
        })) return true;

        //=========================================================================
        // 3. Receive Handshake / Timeout
        sim.issueDummySignal();
        std::cout << "Wait for response!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for a response!"))
            return true;

        return false;
    }
};

static void printResponse(const std::vector<uint8_t> &response) {
    if (response.empty()) {
        std::cerr << "No response received!" << std::endl;
        return;
    }

    std::cout << "Got Response:" << std::endl;
    bool first = true;
    IosFlagSaver flagSaver(std::cout);
    for (auto data : response) {
        if (first) {
            std::cout << "    " << pidToString(static_cast<PID_Types>(data)) << std::endl;
        } else {
            std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
        }
        first = false;
    }
}

static bool readItAll(std::vector<uint8_t> &result, UsbTopSim &sim, int addr, int readSize, uint8_t ep0MaxDescriptorSize) {
    result.clear();

    InTransaction getDesc;
    getDesc.inTokenPacket.token = PID_IN_TOKEN;
    getDesc.inTokenPacket.addr = addr;
    getDesc.inTokenPacket.endpoint = 0;
    getDesc.inTokenPacket.crc = 0b11111; // Should be a dont care!
    getDesc.handshakeToken = PID_HANDSHAKE_ACK;

    do {
        std::cout << std::endl << "Send Input transaction packet" << std::endl;
        bool failed = getDesc.send(sim);
        printResponse(sim.rxState.receivedData);

        if (failed) {
            return true;
        }

        // Skip PID
        for (int i = 1; i < sim.rxState.receivedData.size(); ++i) {
            result.push_back(sim.rxState.receivedData[i]);
        }

        readSize -= sim.rxState.receivedData.size() - 1;

        if (sim.rxState.receivedData.size() - 1 != ep0MaxDescriptorSize && readSize > 0) {
            std::cerr << "ERROR: Received non max sized packet but still expecting data to come!" << std::endl;
            return true;
        }

    } while (readSize > 0);

    return false;
}

static bool expectHandshake(std::vector<uint8_t> &response, PID_Types expectedResponse) {
    if (response.size() != 1) {
        std::cerr << "Expected only a Handshake as response but got multiple bytes!" << std::endl;
        return true;
    }

    if (response[0] != expectedResponse) {
        IosFlagSaver flagSaver(std::cerr);
        std::cerr << "Expected Response: " << pidToString(expectedResponse) << " but got: " << pidToString(static_cast<PID_Types>(response[0])) << std::endl;
        return true;
    }

    return false;
}

static void updateSetupTrans(OutTransaction &setupTrans, SetupPacket &packet) {
    setupTrans.dataPacket.clear();
    setupTrans.dataPacket.push_back(PID_DATA0);
    fillVector(setupTrans.dataPacket, packet);
}

static OutTransaction initDescReadTrans(SetupPacket &packet, DescriptorType descType, uint8_t descIdx, uint8_t addr, uint16_t initialReadSize, StandardDeviceRequest request) {
    OutTransaction setupTrans;
    setupTrans.outTokenPacket.token = PID_SETUP_TOKEN;
    setupTrans.outTokenPacket.addr = addr;
    setupTrans.outTokenPacket.endpoint = 0;
    setupTrans.outTokenPacket.crc = 0b11111; // Should be a dont care!

    std::memset(&packet, 0, sizeof(packet));
    // Request type
    packet.request = request;

    // Descriptor type
    packet.wValueMsB = descType;
    // Descriptor index
    packet.wValueLsB = descIdx;
    // Zero or Language ID
    packet.wIndexLsB = packet.wIndexMsB = 0;
    // First Descriptor read length: if unknown just read the first 8 bytes
    packet.wLengthLsB = initialReadSize & 0x0FF;
    packet.wLengthMsB = (initialReadSize >> 8) & 0x0FF;

    updateSetupTrans(setupTrans, packet);

    return setupTrans;
}

static uint16_t defaultGetDescriptorSize(const std::vector<uint8_t> &result) {
    return result[0];
}

static uint16_t getConfigurationDescriptorSize(const std::vector<uint8_t> &result) {
    return static_cast<uint16_t>(result[2]) | (static_cast<uint16_t>(result[3]) << 8);
}

static bool sendOutputStage(UsbTopSim &sim, OutTransaction& outTrans) {
    bool failed = outTrans.send(sim);
    printResponse(sim.rxState.receivedData);
    failed |= expectHandshake(sim.rxState.receivedData, PID_HANDSHAKE_ACK);
    return failed;
}

static bool statusStage(UsbTopSim &sim, OutTransaction& outTrans) {
    // Status stage
    outTrans.outTokenPacket.token = PID_OUT_TOKEN;
    outTrans.dataPacket.clear();
    // For the status stage always DATA1 is used
    outTrans.dataPacket.push_back(PID_DATA1);
    // An empty data packet signals that everything was successful
    std::cout << "Status stage" << std::endl;
    return sendOutputStage(sim, outTrans);
}

static bool readDescriptor(std::vector<uint8_t> &result, UsbTopSim &sim, DescriptorType descType, uint8_t descIdx, uint8_t &ep0MaxDescriptorSize, uint8_t addr, uint16_t initialReadSize, std::function<uint16_t (const std::vector<uint8_t> &)> descSizeExtractor = defaultGetDescriptorSize, StandardDeviceRequest request = DEVICE_GET_DESCRIPTOR, bool recurse = true) {
    SetupPacket packet;
    OutTransaction setupTrans = initDescReadTrans(packet, descType, descIdx, addr, initialReadSize, request);

    std::cout << "Setup Stage" << std::endl;
    if (sendOutputStage(sim, setupTrans)) {
        return true;
    }

    std::cout << "Data Stage" << std::endl;
    bool failed = readItAll(result, sim, addr, initialReadSize, ep0MaxDescriptorSize == 0 ? 8 : ep0MaxDescriptorSize);

    if (result.size() != initialReadSize) {
        std::cerr << "Error: Desired to read first " << static_cast<int>(initialReadSize) << " bytes of the descriptor but got only: " << result.size() << " bytes!" << std::endl;
        failed = true;
    }

    if (failed) {
        return true;
    }

    if (result.size() == 0 && initialReadSize == 0) {
        // Zero length data phase -> ACK
        std::cout << "Received a zero length data phase and is interpret as an ACK!" << std::endl;
        return false;
    }

    uint16_t descriptorSize = descSizeExtractor(result);

    if (descType == DESC_DEVICE) {
        ep0MaxDescriptorSize = result[7];
        std::cout << "INFO: update EP0 Max packet size to: " << static_cast<int>(ep0MaxDescriptorSize) << std::endl;
    }

    // Status stage
    if (statusStage(sim, setupTrans)) {
        return true;
    }

    if (descriptorSize < initialReadSize) {
        std::cerr << "Error extracting the descriptor size: extracted " << static_cast<int>(descriptorSize) << " but expecting a size of at least " << static_cast<int>(initialReadSize) << std::endl;
        return true;
    } else if (descriptorSize > initialReadSize) {
        if (!recurse) {
            std::cerr << "No further read attempts are permitted, reading entire descriptor failed!" << std::endl;
            return true;
        }

        // Recursion to issue a new request! BUT this time with the correct initalReadSize set!
        // ALSO: further recursions will be disabled to ensure termination!
        return readDescriptor(result, sim, descType, descIdx, ep0MaxDescriptorSize, addr, descriptorSize, descSizeExtractor, request, false);
    }

    std::cout << "Successfully received a " << descTypeToString(descType) << " Descriptor!" << std::endl;

    return false;
}

static bool sendValueSetRequest(UsbTopSim &sim, StandardDeviceRequest request, uint16_t wValue, uint8_t &ep0MaxDescriptorSize, uint8_t addr, uint16_t initialReadSize) {
    std::vector<uint8_t> dummyRes;
    return readDescriptor(dummyRes, sim, static_cast<DescriptorType>((wValue >> 8) & 0x0FF), static_cast<uint8_t>((wValue >> 0) & 0x0FF), ep0MaxDescriptorSize, addr, initialReadSize, defaultGetDescriptorSize, request);
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
    uint8_t ep0MaxPacketSize = 0;
    uint8_t addr = 0;

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
        //TODO check content

        const char * stringDescName[] = {
            "Manufacturer Name:",
            "Product Name:",
            "Serial Number:",
            "Configuration Description:",
            "Interface Description:"
        };
        for (int i = 0; !failed && i < sizeof(stringDescName)/sizeof(stringDescName[0]); ++i) {
            failed |= readDescriptor(result, sim, DESC_STRING, i + 1, ep0MaxPacketSize, addr, 2);
            std::cout << "Read String Descriptor for the " << stringDescName[i] << std::endl;
            prettyPrintDescriptors(result);
            //TODO check content
        }
    }

    if (failed) {
        goto exitAndCleanup;
    }

    std::cout << std::endl << "Lets try reading the configuration descriptor!" << std::endl;

    // Read the default configuration
    failed |= readDescriptor(result, sim, DESC_CONFIGURATION, 0, ep0MaxPacketSize, addr, 9, getConfigurationDescriptorSize);

    std::cout << "Result size: " << result.size() << std::endl;

    prettyPrintDescriptors(result);
    //TODO check content

    if (failed) {
        goto exitAndCleanup;
    }

    // set address to 42
    std::cout << "Setting device address to 42!" << std::endl;
    failed |= sendValueSetRequest(sim, DEVICE_SET_ADDRESS, 42, ep0MaxPacketSize, 0, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    addr = 42;

    // set configuration value to 1
    std::cout << std::endl << "Selecting device configuration 1 (with wrong addr -> should fail)!" << std::endl;
    // This is expected to fail!
    failed |= !sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr + 1, 0);

    if (failed) {
        goto exitAndCleanup;
    }

    std::cout << std::endl << "Selecting device configuration 1 (correct addr)!" << std::endl;
    failed = sendValueSetRequest(sim, DEVICE_SET_CONFIGURATION, 1, ep0MaxPacketSize, addr, 0);

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