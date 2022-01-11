#include <cstring>
#include <iostream>
#include <string>
#include <sstream>
#include <time.h>

template <class Impl, class TOP>
VerilatorTB<Impl, TOP>::VerilatorTB() : simContext(new VerilatedContext), top(nullptr) {
}

template <class Impl, class TOP>
VerilatorTB<Impl, TOP>::~VerilatorTB() {
    if (top) {
        top->final();
    }

    if (traceFile) {
        traceFile->close();
        delete traceFile;
        traceFile = nullptr;
    }

    if (top) {
        delete top;
        top = nullptr;
    }
    delete simContext;
}

template <class Impl, class TOP>
bool VerilatorTB<Impl, TOP>::init(int argc, char **argv) {
    if (top != nullptr) {
        return false;
    }

    simContext->commandArgs(argc, argv);

    const char *traceFilePath = nullptr;
    const char *seedStr = nullptr;

    int opt;
    while ((opt = getopt(argc, argv, ":t:s:")) != -1) {
        switch (opt) {
            case 't':
                traceFilePath = optarg;
                break;
            case 's':
                seedStr = optarg;
                break;
            case ':':
                std::cout << "option needs a value" << std::endl;
                return false;
            case '?': // used for some unknown options
                if (!static_cast<Impl *>(this)->customInit(opt)) {
                    std::cout << "unknown option: " << optopt << std::endl;
                    return false;
                }
                break;
        }
    }

    unsigned seed = time(0);

    if (seedStr) {
        seed = std::atol(seedStr);
    }

    std::stringstream seedSettingStream;
    seedSettingStream << "+verilator+seed+" << seed;

    std::string seedSetting = seedSettingStream.str();

    std::cout << "Using Seed: " << seed << std::endl;

    const char *fixedVerilatorArgs[] = {
        // Random initialization
        "+verilator+rand+reset+2",
        // Zero initialization
        // "+verilator+rand+reset+0",
        // Ones initialization
        // "+verilator+rand+reset+1",
        // Random generator seed
        seedSetting.c_str(),
    };

    simContext->commandArgs(2, fixedVerilatorArgs);

    top = new TOP(simContext);
    if (traceFilePath) {
        // init trace dump
        simContext->traceEverOn(true);
        traceFile = new VERILATOR_DUMPFILE_CLASS;
        top->trace(traceFile, 99);
        traceFile->open(traceFilePath);
    }

    return true;
}

template <class Impl, class TOP>
template <bool dump>
void VerilatorTB<Impl, TOP>::tick() {
    simContext->timeInc(1);
    top->eval();

    if constexpr (dump) {
        if (traceFile) {
            traceFile->dump(simContext->time());
        }
    }
}

template <class Impl, class TOP>
template <bool dump, bool checkStopCondition, bool runSanityChecks, bool runOnRisingEdge, bool runOnFallingEdge>
bool VerilatorTB<Impl, TOP>::run(uint64_t limit) {
    bool stop;
    do {
        stop = checkStopCondition && static_cast<Impl *>(this)->stopCondition();

        top->CLK = 1;

        if constexpr (runOnRisingEdge) {
            static_cast<Impl *>(this)->onRisingEdge();
        }
        tick<dump>();

        top->CLK = 0;

        if constexpr (runOnFallingEdge) {
            static_cast<Impl *>(this)->onFallingEdge();
        }
        tick<dump>();

        if constexpr (runSanityChecks) {
            static_cast<Impl *>(this)->sanityChecks();
        }
    } while (--limit && !stop);

    return stop;
}