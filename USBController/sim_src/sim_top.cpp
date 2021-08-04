#include <atomic>
#include <csignal>
#include <cstdint>

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

class UsbTopSim : public VerilatorTB<TOP_MODULE> {
  public:
    virtual void simReset(TOP_MODULE *top) override {
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

    virtual bool stopCondition(TOP_MODULE *top) override {
        //TODO change to something useful!
        return txState.doneSending || rxState.receivedLastByte || rxState.timedOut || forceStop;
    }

    virtual void onRisingEdge(TOP_MODULE *top) override {
        receiveDeserializedInput(top, rxState);
        feedTransmitSerializer(top, txState);
    }

  public:
    // Usb data receive state variables
    UsbReceiveState rxState;
    UsbTransmitState txState;
};

class InTransaction {
  public:
    TokenPacket inTokenPacket;
    PID_Types handshakeToken;

    void send(UsbTopSim &sim) {
        std::cout << "Send IN token!" << std::endl;

        const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&inTokenPacket);
        for (int i = 0; i < sizeof(inTokenPacket); ++i) {
            sim.txState.dataToSend.push_back(*rawPtr);
            ++rawPtr;
        }

        // Execute till stop condition
        while (!sim.run<true>(0));

        std::cout << "Receive IN data!" << std::endl;
        // Enable timeout for receiving a response
        sim.rxState.enableTimeout = true;

        // Reset done sending flag
        assert(sim.txState.doneSending);
        sim.txState.dataToSend.clear();
        sim.txState.doneSending = false;

        // Execute till stop condition
        while (!sim.run<true>(0));

        std::cout << "Send handshake!" << std::endl;

        // Reset receive flag
        assert(sim.rxState.receivedLastByte);
        sim.rxState.receivedLastByte = false;

        sim.txState.reset();
        sim.txState.dataToSend.push_back(handshakeToken);
        // Execute till stop condition
        while (!sim.run<true>(0));

        assert(sim.txState.doneSending);
    }
};

class OutTransaction {
  public:
    TokenPacket outTokenPacket;
    std::vector<uint8_t> dataPacket;

    void send(UsbTopSim &sim) {
        std::cout << "Send OUT token!" << std::endl;

        const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&outTokenPacket);
        for (int i = 0; i < sizeof(outTokenPacket); ++i) {
            sim.txState.dataToSend.push_back(*rawPtr);
            ++rawPtr;
        }

        // Execute till stop condition
        while (!sim.run<true>(0));

        // Execute a few more cycles to give the logic some time between the packages
        sim.run<true, false>(10);

        std::cout << "Send OUT data!" << std::endl;

        // Reset done sending flag
        assert(sim.txState.doneSending);
        sim.txState.reset();

        for (uint8_t data : dataPacket) {
            sim.txState.dataToSend.push_back(data);
        }

        // Execute till stop condition
        while (!sim.run<true>(0));

        std::cout << "Wait for response!" << std::endl;
        // Enable timeout for receiving a response
        sim.rxState.enableTimeout = true;

        // Reset receive flag
        if (!sim.txState.doneSending) {
            return;
        }

        sim.txState.dataToSend.clear();
        sim.txState.doneSending = false;

        // Execute till stop condition
        while (!sim.run<true>(0));

        if (sim.rxState.timedOut) {
            std::cerr << "Timeout waiting for a response!" << std::endl;
            return;
        }
        assert(sim.rxState.receivedLastByte);
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
    const uint8_t *rawPtr = reinterpret_cast<const uint8_t*>(&packet);
    for (int i = 0; i < sizeof(SetupPacket); ++i) {
        setupTrans.dataPacket.push_back(*rawPtr);
        ++rawPtr;
    }

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

    setupTrans.send(sim);
    std::cout << "Got Response:" << std::endl;
    for (auto data : sim.rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }
    //TODO check results
    sim.reset();

    return 0;
}