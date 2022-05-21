#include "merger.hpp"
#include "vcd_reader.hpp"

#include <cassert>
#include <iostream>
#include <memory>

struct SignalMergeState {
    std::string outputVcdSymbol;
    // NOTE we are not able to represent 'z' & 'x'
    bool currentState;
    // Keep track if the value was changed within this timestep!

    bool changedValue = false;
    bool initialized = false;
    const bool mergeViaAND;

  private:
    const size_t size;
    const std::unique_ptr<bool[]> values;

  public:
    SignalMergeState(const SignalMergeState &) = delete;
    SignalMergeState &operator=(const SignalMergeState &) = delete;
    SignalMergeState &operator=(SignalMergeState &&other) = delete;
    SignalMergeState(SignalMergeState &&other) = delete;

    SignalMergeState(bool mergeViaAND, size_t size)
        : mergeViaAND(mergeViaAND), size(size), values(new bool[size]) {}

    bool mergeSignal(size_t i, bool newValue) {
        values[i] = newValue;

        // Recalculate the combined state value
        bool updatedState = mergeViaAND;
        if (mergeViaAND) {
            for (size_t k = 0; k < size; ++k) {
                updatedState = updatedState && values[k];
            }
        } else {
            // merge with OR
            for (size_t k = 0; k < size; ++k) {
                updatedState = updatedState || values[k];
            }
        }

        changedValue =
            !initialized || changedValue || (updatedState != currentState);
        currentState = updatedState;
        return changedValue;
    }

    void handleTimestepEnd(std::vector<std::string> &printBacklog) {
        // Only print the variable state, if it has changed!
        if (changedValue) {
            initialized = true;
            std::string res((currentState ? '1' : '0') + outputVcdSymbol);
            printBacklog.push_back(std::move(res));
        }
        // Clear the changed flag
        changedValue = false;
    }
};

struct SignalMergerWrapper {
    SignalMergerWrapper(size_t index, SignalMergeState *mergeState)
        : index(index), mergeState(mergeState) {}

    bool handleValueChange(
        const vcd_reader<SignalMergerWrapper>::ValueUpdate &value) {
        assert(value.type == vcd_reader<SignalMergerWrapper>::SINGLE_BIT);
        return mergeState->mergeSignal(index, value.value.singleBit);
    }

    const size_t index;
    SignalMergeState *const mergeState;
};

int mergeVcdFiles(const std::string &inputFile, const std::string &outputFile,
                  const std::vector<MergeSignals> &mergeSignals,
                  bool truncate) {
    std::ofstream out(outputFile);

    if (!out) {
        std::cout << "Could not open output file: " << outputFile << std::endl;
        return 3;
    }

    std::vector<std::unique_ptr<SignalMergeState>> states;
    std::map<std::string, SignalMergerWrapper> signalNameToState;
    for (const auto &s : mergeSignals) {
        const auto &ref =
            states.emplace_back(std::make_unique<SignalMergeState>(
                s.mergeViaAND, s.signalNames.size()));
        size_t i = 0;
        for (const auto &e : s.signalNames) {
            signalNameToState.insert({e, SignalMergerWrapper(i, ref.get())});
            ++i;
        }
    }

    vcd_reader<SignalMergerWrapper> vcdHandler(
        inputFile,
        [&](const std::stack<std::string> & /*scopes*/,
            const std::string &signalName, const std::string &vcdAlias,
            const std::string &typeStr, const std::string &bitwidthStr)
            -> std::optional<SignalMergerWrapper> {
            if (bitwidthStr.size() != 1 || bitwidthStr[0] != '1') {
                // std::cout << "Warning: unsupported bitwidth: " <<
                // line.substr(bitWidthStart, bitWidthEnd - bitWidthStart) <<
                // std::endl; out << line << std::endl;
                return std::nullopt;
            }
            auto it = signalNameToState.find(signalName);
            if (it != signalNameToState.end()) {
                std::cout << "Info: found variable: '" << signalName
                          << "' with alias '" << vcdAlias << "'" << std::endl;
                auto &vcdSymbol = it->second.mergeState->outputVcdSymbol;
                if (vcdSymbol.empty()) {
                    // This is the first alias for this signal group!
                    // -> keep this signal definition & set it as
                    // outputVcdSymbol
                    out << VAR_TOKEN << ' ' << typeStr << ' ' << bitwidthStr
                        << ' ' << vcdAlias << ' ' << END_TOKEN << std::endl;
                    vcdSymbol = vcdAlias;
                }

                // return the new alias
                return it->second;
            } else if (!truncate) {
                std::cout << "Warning: no entry found for signal: "
                          << signalName << std::endl;
                // We still want to keep this signal!
                out << VAR_TOKEN << ' ' << typeStr << ' ' << bitwidthStr << ' '
                    << vcdAlias << ' ' << END_TOKEN << std::endl;
            }
            return std::nullopt;
        },
        [&](std::vector<std::string> &printBacklog) {
            // Iterate over all signal groups to dump updated values
            for (auto &s : states) {
                s->handleTimestepEnd(printBacklog);
            }
        },
        [&](uint64_t /*timestamp*/) { return false; },
        [&](const std::string &line) { out << line << std::endl; });

    if (!vcdHandler.good()) {
        std::cout << "Could not open input file: " << inputFile << std::endl;
        return 4;
    }

    // run the vcdHandler
    vcdHandler.process(truncate);

    return 0;
}
