#include <algorithm>
#include <atomic>
#include <bitset>
#include <csignal>
#include <cstdint>

#define TOP_MODULE Vsim_usb_tx
#include "Vsim_usb_tx.h"       // basic Top header
#include "Vsim_usb_tx__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class UsbTxSim : public VerilatorTB<TOP_MODULE> {
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
        return rxState.receivedLastByte || forceStop;
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

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    int testFailed = 0;

    UsbTxSim sim;
    sim.init(argc, argv);

    // start things going
    for (int it = 0; !forceStop; ++it) {
        sim.reset();

        //TODO test different packet types!
        bool expectedKeepPacket = true;

        switch (it) {

            case 0: {
                sim.txState.dataToSend.push_back(PID_DATA0);
                // Single byte packet that triggers the CRC bitstuffing at end edge case!
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xF9));
                std::cout << "Test single data byte CRC16 bitstuffing edge case:" << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0xF9)>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 1: {
                sim.txState.dataToSend.push_back(PID_DATA0);
                // Two byte packet that triggers the CRC bitstuffing at end edge case!
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xFF));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xFA));
                std::cout << "Test 2 data bytes CRC16 bitstuffing edge case:" << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0xFF), static_cast<uint8_t>(0xFA)>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 2: {
                sim.txState.dataToSend.push_back(PID_DATA0);
                // Another edge case: empty data packet!
                std::cout << "Test 0 data bytes packet edge case:" << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 3: {
                sim.txState.dataToSend.push_back(PID_DATA0);
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x11));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x22));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x33));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x44));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x55));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x66));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x77));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x88));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0x99));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xAA));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xBB));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xCC));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xDD));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xDE));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xAD));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xBE));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xEF));
                // Ensure that at least one bit stuffing is required!
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xFF));

                std::cout << "Test \"normal\" data packet:" << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0x11), static_cast<uint8_t>(0x22), static_cast<uint8_t>(0x33), static_cast<uint8_t>(0x44), static_cast<uint8_t>(0x55), static_cast<uint8_t>(0x66), static_cast<uint8_t>(0x77), static_cast<uint8_t>(0x88), static_cast<uint8_t>(0x99), static_cast<uint8_t>(0xAA), static_cast<uint8_t>(0xBB), static_cast<uint8_t>(0xCC), static_cast<uint8_t>(0xDD), static_cast<uint8_t>(0xDE), static_cast<uint8_t>(0xAD), static_cast<uint8_t>(0xBE), static_cast<uint8_t>(0xEF), static_cast<uint8_t>(0xFF)>(CRC16))
                          << std::endl;
                break;
            }

            case 4: {
                sim.txState.dataToSend.push_back(PID_DATA0 ^ 0x80);
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xDE));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xAD));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xBE));
                sim.txState.dataToSend.push_back(static_cast<uint8_t>(0xEF));

                std::cout << "Test data packet with invalid PID \"checksum\" -> we expect keepPacket = 0" << std::endl;
                expectedKeepPacket = false;
                break;
            }

            case 5: {
                sim.txState.dataToSend.push_back(PID_HANDSHAKE_ACK);

                std::cout << "Test handshake packet ACK" << std::endl;
                break;
            }

            case 6: {
                sim.txState.dataToSend.push_back(PID_HANDSHAKE_NACK);

                std::cout << "Test handshake packet NACK" << std::endl;
                break;
            }

            case 7: {
                sim.txState.dataToSend.push_back(PID_HANDSHAKE_STALL);

                std::cout << "Test handshake packet STALL" << std::endl;
                break;
            }

            case 8: {
                sim.txState.dataToSend.push_back(PID_HANDSHAKE_NYET);

                std::cout << "Test handshake packet NYET" << std::endl;
                break;
            }

            case 9: {
                sim.txState.dataToSend.push_back(PID_DATA0 ^ 0x01);

                std::cout << "Test handshake packet with invalid PID \"checksum\" -> we expect keepPacket = 0" << std::endl;
                expectedKeepPacket = false;
                break;
            }

            case 10: {
                TokenPacket tokenPacket;
                tokenPacket.token = PID_SETUP_TOKEN;
                tokenPacket.addr = 0;
                tokenPacket.endpoint = 0;
                //TODO this breaks later comparison & should be patched or ignored!
                tokenPacket.crc = 0b11111; // Should be a dont care!

                const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&tokenPacket);
                for (int i = 0; i < sizeof(tokenPacket); ++i) {
                    sim.txState.dataToSend.push_back(*rawPtr);
                    ++rawPtr;
                }

                std::cout << "Test sending a setup token packet" << std::endl;

                break;
            }

            default: {
                std::cout << "No more test packets left" << std::endl;
                goto exitAndCleanup;
            }
        }

        std::cout << "Expected packet size: " << sim.txState.dataToSend.size() << std::endl;

        // Execute till stop condition
        while (!sim.run<true>(0));

        if (forceStop) {
            goto exitAndCleanup;
        }
        // Execute a few more cycles
        sim.run<true, false>(4 * 10);

        if (forceStop) {
            goto exitAndCleanup;
        }

        // First compare amount of data
        if (sim.txState.dataToSend.size() != sim.rxState.receivedData.size()) {
            std::cerr << "Send and received byte count differs!\n    Expected: " << sim.txState.dataToSend.size() << " got: " << sim.rxState.receivedData.size() << std::endl;
            ++testFailed;
        }

        // Then compare the data itself
        size_t compareSize = std::min(sim.txState.dataToSend.size(), sim.rxState.receivedData.size());
        for (size_t i = 0; i < compareSize; ++i) {
            if (sim.txState.dataToSend[i] != sim.rxState.receivedData[i]) {
                std::cerr << "Send and received byte " << i << " differ!\n    Expected: 0x" << std::hex << static_cast<int>(sim.txState.dataToSend[i]) << " got: 0x" << std::hex << static_cast<int>(sim.rxState.receivedData[i]) << std::endl;
                ++testFailed;
            }
        }

        // Finally check that the packet should be kept!
        if (expectedKeepPacket != sim.rxState.keepPacket) {
            std::cerr << "Keep packet has an unexpected value! Expected: " << expectedKeepPacket << " got: " << sim.rxState.keepPacket << std::endl;
            ++testFailed;
        }

        std::cout << std::endl;
    }

exitAndCleanup:

    std::cout << std::endl
              << "Tests ";

    if (forceStop) {
        std::cout << "ABORTED!" << std::endl;
        std::cerr << "The user requested a forced stop!" << std::endl;
    } else if (testFailed) {
        std::cout << "FAILED!" << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    return testFailed;
}