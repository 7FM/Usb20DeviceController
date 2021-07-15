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
    virtual bool stopCondition(TOP_MODULE *top) override {
        //TODO change to something useful!
        return forceStop;
    }
};

/******************************************************************************/
int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbTopSim sim;
    sim.init(argc, argv);

    // start things going
    sim.reset();

    // Execute till stop condition
    while (!sim.run<true>(0));
    // Execute a few more cycles
    sim.run<true, false>(4 * 10);

    return 0;
}