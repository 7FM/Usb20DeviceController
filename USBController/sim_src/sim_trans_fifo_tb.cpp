#include <atomic>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <functional>

#define TOP_MODULE Vsim_trans_fifo_tb
#include "Vsim_trans_fifo_tb.h"       // basic Top header
#include "Vsim_trans_fifo_tb__Syms.h" // all headers to access exposed internal signals

#include "common/VerilatorTB.hpp"
#include "common/print_utils.hpp"
#include "common/usb_descriptors.hpp"
#include "common/usb_packets.hpp"
#include "common/usb_utils.hpp" // Utils to create & read a usb packet

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class FIFOPusher {
  public:
    int pushed;

  private:
    bool enabled = false;

  public:
    void reset(TOP_MODULE *top) {
        pushed = 0;

        // Data send/transmit interface
        top->fillTransDone_i = 0;
        top->fillTransSuccess_i = 0;
        top->dataValid_i = 0;
        top->data_i = 0;

        clearCommit(top);
    }

    void enable() {
        enabled = true;
    }
    void disable() {
        enabled = false;
    }
    bool isEnabled() const {
        return enabled;
    }

    void fillFIFO(TOP_MODULE *top, bool posedge, bool negedge) {
        if (!enabled) {
            return;
        }
        if (negedge) {
            top->dataValid_i = enabled;
            top->data_i = pushed;
            return;
        }

        bool pushHandshake = top->dataValid_i && !top->full_o;

        if (pushHandshake) {
            ++pushed;
        }
    }

    void commit(TOP_MODULE *top) {
        top->fillTransDone_i = 1;
        top->fillTransSuccess_i = 1;
    }

    void clearCommit(TOP_MODULE *top) {
        top->fillTransDone_i = 0;
        top->fillTransSuccess_i = 0;
    }
};

class FIFOPopper {
  public:
    std::vector<uint8_t> poppedData;

  private:
    bool enabled = false;

  public:
    void reset(TOP_MODULE *top) {
        poppedData.clear();

        // Data receive interface
        top->popTransDone_i = 0;
        top->popTransSuccess_i = 0;
        top->popData_i = 0;

        clearCommit(top);
    }

    void enable() {
        enabled = true;
    }
    void disable() {
        enabled = false;
    }
    bool isEnabled() const {
        return enabled;
    }

    void emptyFIFO(TOP_MODULE *top, bool posedge, bool negedge) {
        if (!enabled) {
            return;
        }
        if (negedge) {
            top->popData_i = enabled;
            return;
        }

        bool popHandshake = top->popData_i && top->dataAvailable_o;

        if (popHandshake) {
            poppedData.push_back(top->data_o);
        }
    }

    void commit(TOP_MODULE *top) {
        top->popTransDone_i = 1;
        top->popTransSuccess_i = 1;
    }

    void clearCommit(TOP_MODULE *top) {
        top->popTransDone_i = 0;
        top->popTransSuccess_i = 0;
    }
};

class FIFOSim : public VerilatorTB<FIFOSim, TOP_MODULE> {
  public:
    void simReset() {
        popper.reset(top);
        pusher.reset(top);
        commit = false;
    }

    bool stopCondition() {
        return forceStop || (pusher.isEnabled() && top->full_o) || (popper.isEnabled() && !top->dataAvailable_o);
    }

    void onRisingEdge() {
        if (commit) {
            popper.commit(top);
            pusher.commit(top);
        } else {
            popper.emptyFIFO(top, true, false);
            pusher.fillFIFO(top, true, false);
        }
    }
    void onFallingEdge() {
        if (!commit) {
            popper.emptyFIFO(top, false, true);
            pusher.fillFIFO(top, false, true);
        }
    }

    bool customInit(int, const char *) { return false; }
    void sanityChecks() {}

  public:
    FIFOPopper popper;
    FIFOPusher pusher;
    bool commit;
};

/******************************************************************************/
// static constexpr int fifoSize = 512;
static constexpr int fifoSize = 502;

int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    FIFOSim sim;
    if (!sim.init(argc, argv)) {
        return 1;
    }

    sim.reset();

    sim.pusher.enable();
    sim.popper.disable();

    bool failed = false;

    // Execute till stop condition
    while (!sim.run<true>(0)) {
    }

    sim.commit = true;
    sim.run<true, false>(1);

    failed = sim.pusher.pushed != fifoSize;
    std::cout << "Pushed " << sim.pusher.pushed << " elements!" << std::endl;

    if (failed) {
        goto exitAndCleanup;
    }

    sim.reset();

    sim.pusher.disable();
    sim.popper.enable();

    // Execute till stop condition
    while (!sim.run<true>(0)) {
    }

    sim.commit = true;
    sim.run<true, false>(1);

    failed = sim.popper.poppedData.size() != fifoSize;
    std::cout << "Popped " << sim.popper.poppedData.size() << " elements!" << std::endl;

    if (failed) {
        goto exitAndCleanup;
    }

    for (int i = 0; i < sim.popper.poppedData.size(); ++i) {
        uint8_t expected = i & 0xFF;
        uint8_t got = sim.popper.poppedData[i];
        if (got != expected) {
            failed = true;
            std::cout << "Popped wrong value at idx: " << i << " expected: " << static_cast<int>(expected) << " Got: " << static_cast<int>(got) << std::endl;
        }
    }

exitAndCleanup:

    std::cout << std::endl
              << "Tests ";

    if (forceStop) {
        std::cout << "ABORTED!" << std::endl;
        std::cerr << "The user requested a forced stop!" << std::endl;
    } else if (failed) {
        std::cout << "FAILED!" << std::endl;
    } else {
        std::cout << "PASSED!" << std::endl;
    }

    return 0;
}