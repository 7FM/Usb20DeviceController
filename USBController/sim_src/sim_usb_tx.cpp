#include <algorithm>
#include <bitset>
#include <cstdint>
#include <getopt.h>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

#define TOP_MODULE Vsim_usb_tx
#include "Vsim_usb_tx.h"       // basic Top header
#include "Vsim_usb_tx__Syms.h" // all headers to access exposed internal signals

#include "common/usb_utils.hpp" // Utils to create & read a usb packet

#ifndef PHASE_LENGTH
#define PHASE_LENGTH 5
#endif

static TOP_MODULE *ptop = nullptr; // Instantiation of module
static VerilatedVcdC *tfp = nullptr;

static vluint64_t main_time = 0; // Current simulation time

static bool stopCondition();

static void sanityChecks();
static void onRisingEdge();
static void onFallingEdge();

/**
* Called by $time in Verilog
****************************************************************************/
double sc_time_stamp() {
    return main_time; // converts to double, to match what SystemC does
}

/******************************************************************************/
static void tick(int count, bool dump) {
    do {
        //if (tfp)
        //tfp->dump(main_time); // dump traces (inputs stable before outputs change)
        ptop->eval(); // Evaluate model
        main_time++;  // Time passes...
        if (tfp && dump)
            tfp->dump(main_time); // inputs and outputs all updated at same time
    } while (--count);
}

/******************************************************************************/

static void run(uint64_t limit, bool dump, bool checkStopCondition = true) {
    bool stop;
    do {
        stop = checkStopCondition && stopCondition();
        ptop->CLK = 1;
        onRisingEdge();
        tick(PHASE_LENGTH, dump);
        ptop->CLK = 0;
        onFallingEdge();
        tick(PHASE_LENGTH, dump);
        sanityChecks();
    } while (--limit && !stop);
}

/******************************************************************************/

// Usb data receive state variables
static UsbReceiveState rxState;
static UsbTransmitState txState;

static void sanityChecks() {
}

static bool stopCondition() {
    return rxState.receivedLastByte;
}

static void onRisingEdge() {
    receiveDeserializedInput(ptop, rxState);
    feedTransmitSerializer(ptop, txState);
}

static void onFallingEdge() {
}

static void reset() {
    // Data send/transmit interface
    ptop->txReqSendPacket = 0;
    ptop->txIsLastByte = 0;
    ptop->txDataValid = 0;
    ptop->txData = 0;
    // Data receive interface
    ptop->rxAcceptNewData = 0;

    ptop->rxRST = 1;
    // Give modules some time to settle
    int resetCycles = 10;
    do {
        ptop->CLK = 1;
        tick(PHASE_LENGTH, true);
        ptop->CLK = 0;
        tick(PHASE_LENGTH, true);
    } while (--resetCycles);
    ptop->rxRST = 0;

    rxState.reset();
    txState.reset();
}

/******************************************************************************/
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    ptop = new TOP_MODULE; // Create instance

    int verbose = 0;
    int start = 0;
    int testFailed = 0;

    int opt;

    while ((opt = getopt(argc, argv, ":s:t:v:")) != -1) {
        switch (opt) {
            case 'v':
                verbose = std::atoi(optarg);
                break;
            case 't':
                // init trace dump
                Verilated::traceEverOn(true);
                tfp = new VerilatedVcdC;
                ptop->trace(tfp, 99);
                tfp->open(optarg);
                break;
            case 's':
                start = std::atoi(optarg);
                break;
            case ':':
                std::cout << "option needs a value" << std::endl;
                goto exitAndCleanup;
                break;
            case '?': //used for some unknown options
                std::cout << "unknown option: " << optopt << std::endl;
                goto exitAndCleanup;
                break;
        }
    }

    // start things going
    for (int it = 0; true; ++it) {
        reset();

        //TODO test different packet types!

        switch (it) {

            case 0: {
                txState.dataToSend.push_back(PID_DATA0);
                // Single byte packet that triggers the CRC bitstuffing at end edge case!
                txState.dataToSend.push_back(static_cast<uint8_t>(0xF9));
                std::cout << "Expected packet size: " << txState.dataToSend.size() << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0xF9)>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 1: {
                txState.dataToSend.push_back(PID_DATA0);
                // Two byte packet that triggers the CRC bitstuffing at end edge case!
                txState.dataToSend.push_back(static_cast<uint8_t>(0xFF));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xFA));
                std::cout << "Expected packet size: " << txState.dataToSend.size() << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0xFF), static_cast<uint8_t>(0xFA)>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 2: {
                txState.dataToSend.push_back(PID_DATA0);
                // Another edge case: empty data packet!
                std::cout << "Expected packet size: " << txState.dataToSend.size() << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<>(CRC_Type::CRC16)) << std::endl;
                break;
            }

            case 3: {
                txState.dataToSend.push_back(PID_DATA0);
                txState.dataToSend.push_back(static_cast<uint8_t>(0x11));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x22));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x33));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x44));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x55));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x66));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x77));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x88));
                txState.dataToSend.push_back(static_cast<uint8_t>(0x99));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xAA));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xBB));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xCC));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xDD));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xDE));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xAD));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xBE));
                txState.dataToSend.push_back(static_cast<uint8_t>(0xEF));
                // Ensure that at least one bit stuffing is required!
                txState.dataToSend.push_back(static_cast<uint8_t>(0xFF));

                std::cout << "Expected packet size: " << txState.dataToSend.size() << std::endl;
                std::cout << "Expected CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0x11), static_cast<uint8_t>(0x22), static_cast<uint8_t>(0x33), static_cast<uint8_t>(0x44), static_cast<uint8_t>(0x55), static_cast<uint8_t>(0x66), static_cast<uint8_t>(0x77), static_cast<uint8_t>(0x88), static_cast<uint8_t>(0x99), static_cast<uint8_t>(0xAA), static_cast<uint8_t>(0xBB), static_cast<uint8_t>(0xCC), static_cast<uint8_t>(0xDD), static_cast<uint8_t>(0xDE), static_cast<uint8_t>(0xAD), static_cast<uint8_t>(0xBE), static_cast<uint8_t>(0xEF), static_cast<uint8_t>(0xFF)>(CRC16))
                          << std::endl;
                break;
            }

            default: {
                std::cout << "No more test packets left" << std::endl;
                goto exitAndCleanup;
            }
        }

        if (start) {
            run(start, false);
        }
        // Execute till stop condition
        run(0, true);
        // Execute a few more cycles
        run(4 * 10, true, false);

        // First compare amount of data
        if (txState.dataToSend.size() != rxState.receivedData.size()) {
            std::cerr << "Send and received byte count differs!\n    Expected: " << txState.dataToSend.size() << " got: " << rxState.receivedData.size() << std::endl;
            testFailed = 1;
        }

        // Then compare the data itself
        size_t compareSize = std::min(txState.dataToSend.size(), rxState.receivedData.size());
        for (size_t i = 0; i < compareSize; ++i) {
            if (txState.dataToSend[i] != rxState.receivedData[i]) {
                std::cerr << "Send and received byte " << i << "differ!\n    Expected: 0x" << std::hex << static_cast<int>(txState.dataToSend[i]) << " got: 0x" << std::hex << static_cast<int>(rxState.receivedData[i]) << std::endl;
                testFailed = 1;
            }
        }

        // Finally check that the packet should be kept!
        if (!rxState.keepPacket) {
            std::cerr << "Packet transmission failed, likely CRC calculation or transmission failed!" << std::endl;
            testFailed = 1;
        }
    }

exitAndCleanup:

    std::cout << std::endl
              << "Tests ";
    if (testFailed) {
        std::cout << "FAILED!" << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    if (tfp)
        tfp->close();

    ptop->final(); // Done simulating

    if (tfp)
        delete tfp;

    delete ptop;

    return testFailed;
}