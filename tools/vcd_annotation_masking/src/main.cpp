#include <cassert>
#include <fstream>
#include <getopt.h>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "device_masker.hpp"
#include "vcd_reader.hpp"

static void printHelp() {
    std::cout << "Usage: ./vcd_annotation_masking -i <input.vcd> -a "
                 "<annotation.txt> -o <output.vcd>"
              << std::endl;
}

struct SignalState {
    std::string outputVcdSymbol;
    // NOTE we are not able to represent 'z' & 'x'
    bool currentState;
    // Keep track if the value was changed within this timestep!

    bool changedValue = false;
    bool initialized = false;

    bool handleValueChange(bool newValue) {
        changedValue =
            !initialized || changedValue || (newValue != currentState);
        currentState = newValue;
        return changedValue;
    }

    void handleTimestepEnd(std::vector<std::string> &printBacklog) {
        // Only print the variable state, if it has changed!
        if (changedValue) {
            std::string res = (currentState ? '1' : '0') + outputVcdSymbol;
            printBacklog.push_back(std::move(res));
        }

        initialized = initialized || changedValue;
        // Clear the changed flag
        changedValue = false;
    }
};

struct SignalWrapper {
    SignalWrapper(SignalState *state) : state(state) {}

    bool
    handleValueChange(const vcd_reader<SignalWrapper>::ValueUpdate &value) {
        assert(value.type == vcd_reader<SignalWrapper>::SINGLE_BIT);
        return state->handleValueChange(value.value.singleBit);
    }

    SignalState *const state;
};

int main(int argc, char **argv) {
    std::string inputVcdFile;
    std::string outputFile;
    std::string inputAnnotationFile;
    uint64_t padding = 10;
    uint64_t downsampleFactor = 1;

    int opt;
    while ((opt = getopt(argc, argv, "i:a:o:p:d:")) != -1) {
        switch (opt) {
            case 'i': {
                inputVcdFile = optarg;
                break;
            }
            case 'a': {
                inputAnnotationFile = optarg;
                break;
            }
            case 'o': {
                outputFile = optarg;
                break;
            }
            case 'p': {
                padding = std::stoull(optarg);
                break;
            }
            case 'd': {
                downsampleFactor = std::stoull(optarg);
                break;
            }
            default: {
                std::cout << "Unknown option: -" << opt << "!" << std::endl;
                printHelp();
                break;
            }
        }
    }

    if (inputVcdFile.empty() || inputAnnotationFile.empty() ||
        outputFile.empty()) {
        std::cout << "You need to specify a input vcd file, a annotation file "
                     "and a output vcd file!"
                  << std::endl;
        printHelp();
        return 1;
    }

    std::vector<Packet> packets;
    decltype(packets.size()) packetIdx = 0;
    {
        annotation_reader annotationReader(inputAnnotationFile);

        if (!annotationReader.good()) {
            return 2;
        }

        annotationReader.parse(packets);
        maskDevicePackets(packets);
    }

    for (decltype(packets.size()) i = 0; i < packets.size(); ++i) {
        packets[i].startTime *= downsampleFactor;
        packets[i].endTime *= downsampleFactor;
        std::cout << "Packet " << (i + 1) << "/" << packets.size() << ": "
                  << packets[i] << std::endl;
    }

    std::vector<std::unique_ptr<SignalState>> signals;

    std::ofstream out(outputFile);
    vcd_reader<SignalWrapper> vcdReader(
        inputVcdFile,
        [&](const std::stack<std::string> & /*scopes*/,
            const std::string &signalName, const std::string &vcdAlias,
            const std::string &typeStr,
            const std::string &bitwidthStr) -> std::optional<SignalWrapper> {
            auto it = signalName.find("USB_D");
            if (bitwidthStr.size() != 1 || bitwidthStr[0] != '1' ||
                it == std::string::npos) {
                // std::cout << "Warning: unsupported bitwidth: " <<
                // line.substr(bitWidthStart, bitWidthEnd - bitWidthStart) <<
                // std::endl; out << line << std::endl;
                return std::nullopt;
            }

            // -> keep this signal definition
            out << VAR_TOKEN << ' ' << typeStr << ' ' << bitwidthStr << ' '
                << vcdAlias << ' ' << signalName << ' ' << END_TOKEN
                << std::endl;

            const auto &ref =
                signals.emplace_back(std::make_unique<SignalState>());

            SignalWrapper wrapper(ref.get());
            ref->outputVcdSymbol = vcdAlias;
            return wrapper;
        },
        [&](std::vector<std::string> &printBacklog) {
            // Iterate over all signal groups to dump updated values
            for (auto &s : signals) {
                s->handleTimestepEnd(printBacklog);
            }
        },
        [&](uint64_t timestamp) {
            // Check whether the current packet is masked!
            bool ignore = false;
            for (; packetIdx < packets.size(); ++packetIdx) {
                const auto &p = packets[packetIdx];

                if (static_cast<int64_t>(timestamp) < p.startTime - padding) {
                    // we haven't reached the current packet yet!
                    break;
                } else if (p.endTime + padding >=
                           static_cast<int64_t>(timestamp)) {
                    ignore = p.ignore;
                    break;
                }
            }

            return ignore;
        },
        [&](const std::string &line, bool /*isHeader*/) {
            out << line << std::endl;
        });

    if (!vcdReader.good() || !out.good()) {
        return 3;
    }

    bool truncate = true;
    // run the vcdReader
    vcdReader.process(truncate);

    return 0;
}
