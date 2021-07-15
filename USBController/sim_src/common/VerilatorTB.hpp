#pragma once

#include <getopt.h>
#include <verilated.h> // Defines common routines
#include <verilated_vcd_c.h>

template <class TOP>
class VerilatorTB {
  private:
    template <bool dump>
    void tick();

  protected:
    virtual bool customInit(int opt) { return false; }
    virtual void onRisingEdge(TOP *top) {}
    virtual void onFallingEdge(TOP *top) {}
    virtual void sanityChecks(const TOP *top) {}
    virtual bool stopCondition(TOP *top) { return false; }

    virtual void simReset(TOP *top) {}

  public:
    VerilatorTB();
    virtual ~VerilatorTB();

    // This class is not copyable!
    VerilatorTB(const VerilatorTB &) = delete;
    VerilatorTB &operator=(const VerilatorTB &) = delete;

    vluint64_t getSimulationTime() const {
        return simContext->time();
    }
    bool gotFinish() const {
        // Simulation called $finish
        return simContext->gotFinish();
    }
    void reset() {
        simReset(top);
    }

    bool init(int argc, char **argv);
    template <bool dump, bool checkStopCondition = true, bool runSanityChecks = true, bool runOnRisingEdge = true, bool runOnFallingEdge = true>
    bool run(uint64_t limit);

  private:
    bool initialized = false;

    VerilatedContext *const simContext;
    TOP *const top;

    VerilatedVcdC *traceFile = nullptr;
};

double sc_time_stamp() {
    return 0;
}

#include "VerilatorTB.tpp"
