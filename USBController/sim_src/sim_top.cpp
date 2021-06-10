#include <getopt.h>
#include <unistd.h>

#include <chrono>
#include <cmath>
#include <csignal>
#include <cstdlib>
#include <ctype.h>
#include <exception>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream> // Need std::cout
#include <string>
#include <thread>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

#include "Vsim_top.h"       // basic Top header
#include "Vsim_top__Syms.h" // all headers to access exposed internal signals

#ifndef PERIOD
#define PERIOD 5
#endif

static Vsim_top *ptop = nullptr; // Instantiation of module
static VerilatedVcdC *tfp = nullptr;

static vluint64_t main_time = 0; // Current simulation time

static void sanityChecks();

/**
* Called by $time in Verilog
****************************************************************************/
double sc_time_stamp() {
    return main_time; // converts to double, to match
                      // what SystemC does
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
    do {
        ptop->CLK = 1;
        tick(PERIOD, dump);
        ptop->CLK = 0;
        tick(PERIOD, dump);
        sanityChecks();
    } while (--limit);
}

/******************************************************************************/
static void reset() {
    // this module has nothing to reset
}

/******************************************************************************/

static void sanityChecks() {

}

/******************************************************************************/
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    ptop = new Vsim_top; // Create instance

    int verbose = 0;

    // Skip all visible lines except the last
    int start = 800 * 479;

    int opt;
    while ((opt = getopt(argc, argv, ":s:tv:")) != -1) {
        switch (opt) {
            case 'v':
                verbose = std::atoi(optarg);
                break;
            case 't':
                // init trace dump
                Verilated::traceEverOn(true);
                tfp = new VerilatedVcdC;
                ptop->trace(tfp, 99);
                tfp->open("wave.vcd");
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