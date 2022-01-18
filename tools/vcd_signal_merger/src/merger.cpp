#include "merger.hpp"

#include <fstream>
#include <map>
#include <utility>
#include <memory>

#include <iostream>

struct SignalMergeState {
    std::string outputVcdSymbol;
    // NOTE we are not able to represent 'z' & 'x'
    bool currentState;
    // Keep track if the value was changed within this timestep!

    bool changedValue = false;
    bool initialized = false;
    const bool mergeViaAND;

    const size_t size;
    std::unique_ptr<bool[]> values;

    SignalMergeState(bool mergeViaAND, size_t size) : mergeViaAND(mergeViaAND), size(size), values(new bool[size]) {}

    void mergeSignal(size_t i, bool newValue) {
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

        changedValue = !initialized || changedValue || (updatedState != currentState);
        currentState = updatedState;
    }

    void handleTimestepEnd(std::ofstream &out) {
        // Only print the variable state, if it has changed!
        if (changedValue) {
            initialized = true;
            out << (currentState ? '1' : '0') << outputVcdSymbol << std::endl;
        }
        // Clear the changed flag
        changedValue = false;
    }
};

int mergeVcdFiles(const std::string &inputFile, const std::string &outputFile, const std::vector<MergeSignals> &mergeSignals) {
    std::ifstream in(inputFile);
    std::ofstream out(outputFile);

    if (!in) {
        std::cout << "Could not open input file: " << inputFile << std::endl;
        return 3;
    }
    if (!out) {
        std::cout << "Could not open output file: " << outputFile << std::endl;
        return 3;
    }

    std::vector<SignalMergeState> states;
    std::map<std::string, std::pair<size_t, SignalMergeState *>> signalNameToState;
    for (const auto &s : mergeSignals) {
        auto &ref = states.emplace_back(s.mergeViaAND, s.signalNames.size());

        size_t i = 0;
        for (const auto &e : s.signalNames) {
            signalNameToState.insert({e, std::make_pair(i, &ref)});
            ++i;
        }
    }

    std::map<std::string, std::pair<size_t, SignalMergeState *>> vcdAliases;

    std::string line;

    // Parse the header
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        if (line.starts_with("$var")) {
            // Expected format: `$var` <type> <bitWidth> <vcdAlias> <signalName> `$end`
            auto typeStart = line.find_first_not_of(" ", 4);
            if (typeStart == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }
            auto typeEnd = line.find(" ", typeStart);
            if (typeEnd == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }

            auto bitWidthStart = line.find_first_not_of(" ", typeEnd);
            if (bitWidthStart == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }
            auto bitWidthEnd = line.find(" ", bitWidthStart);
            if (bitWidthEnd == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }
            if (line[bitWidthStart] != '1' || bitWidthStart + 1 != bitWidthEnd) {
                std::cout << "Warning: unsupported bitwidth: " << line.substr(bitWidthStart, bitWidthEnd - bitWidthStart) << std::endl;
                out << line << std::endl;
                continue;
            }

            auto vcdAliasStart = line.find_first_not_of(" ", bitWidthEnd);
            if (vcdAliasStart == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }
            auto vcdAliasEnd = line.find(" ", vcdAliasStart);
            if (vcdAliasEnd == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }

            auto signalNameStart = line.find_first_not_of(" ", vcdAliasEnd);
            if (signalNameStart == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }
            auto signalNameEnd = line.find(" ", signalNameStart);
            if (signalNameEnd == std::string::npos) {
                std::cout << "Invalid $var define!" << std::endl;
                out << line << std::endl;
                continue;
            }

            std::string vcdAlias(line.substr(vcdAliasStart, vcdAliasEnd - vcdAliasStart));
            std::string signalName(line.substr(signalNameStart, signalNameEnd - signalNameStart));

            std::cout << "Info: found variable: '" << signalName << "' with alias '" << vcdAlias << "'" << std::endl;

            auto it = signalNameToState.find(signalName);
            if (it != signalNameToState.end()) {
                // Add the new alias
                vcdAliases.insert({vcdAlias, it->second});
                if (it->second.second->outputVcdSymbol.empty()) {
                    // This is the first alias for this signal group!
                    // -> keep this signal definition & set it as outputVcdSymbol
                    out << line << std::endl;
                    it->second.second->outputVcdSymbol = vcdAlias;
                }
            } else {
                std::cout << "Warning: no entry found for signal: " << signalName << std::endl;
                // We still want to keep this signal!
                out << line << std::endl;
            }
        } else {
            // We dont care about this line, just write it too
            out << line << std::endl;

            // We are done with the header!
            if (line.starts_with("$dumpvars")) {
                break;
            }
        }
    }

    if (!in.good()) {
        return 0;
    }

    // Handle the actual dump data!
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        bool isTimestampEnd = line.starts_with('#');
        bool isVariableUpdate = !isTimestampEnd && !line.starts_with('$');
        if (isVariableUpdate) {
            // Expected format: <value><vcdAlias> or b<multibit value> <vcdAlias>
            std::string vcdAlias;
            bool value;

            if (line[0] == 'b') {
                // Multibit value: currently we can not handle this
                std::cout << "Warning: multibit values are unsupported!" << std::endl;
                out << line << std::endl;
                continue;
            } else {
                // Single bit value
                char valueChar = line[0];
                if (valueChar != '0' && valueChar != '1') {
                    std::cout << "Warning: unsupported value: " << valueChar << std::endl;
                    out << line << std::endl;
                    continue;
                }
                value = valueChar == '1';
                vcdAlias = line.substr(1);
            }

            auto it = vcdAliases.find(vcdAlias);
            if (it != vcdAliases.end()) {
                it->second.second->mergeSignal(it->second.first, value);
            } else {
                std::cout << "Warning: no entry found for vcd alias: " << vcdAlias << std::endl;
                std::cout << "    raw line: " << line << std::endl;
                // We still want to keep this signal!
                out << line << std::endl;
            }
        } else if (isTimestampEnd) {
            // Iterate over all signal groups to dump updated values
            for (auto &s : states) {
                s.handleTimestepEnd(out);
            }
            // Also print this line that signaled the end of an timestamp
            out << line << std::endl;
        } else {
            // We neither know nor want to know what this line is, just pass it on!
            // TODO log?
            out << line << std::endl;
        }
    }

    // One final dump for updated values
    for (auto &s : states) {
        s.handleTimestepEnd(out);
    }

    return 0;
}
