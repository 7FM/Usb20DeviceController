#include <getopt.h>
#include <iostream>

#include "merger.hpp"

static void printHelp() {
    std::cout
        << "Usage: ./vcd_signal_merger -i <input.vcd> -o <output.vcd> [OPTIONS]"
        << std::endl;
    // TODO print options
}

static void parseMergeSignalArgs(const std::string &arg, MergeSignals &merge) {
    // Expected format: <Signal1>;<Signal2>;....;<SignalN>
    auto pos = arg.find(";");
    auto prevPos = pos;
    prevPos = 0;
    std::cout << "Requested merging:";
    while (pos != std::string::npos) {
        auto sig = arg.substr(prevPos, pos - prevPos);
        std::cout << " " << sig;
        merge.signalNames.insert(std::move(sig));
        prevPos = pos + 1;
        pos = arg.find(";", prevPos);
    }
    auto sig = arg.substr(prevPos);
    merge.signalNames.insert(sig);
    std::cout << " " << sig << std::endl;
}

int main(int argc, char **argv) {
    std::string inputFile;
    std::string outputFile;
    std::vector<MergeSignals> mergeSignals;

    bool truncate = false;

    int opt;
    while ((opt = getopt(argc, argv, "Hhi:o:A:O:t")) != -1) {
        switch (opt) {
            case 'i': {
                inputFile = optarg;
                break;
            }
            case 'o': {
                outputFile = optarg;
                break;
            }
            case 't': {
                truncate = true;
                break;
            }
            case 'A': {
                auto &ref = mergeSignals.emplace_back();
                ref.mergeViaAND = true;
                parseMergeSignalArgs(optarg, ref);
                break;
            }
            case 'O': {
                auto &ref = mergeSignals.emplace_back();
                ref.mergeViaAND = false;
                parseMergeSignalArgs(optarg, ref);
                break;
            }
            default: {
                std::cout << "Unknown option: -" << opt << "!" << std::endl;
                printHelp();
                break;
            }
        }
    }

    if (inputFile.empty() || outputFile.empty()) {
        std::cout << "You need to specify both a input & output file!"
                  << std::endl;
        printHelp();
        return 1;
    }

    if (mergeSignals.empty()) {
        std::cout << "You need to specify at least 2 signal names that are "
                     "supposed to be merged to merge!"
                  << std::endl;
        printHelp();
        return 2;
    }

    return mergeVcdFiles(inputFile, outputFile, mergeSignals, truncate);
}
