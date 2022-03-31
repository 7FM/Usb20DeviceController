#include <fstream>
#include <getopt.h>
#include <iostream>
#include <vector>
#include <memory>

#include "device_masker.hpp"
#include "vcd_reader.hpp"

static void printHelp() {
    std::cout << "Usage: ./vcd_annotation_masking -i <input.vcd> -a <annotation.txt> -o <output.vcd>" << std::endl;
}

struct SignalState {
    std::string outputVcdSymbol;
    // NOTE we are not able to represent 'z' & 'x'
    bool currentState;
    // Keep track if the value was changed within this timestep!

    bool changedValue = false;
    bool initialized = false;

    void handleValueChange(bool newValue) {
        changedValue = !initialized || changedValue || (newValue != currentState);
        currentState = newValue;
    }

    void handleTimestepEnd(std::ofstream &out, bool ignore) {
        // Only print the variable state, if it has changed!
        if (!ignore && changedValue) {
            out << (currentState ? '1' : '0') << outputVcdSymbol << std::endl;
        }

        initialized = initialized || changedValue;
        // Clear the changed flag
        changedValue = false;
    }
};


struct SignalWrapper {
    SignalWrapper(SignalState *state) : state(state) {}

    void handleValueChange(bool value) {
        state->handleValueChange(value);
    }

    SignalState *const state;
};


int main(int argc, char **argv) {
    std::string inputVcdFile;
    std::string outputFile;
    std::string inputAnnotationFile;

    int opt;
    while ((opt = getopt(argc, argv, "i:a:o:")) != -1) {
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
            default: {
                std::cout << "Unknown option: -" << opt << "!" << std::endl;
                printHelp();
                break;
            }
        }
    }

    if (inputVcdFile.empty() || inputAnnotationFile.empty() || outputFile.empty()) {
        std::cout << "You need to specify a input vcd file, a annotation file and a output vcd file!" << std::endl;
        printHelp();
        return 1;
    }

    std::ofstream out(outputFile);
    std::vector<std::unique_ptr<SignalState>> signals;

    annotation_reader annotationReader(inputAnnotationFile);
    vcd_reader<SignalWrapper> vcdReader(
        inputVcdFile,
        [&](const std::string &line, const std::string &signalName, const std::string &vcdAlias, const std::string &typeStr, const std::string &bitwidthStr) -> std::optional<SignalWrapper> {
            if (bitwidthStr.size() != 1 || bitwidthStr[0] != '1' || !signalName.starts_with("USB_D")) {
                // std::cout << "Warning: unsupported bitwidth: " << line.substr(bitWidthStart, bitWidthEnd - bitWidthStart) << std::endl;
                // out << line << std::endl;
                return std::nullopt;
            }

            const auto &ref = signals.emplace_back(std::make_unique<SignalState>());

            SignalWrapper wrapper(ref.get());
            ref->outputVcdSymbol = vcdAlias;
            return wrapper;
        },
        [&](uint64_t timestamp) {
            bool ignore; // TODO use timestamp to get the packet annotation!

            // Iterate over all signal groups to dump updated values
            for (auto &s : signals) {
                s->handleTimestepEnd(out, ignore);
            }
        },
        [&](const std::string &line) { out << line << std::endl; });

    if (!annotationReader.good() || !vcdReader.good() || !out.good()) {
        return 2;
    }

    std::vector<Packet> packets;
    annotationReader.parse(packets);

    maskDevicePackets(packets);

    for (decltype(packets.size()) i = 0; i < packets.size(); ++i) {
        std::cout << "Packet " << (i + 1) << "/" << packets.size() << ": " << packets[i] << std::endl;
    }

    bool truncate = true;
    // run the vcdReader
    while (vcdReader.singleStep(truncate)) {
    }

    return 0;
}
