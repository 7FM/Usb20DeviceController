#include <atomic>
#include <csignal>
#include <cstdint>
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

    void send(UsbTopSim &sim) {
        //=========================================================================
        // 1. Send Token packet
        std::cout << "Send IN token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, inTokenPacket);
        })) return;

        //=========================================================================
        // 2. Receive Data packet / Timeout

        std::cout << "Receive IN data!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for input data!"))
            return;

        //=========================================================================
        // 3. (Send Handshake)

        std::cout << "Send handshake!" << std::endl;

        if(sendStuff(sim, [&]{
            sim.txState.dataToSend.push_back(handshakeToken);
        })) return;
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

    void send(UsbTopSim &sim) {
        //=========================================================================
        // 1. Send Token packet

        std::cout << "Send OUT token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, outTokenPacket);
        })) return;

        // Execute a few more cycles to give the logic some time between the packages
        sim.run<true, false>(10);

        //=========================================================================
        // 2. Send Data packet
        std::cout << "Send OUT data!" << std::endl;

        if(sendStuff(sim, [&]{
            for (uint8_t data : dataPacket) {
                sim.txState.dataToSend.push_back(data);
            }
        })) return;

        //=========================================================================
        // 3. Receive Handshake / Timeout

        std::cout << "Wait for response!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for a response!"))
            return;
    }
};

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbTopSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    // Test 1: Setup transaction
    OutTransaction setupTrans;
    setupTrans.outTokenPacket.token = PID_SETUP_TOKEN;
    setupTrans.outTokenPacket.addr = 0;
    setupTrans.outTokenPacket.endpoint = 0;
    setupTrans.outTokenPacket.crc = 0b11111; // Should be a dont care!

    SetupPacket packet; //TODO fill
    setupTrans.dataPacket.push_back(PID_DATA0);
    fillVector(setupTrans.dataPacket, packet);

    std::cout << "Send Setup transaction packet" << std::endl;
    setupTrans.send(sim);
    std::cout << "Got Response:" << std::endl;
    for (auto data : sim.rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }
    //TODO check results

    sim.reset();

    InTransaction getDesc;
    getDesc.inTokenPacket.token = PID_IN_TOKEN;
    getDesc.inTokenPacket.addr = 0;
    getDesc.inTokenPacket.endpoint = 0;
    getDesc.inTokenPacket.crc = 0b11111; // Should be a dont care!
    getDesc.handshakeToken = PID_HANDSHAKE_ACK;

    std::cout << "Send Input transaction packet" << std::endl;
    getDesc.send(sim);
    std::cout << "Got Response:" << std::endl;
    for (auto data : sim.rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }
    //TODO check results

    sim.reset();

    return 0;
}