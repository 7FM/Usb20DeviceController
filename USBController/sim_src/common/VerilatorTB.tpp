#include <iostream>

template <class Impl, class TOP>
VerilatorTB<Impl, TOP>::VerilatorTB() : simContext(new VerilatedContext), top(new TOP(simContext)) {
}

template <class Impl, class TOP>
VerilatorTB<Impl, TOP>::~VerilatorTB() {
    top->final();

    if (traceFile) {
        traceFile->close();
        delete traceFile;
        traceFile = nullptr;
    }

    delete top;
    delete simContext;
}

template <class Impl, class TOP>
bool VerilatorTB<Impl, TOP>::init(int argc, char **argv) {
    if (initialized) {
        return false;
    }

    simContext->commandArgs(argc, argv);

    const char *traceFilePath = nullptr;

    int opt;
    while ((opt = getopt(argc, argv, ":t:")) != -1) {
        switch (opt) {
            case 't':
                traceFilePath = optarg;
                break;
            case ':':
                std::cout << "option needs a value" << std::endl;
                return false;
            case '?': //used for some unknown options
                if (!static_cast<Impl *>(this)->customInit(opt)) {
                    std::cout << "unknown option: " << optopt << std::endl;
                    return false;
                }
                break;
        }
    }

    if (traceFilePath) {
        // init trace dump
        simContext->traceEverOn(true);
        traceFile = new VerilatedVcdC;
        top->trace(traceFile, 99);
        traceFile->open(traceFilePath);
    }

    initialized = true;

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