#pragma once

#include <getopt.h>
#include <verilated.h> // Defines common routines

#ifdef DUMP_FST
#include <verilated_fst_c.h>
#define VERILATOR_DUMPFILE_CLASS VerilatedFstC
#else
#include <verilated_vcd_c.h>
#define VERILATOR_DUMPFILE_CLASS VerilatedVcdC
#endif

template <class Impl, class TOP>
class VerilatorTB {
  private:
    template <bool dump>
    void tick();

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
        static_cast<Impl*>(this)->simReset();
    }

    bool init(int argc, char **argv);
    template <bool dump, bool checkStopCondition = true, bool runSanityChecks = true, bool runOnRisingEdge = true, bool runOnFallingEdge = true>
    bool run(uint64_t limit);

  private:
    VerilatedContext *const simContext;

  protected:
    TOP * top;

  private:
    VERILATOR_DUMPFILE_CLASS *traceFile = nullptr;
};

double sc_time_stamp() {
    return 0;
}

#include "VerilatorTB.tpp"
