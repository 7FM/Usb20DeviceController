#include <cstdint>
#include <getopt.h>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

#define TOP_MODULE Vsim_usb_rx
#include "Vsim_usb_rx.h"       // basic Top header
#include "Vsim_usb_rx__Syms.h" // all headers to access exposed internal signals

#include "common/usb_utils.hpp" // Utils to create & read a usb packet

#ifndef PHASE_LENGTH
#define PHASE_LENGTH 5
#endif
#ifndef USB_SIGNAL_LENGTH
#define USB_SIGNAL_LENGTH 4
#endif

#define APPLY_USB_SIGNAL_ON_RISING_EDGE 0

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

static void sanityChecks() {
}

/******************************************************************************/

static constexpr auto signalToReceive = constructSignal(usbSyncSignal, nrziEncode<true, PID_DATA0, static_cast<uint8_t>(0xDE), static_cast<uint8_t>(0xAD), static_cast<uint8_t>(0xBE), static_cast<uint8_t>(0xEF)>(), usbEOPSignal);

static int signalIdx;
static uint8_t delayCnt;

static void applyUsbSignal(const uint8_t *data, std::size_t arraySize) {
    if (signalIdx + 1 < arraySize) {
        delayCnt = (delayCnt + 1) % USB_SIGNAL_LENGTH;
        if (delayCnt == 0) {
            ptop->USB_DP = data[signalIdx++];
            ptop->USB_DN = data[signalIdx++];
        }
    }
}

// Usb data receive state variables
static UsbReceiveState rxState;

/******************************************************************************/

static bool stopCondition() {
    return signalIdx >= signalToReceive.size() && rxState.receivedLastByte;
}

static void onRisingEdge() {
    receiveDeserializedInput(ptop, rxState);
#if APPLY_USB_SIGNAL_ON_RISING_EDGE
    applyUsbSignal(signalToReceive.data(), signalToReceive.size());
#endif
}

static void onFallingEdge() {
#if !APPLY_USB_SIGNAL_ON_RISING_EDGE
    applyUsbSignal(signalToReceive.data(), signalToReceive.size());
#endif
}

/******************************************************************************/
static void reset() {
    // Set inputs to valid states
    ptop->USB_DP = 1;
    ptop->USB_DN = 0;

    ptop->rxRST = 0;
    ptop->rxAcceptNewData = 0;

    // Simulation state
    signalIdx = 0;
    // Here we could test different signal start offsets!
    delayCnt = 0;
}

/******************************************************************************/
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    ptop = new TOP_MODULE; // Create instance

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
                goto exitAndCleanup;
                break;
            case '?': //used for some unknown options
                std::cout << "unknown option: " << optopt << std::endl;
                goto exitAndCleanup;
                break;
        }
    }

    // start things going
    reset();

    if (start) {
        run(start, false);
    }
    // Execute till stop condition
    run(0, true);
    // Execute a few more cycles
    run(4 * 10, true, false);

    std::cout << "Received Data:" << std::endl;
    for (uint8_t data : rxState.receivedData) {
        std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
    }

exitAndCleanup:

    if (tfp)
        tfp->close();

    ptop->final(); // Done simulating

    if (tfp)
        delete tfp;

    delete ptop;


    return 0;
}