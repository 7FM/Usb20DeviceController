#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <functional>

#define TOP_MODULE Vsim_top
#include "Vsim_top.h"       // basic Top header
#include "Vsim_top__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class UsbTopSim : public VerilatorTB<UsbTopSim, TOP_MODULE> {

  public:
    void simReset() {
        // Data send/transmit interface
        top->txReqSendPacket = 0;
        top->txIsLastByte = 0;
        top->txDataValid = 0;
        top->txData = 0;
        // Data receive interface
        top->rxAcceptNewData = 0;

        top->rxRST = 1;
        // Give modules some time to settle
        constexpr int resetCycles = 10;
        run<false, false, false, false, false>(resetCycles);
        top->rxRST = 0;

        rxState.reset();
        txState.reset();
    }

    bool stopCondition() {
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop;
    }

    void onRisingEdge() {
        receiveDeserializedInput(top, rxState);
        feedTransmitSerializer(top, txState);
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

static void printResponse(const std::vector<uint8_t>& response) {
    if (response.empty()) {
        std::cerr << "No response received!" << std::endl;
        return;
    }

    std::cout << "Got Response:" << std::endl;
    bool first = true;
    for (auto data : response) {
        if (first) {
            std::cout << "    " << pidToString(static_cast<PID_Types>(data)) << std::endl;
        } else {
            std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
        }
        first = false;
    }
}

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbTopSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    bool failed = false;

    // Test 1: Setup transaction: request the device descriptor
    OutTransaction setupTrans;
    setupTrans.outTokenPacket.token = PID_SETUP_TOKEN;
    setupTrans.outTokenPacket.addr = 0;
    setupTrans.outTokenPacket.endpoint = 0;
    setupTrans.outTokenPacket.crc = 0b11111; // Should be a dont care!

    SetupPacket packet;
    std::memset(&packet, 0, sizeof(packet));
    // Request type
    packet.request = DEVICE_GET_DESCRIPTOR;

    // Descriptor type
    packet.wValueMsB = DESC_DEVICE;
    // Descriptor index;
    packet.wValueLsB = 0;
    // Zero or Language ID
    packet.wIndexLsB = packet.wIndexMsB = 0;
    // Descriptor length, is unknown but can be determined by reading the first 8 bytes
    packet.wLengthLsB = 8;
    packet.wLengthMsB = 0;

    setupTrans.dataPacket.push_back(PID_DATA0);
    fillVector(setupTrans.dataPacket, packet);

    std::cout << "Send Setup transaction packet" << std::endl;
    failed |= setupTrans.send(sim);
    printResponse(sim.rxState.receivedData);
    //TODO check results

    sim.reset();

    InTransaction getDesc;
    getDesc.inTokenPacket.token = PID_IN_TOKEN;
    getDesc.inTokenPacket.addr = 0;
    getDesc.inTokenPacket.endpoint = 0;
    getDesc.inTokenPacket.crc = 0b11111; // Should be a dont care!
    getDesc.handshakeToken = PID_HANDSHAKE_ACK;

    std::cout << "Send Input transaction packet" << std::endl;
    failed |= getDesc.send(sim);
    printResponse(sim.rxState.receivedData);
    //TODO check results

    sim.reset();


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