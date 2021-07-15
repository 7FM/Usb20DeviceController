#include <iostream>

template <class TOP>
VerilatorTB<TOP>::VerilatorTB() : simContext(new VerilatedContext), top(new TOP(simContext)) {
}

template <class TOP>
VerilatorTB<TOP>::~VerilatorTB() {
    top->final();

    if (traceFile) {
        traceFile->close();
        delete traceFile;
        traceFile = nullptr;
    }

    delete top;
    delete simContext;
}
template <class TOP>
bool VerilatorTB<TOP>::init(int argc, char **argv) {
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
                if (!customInit(opt)) {
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

template <class TOP>
template <bool dump>
void VerilatorTB<TOP>::tick() {
    simContext->timeInc(1);
    top->eval();

    if constexpr (dump) {
        if (traceFile) {
            traceFile->dump(simContext->time());
        }
    }
}

template <class TOP>
template <bool dump, bool checkStopCondition, bool runSanityChecks, bool runOnRisingEdge, bool runOnFallingEdge>
bool VerilatorTB<TOP>::run(uint64_t limit) {
    bool stop;
    do {
        stop = checkStopCondition && stopCondition(top);

        top->CLK = 1;

        if constexpr (runOnRisingEdge) {
            onRisingEdge(top);
        }
        tick<dump>();

        top->CLK = 0;

        if constexpr (runOnFallingEdge) {
            onFallingEdge(top);
        }
        tick<dump>();

        if constexpr (runSanityChecks) {
            sanityChecks(top);
        }
    } while (--limit && !stop);

    return stop;
}