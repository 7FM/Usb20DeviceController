#include <cassert>
#include <cmath>
#include <fstream>
#include <getopt.h>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "vcd_reader.hpp"

static void printHelp() {
    std::cout << "Usage: ./vcd_time_to_clk -i <input.vcd> -o <output.vcd> "
                 "-s <signalFreq> -t <targetMultiplier>"
              << std::endl;
}

struct DummySignalWrapper {
    bool handleValueChange(
        const vcd_reader<DummySignalWrapper>::ValueUpdate & /*value*/) {
        return true;
    }
};

int main(int argc, char **argv) {
    std::string outputFile;
    std::string inputVcdFile;

    std::string signalFreqStr = "12MHz";
    std::string targetMultiplierStr = "4";

    int opt;
    while ((opt = getopt(argc, argv, "i:o:s:t:")) != -1) {
        switch (opt) {
            case 'i': {
                inputVcdFile = optarg;
                break;
            }
            case 'o': {
                outputFile = optarg;
                break;
            }
            case 's': {
                signalFreqStr = optarg;
                break;
            }
            case 't': {
                targetMultiplierStr = optarg;
                break;
            }
            default: {
                std::cout << "Unknown option: -" << opt << "!" << std::endl;
                printHelp();
                break;
            }
        }
    }

    if (inputVcdFile.empty() || outputFile.empty() || signalFreqStr.empty() ||
        targetMultiplierStr.empty()) {
        std::cout << "You need to specify an input and an output vcd file as "
                     "well as a signal and a target clock frequency!"
                  << std::endl;
        printHelp();
        return 1;
    }

    unsigned scalePartOffset = 0;
    for (unsigned end = signalFreqStr.size(); scalePartOffset < end;
            ++scalePartOffset) {
        auto c = signalFreqStr[scalePartOffset];
        if (c < '0' || c > '9') {
            break;
        }
    }
    std::string factorPart = signalFreqStr.substr(0, scalePartOffset);
    std::string scalePart = signalFreqStr.substr(scalePartOffset);
    for (auto& c : scalePart) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }

    uint64_t targetMultiplier = std::stoull(targetMultiplierStr);

    uint64_t sourceFreq = std::stoull(factorPart);
    if (scalePart == "hz") {
        sourceFreq *= static_cast<decltype(sourceFreq)>(1e0);
    } else if (scalePart == "khz") {
        sourceFreq *= static_cast<decltype(sourceFreq)>(1e3);
    } else if (scalePart == "mhz") {
        sourceFreq *= static_cast<decltype(sourceFreq)>(1e6);
    } else if (scalePart == "ghz") {
        sourceFreq *= static_cast<decltype(sourceFreq)>(1e9);
    } else if (scalePart == "thz") {
        sourceFreq *= static_cast<decltype(sourceFreq)>(1e12);
    } else {
        std::cout << "Unknown frequency scale: " << scalePart << std::endl;
        return 2;
    }

    uint64_t timestampDelta = 0;
    uint64_t lastTimestamp = 0;
    uint64_t lastPatchedTimestamp = 0;
    std::ofstream out(outputFile);

    double signalCyclesPerTicks;

    vcd_reader<DummySignalWrapper> vcdReader(
        inputVcdFile,
        [&](const std::stack<std::string> & /*scopes*/,
            const std::string &signalName, const std::string &vcdAlias,
            const std::string &typeStr, const std::string &bitwidthStr)
            -> std::optional<DummySignalWrapper> {
            // keep everything!
            out << VAR_TOKEN << ' ' << typeStr << ' ' << bitwidthStr << ' '
                << vcdAlias << ' ' << signalName << ' ' << END_TOKEN
                << std::endl;

            return std::nullopt;
        },
        [&](std::vector<std::string> &printBacklog) {
            // on timestamp end -> patch the timestamp
            if (!printBacklog.empty()) {
                // Check if this is a regular timestamp
                if (printBacklog[0][0] == '#') {
                    // round to the nearest integer value
                    uint64_t signalTicks =
                        std::lround(timestampDelta * signalCyclesPerTicks);
                    uint64_t patchedTimestamp =
                        lastPatchedTimestamp + signalTicks * targetMultiplier;

                    printBacklog[0] =
                        std::string("#") + std::to_string(patchedTimestamp);

                    lastPatchedTimestamp = patchedTimestamp;
                }
            }
        },
        [&](uint64_t timestamp) {
            timestampDelta = timestamp - lastTimestamp;
            lastTimestamp = timestamp;
            // print it all
            return false;
        },
        [&](const std::string &line, bool /*isHeader*/) {
            out << line << std::endl;
        });

    if (!vcdReader.good() || !out.good()) {
        return 3;
    }

    const uint64_t tickFreq = vcdReader.getTickFrequency();
    if (tickFreq == 0) {
        std::cout << "ERROR: invalid timescale" << std::endl;
        return 4;
    }
    signalCyclesPerTicks = static_cast<double>(sourceFreq) / tickFreq;

    // run the vcdReader
    vcdReader.process(false, false);

    return 0;
}
