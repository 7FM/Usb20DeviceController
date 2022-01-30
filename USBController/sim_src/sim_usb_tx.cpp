#include <algorithm>
#include <atomic>
#include <bitset>
#include <csignal>
#include <cstdint>

#define TOP_MODULE Vsim_usb_tx
#include "Vsim_usb_tx.h"       // basic Top header
#include "Vsim_usb_tx__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/print_utils.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class UsbTxSim : public VerilatorTB<UsbTxSim, TOP_MODULE> {

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
        return rxState.receivedLastByte || forceStop;
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

    bool customInit(int opt) { return false; }
    void onFallingEdge() {}
    void sanityChecks() {}

  public:
    // Usb data receive state variables
    UsbReceiveState rxState;
    UsbTransmitState txState;

    uint8_t clk12Offset = 0;
};

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    int testFailed = 0;

    UsbTxSim sim;
    sim.init(argc, argv);

    for (sim.clk12Offset = 0; sim.clk12Offset < 4 && testFailed == 0 && !forceStop; ++sim.clk12Offset) {
        std::cout << "Use CLK12 offset of " << static_cast<int>(sim.clk12Offset) << std::endl << std::endl;

        // start things going
        for (int it = 0; !forceStop; ++it) {
            sim.reset();

            // TODO test different packet types!
            bool expectedKeepPacket = true;
            bool crc5Patching = false;

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
                    sim.txState.dataToSend.push_back(PID_HANDSHAKE_NAK);

                    std::cout << "Test handshake packet NAK" << std::endl;
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
                    tokenPacket.crc = 0b1'1111; // Should be a dont care!

                    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&tokenPacket);
                    for (int i = 0; i < sizeof(tokenPacket); ++i) {
                        sim.txState.dataToSend.push_back(*rawPtr);
                        ++rawPtr;
                    }

                    crc5Patching = true;

                    std::cout << "Test sending a setup token packet" << std::endl;

                    break;
                }

                case 11: {
                    TokenPacket tokenPacket;
                    tokenPacket.token = PID_SETUP_TOKEN;
                    tokenPacket.addr = 0b110'0000;
                    tokenPacket.endpoint = 0b1111;
                    tokenPacket.crc = 0b1'1111; // Should be a dont care!

                    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&tokenPacket);
                    for (int i = 0; i < sizeof(tokenPacket); ++i) {
                        sim.txState.dataToSend.push_back(*rawPtr);
                        ++rawPtr;
                    }

                    crc5Patching = true;

                    std::cout << "Test sending a setup token packet with bit stuffing right before the crc5" << std::endl;

                    break;
                }

                case 12: {
                    TokenPacket tokenPacket;
                    tokenPacket.token = PID_SETUP_TOKEN;
                    tokenPacket.addr = 0b111'0000;
                    tokenPacket.endpoint = 0b1111;
                    tokenPacket.crc = 0b1'1111; // Should be a dont care!

                    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&tokenPacket);
                    for (int i = 0; i < sizeof(tokenPacket); ++i) {
                        sim.txState.dataToSend.push_back(*rawPtr);
                        ++rawPtr;
                    }

                    crc5Patching = true;

                    std::cout << "Test sending a setup token packet with bit stuffing 1 bit before the crc5" << std::endl;

                    break;
                }

                case 13:
                /*
                case 14:
                case 15:
                case 16:
                case 17:
                case 18:
                case 19:
                case 20:
                case 21:
                case 22:
                case 23:
                case 24:
                case 25:
                case 26:
                case 27:
                case 28:
                case 29:
                case 30:
                case 31:
                case 32:
                case 33:
                case 34:
                case 35:
                case 36:
                case 37:
                case 38:
                case 39:
                case 40:*/ {
                    // Token packet with random addr & endpoint!
                    TokenPacket tokenPacket;
                    tokenPacket.token = PID_SETUP_TOKEN;
                    tokenPacket.addr = sim.getRand();
                    tokenPacket.endpoint = sim.getRand();
                    tokenPacket.crc = 0b1'1111; // Should be a dont care!

                    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&tokenPacket);
                    for (int i = 0; i < sizeof(tokenPacket); ++i) {
                        sim.txState.dataToSend.push_back(*rawPtr);
                        ++rawPtr;
                    }

                    crc5Patching = true;

                    std::cout << "Test sending a setup token packet with random addr & ep" << std::endl;

                    break;
                }

                default: {
                    std::cout << "No more test packets left" << std::endl;
                    goto exitInnerLoop;
                }
            }

            std::cout << "Expected packet size: " << sim.txState.dataToSend.size() << std::endl;

            // Execute till stop condition
            while (!sim.run<true>(0)) {
            }

            if (forceStop) {
                goto exitAndCleanup;
            }
            // Execute a few more cycles
            sim.run<true, false>(4 * 10);

            if (forceStop) {
                goto exitAndCleanup;
            }

            // If crc5 patching is enabled then 5 Msb of the last byte will be patched to include the specified crc5
            // Else the byte wise comparison between sent & received data will fail!
            if (crc5Patching) {
                // First calculate the desired crc5 value
                std::vector<uint8_t> tmpVec;
                for (int i = 1; i < sim.txState.dataToSend.size(); ++i) {
                    tmpVec.push_back(sim.txState.dataToSend[i]);
                }
                uint8_t crc5 = calculateDataCRC(CRC_Type::CRC5, tmpVec, tmpVec.size());
                std::cout << "Expected CRC: " << std::bitset<5>(crc5) << std::endl;

                uint8_t lastByte = sim.txState.dataToSend[sim.txState.dataToSend.size() - 1];
                lastByte = (lastByte & 0x07) | (crc5 << 3);
                sim.txState.dataToSend[sim.txState.dataToSend.size() - 1] = lastByte;
            }

            // First compare amount of data
            if (sim.txState.dataToSend.size() != sim.rxState.receivedData.size()) {
                IosFlagSaver flagSaver(std::cerr);
                std::cerr << "Send and received byte count differs!\n    Expected: " << sim.txState.dataToSend.size() << " got: " << sim.rxState.receivedData.size() << std::endl;
                std::cerr << "        Send Data: ";
                for (size_t i = 0; i < sim.txState.dataToSend.size(); ++i) {
                    std::cerr << "0x" << std::hex << static_cast<int>(sim.txState.dataToSend[i]) << ' ';
                }
                std::cerr << std::endl;
                std::cerr << "    Received Data: ";
                for (size_t i = 0; i < sim.rxState.receivedData.size(); ++i) {
                    std::cerr << "0x" << std::hex << static_cast<int>(sim.rxState.receivedData[i]) << ' ';
                }
                std::cerr << std::endl;
                ++testFailed;
            }

            // Then compare the data itself
            size_t compareSize = std::min(sim.txState.dataToSend.size(), sim.rxState.receivedData.size());
            for (size_t i = 0; i < compareSize; ++i) {
                if (sim.txState.dataToSend[i] != sim.rxState.receivedData[i]) {
                    IosFlagSaver flagSaver(std::cerr);
                    std::cerr << "Send and received byte at idx " << i << " differ!\n    Expected: 0x" << std::hex << static_cast<int>(sim.txState.dataToSend[i]) << " got: 0x" << std::hex << static_cast<int>(sim.rxState.receivedData[i]) << std::endl;
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
    exitInnerLoop:
        std::cout << "Tests ";
        if (testFailed != 0) {
            std::cout << "FAILED";
        } else {
            std::cout << "PASSED";
        }
        std::cout << " for CLK12 offset of " << static_cast<int>(sim.clk12Offset) << std::endl;
    }

exitAndCleanup:

    std::cout << std::endl
              << "Tests ";

    if (forceStop) {
        std::cout << "ABORTED!" << std::endl;
        std::cerr << "The user requested a forced stop!" << std::endl;
    } else if (testFailed) {
        std::cout << "FAILED! Seed: " << sim.getSeed() << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    return testFailed;
}