#include <getopt.h>
#include <unistd.h>

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdlib>
#include <ctype.h>
#include <exception>
#include <fstream>
#include <functional>
#include <initializer_list>
#include <iomanip>
#include <iostream> // Need std::cout
#include <string>
#include <thread>
#include <tuple>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

#include "Vsim_usb_rx.h"       // basic Top header
#include "Vsim_usb_rx__Syms.h" // all headers to access exposed internal signals

#ifndef PHASE_LENGTH
#define PHASE_LENGTH 5
#endif
#ifndef USB_SIGNAL_LENGTH
#define USB_SIGNAL_LENGTH 4
#endif

#define BIT_STUFF_AFTER_X_ONES 6
#define APPLY_USB_SIGNAL_ON_RISING_EDGE 0

static Vsim_usb_rx *ptop = nullptr; // Instantiation of module
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

static void run(uint64_t limit, bool dump = true) {
    bool stop;
    do {
        stop = stopCondition();
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

template <std::size_t N>
struct USBSignal {
    constexpr USBSignal() : dp(), dn() {}

    static constexpr std::size_t size = N;
    uint8_t dp[N];
    uint8_t dn[N];
};

static constexpr bool needsBitStuffing(uint8_t &oneCounter, uint8_t dataBit) {
    if (dataBit == 1) {
        ++oneCounter;
        if (oneCounter >= BIT_STUFF_AFTER_X_ONES) {
            oneCounter = 0;
            return true;
        }
    } else {
        oneCounter = 0;
    }
    return false;
}

template <uint8_t... dataBytes>
static constexpr int requiredBitStuffings() {
    int requiredBitStuffing = 0;
    uint8_t ones = 0;

    for (uint8_t data : {dataBytes...}) {
        for (int i = 0; i < sizeof(data) * 8; ++i) {

            if (needsBitStuffing(ones, data & 1)) {
                ++requiredBitStuffing;
            }

            // Next data bit
            data >>= 1;
        }
    }

    return requiredBitStuffing;
}

static constexpr void applyNrziEncode(uint8_t &nrziEncoderState, uint8_t dataBit, uint8_t *dp, uint8_t *dn) {
    // XNOR first bit
    nrziEncoderState = 1 ^ (nrziEncoderState ^ dataBit);

    *dp = nrziEncoderState;
    *dn = 1 ^ nrziEncoderState;
}

// Source: https://stackoverflow.com/questions/5438671/static-assert-on-initializer-listsize
template <uint8_t... dataBytes>
static constexpr auto nrziEncode(uint8_t initialOneCount = 1, uint8_t encoderStartState = 0) {

    // Set size to upper bound -> #bits + #bits/6 to account for bitstuffing too
    USBSignal<sizeof...(dataBytes) * sizeof(uint8_t) * 8 + requiredBitStuffings<dataBytes...>()> signal;
    int signalIdx = 0;

    int requiredBitStuffings = 0;
    uint8_t bitStuffingOneCounter = initialOneCount;
    uint8_t nrziEncoderState = encoderStartState;

    for (uint8_t data : {dataBytes...}) {
        for (int i = 0; i < sizeof(data) * 8; ++i, ++signalIdx) {

            uint8_t dataBit = data & 1;
            // Next data bit
            data >>= 1;

            applyNrziEncode(nrziEncoderState, dataBit, signal.dp + signalIdx, signal.dn + signalIdx);

            if (needsBitStuffing(bitStuffingOneCounter, dataBit)) {
                // If the allowed amount of consecutive one's are exceeded a 0 needs to be stuffed into the signal!
                ++signalIdx;
                applyNrziEncode(nrziEncoderState, 0, signal.dp + signalIdx, signal.dn + signalIdx);
            }
        }
    }

    return signal;
}

template <class... SignalPart>
static constexpr int determineSignalLength(const SignalPart &...signalParts) {
    return (0 + ... + signalParts.size);
}

template <class SignalPart, std::size_t N>
static constexpr void constructSignalHelper(const SignalPart &signalPart, int &idx, std::array<uint8_t, N> &storage) {
    for (int j = 0; j < signalPart.size; ++j) {
        storage[idx++] = signalPart.dp[j];
        storage[idx++] = signalPart.dn[j];
    }
}

template <class... SignalPart>
static constexpr auto constructSignal(const SignalPart &...signalParts) {
    std::array<uint8_t, determineSignalLength(signalParts...) * 2> signal{};

    int i = 0;
    (constructSignalHelper(signalParts, i, signal), ...);

    return signal;
}

static constexpr auto createEOPSignal() {
    USBSignal<3> signal;

    signal.dp[0] = signal.dn[0] = signal.dp[1] = signal.dn[1] = 0;
    signal.dp[2] = 1;
    signal.dn[2] = 0;

    return signal;
}

static constexpr auto usbSyncSignal = nrziEncode<static_cast<uint8_t>(0b1000'0000)>(0, 1);
static constexpr auto usbEOPSignal = createEOPSignal();

static constexpr auto signalToReceive = constructSignal(usbSyncSignal, nrziEncode<static_cast<uint8_t>(0b1000'0111), static_cast<uint8_t>(0xDE), static_cast<uint8_t>(0xAD), static_cast<uint8_t>(0xBE), static_cast<uint8_t>(0xEF)>(), usbEOPSignal);

int signalIdx;
uint8_t delayCnt;

static void applyUsbSignal(const uint8_t *data, std::size_t arraySize) {
    if (signalIdx + 1 < arraySize) {
        delayCnt = (delayCnt + 1) % USB_SIGNAL_LENGTH;
        if (delayCnt == 0) {
            ptop->USB_DP = data[signalIdx++];
            ptop->USB_DN = data[signalIdx++];
        }
    }
}

/******************************************************************************/

static bool stopCondition() {
    return signalIdx >= signalToReceive.size() && ptop->rxIsLastByte;
}

static void onRisingEdge() {
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
    ptop->outEN_reg = 0;
    ptop->ACK_USB_RST = 0;
    //TODO create handshake stuff
    ptop->rxAcceptNewData = 0;

    // Simulation state
    signalIdx = 0;
    // Here we could test different signal start offsets!
    delayCnt = 0;
}

/******************************************************************************/
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    ptop = new Vsim_usb_rx; // Create instance

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
                printf("option needs a value\n");
                break;
            case '?': //used for some unknown options
                printf("unknown option: %c\n", optopt);
                break;
        }
    }

    // start things going
    reset();

    if (start) {
        run(start, false);
    }
    // Only dump transistion lines to new frame
    run(800 * (525 + 1 - 479), true);

    if (tfp)
        tfp->close();

    ptop->final(); // Done simulating

    if (tfp)
        delete tfp;

    delete ptop;

    return 0;
}