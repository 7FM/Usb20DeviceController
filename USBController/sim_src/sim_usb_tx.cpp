#include <cstdint>
#include <getopt.h>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

#include "Vsim_usb_tx.h"       // basic Top header
#include "Vsim_usb_tx__Syms.h" // all headers to access exposed internal signals

#include "common/usb_utils.hpp" // Utils to create & read a usb packet

#ifndef PHASE_LENGTH
#define PHASE_LENGTH 5
#endif

static Vsim_usb_tx *ptop = nullptr; // Instantiation of module
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
static void reset() {
    // Data send/transmit interface
    ptop->reqSendPacket = 0;
    ptop->txIsLastByte = 0;
    ptop->txDataValid = 0;
    ptop->txData = 0;
    // Data receive interface
    ptop->rxAcceptNewData = 0;
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

/******************************************************************************/
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    ptop = new Vsim_usb_tx; // Create instance

    int verbose = 0;
    int start = 0;

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
                break;
            case '?': //used for some unknown options
                std::cout << "unknown option: " << optopt << std::endl;
                break;
        }
    }

    // start things going
    reset();

    txState.dataToSend.push_back(PID_DATA0);
    txState.dataToSend.push_back(static_cast<uint8_t>(0xDE));
    txState.dataToSend.push_back(static_cast<uint8_t>(0xAD));
    txState.dataToSend.push_back(static_cast<uint8_t>(0xBE));
    txState.dataToSend.push_back(static_cast<uint8_t>(0xEF));
    // Ensure that at least one bit stuffing is required!
    txState.dataToSend.push_back(static_cast<uint8_t>(0xFF));

    if (start) {
        run(start, false);
    }
    // Execute till stop condition
    //run(0, true);
    //TODO no data is retrieved! Find out WHY
    //TODO no data is retrieved! Find out WHY
    //TODO no data is retrieved! Find out WHY
    //TODO no data is retrieved! Find out WHY
    // Upper bound: 2000 Cycles
    run(2000, true);
    //TODO no data is retrieved! Find out WHY
    //TODO no data is retrieved! Find out WHY
    //TODO no data is retrieved! Find out WHY
    // Execute a few more cycles
    run(4 * 10, true, false);

    if (tfp)
        tfp->close();

    ptop->final(); // Done simulating

    if (tfp)
        delete tfp;

    delete ptop;

    std::cout << "Received Data:" << std::endl;
    for (uint8_t data : rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }

    return 0;
}