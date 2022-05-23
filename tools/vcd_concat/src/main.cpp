#include <cassert>
#include <fstream>
#include <getopt.h>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "vcd_reader.hpp"

static void printHelp() {
    std::cout << "Usage: ./vcd_concat -i <input_1.vcd> -i <input_2.vcd> -o "
                 "<output.vcd>"
              << std::endl;
}

struct TranslatingSignalWrapper {
    TranslatingSignalWrapper(std::string &newVcdAlias)
        : vcdAlias(newVcdAlias), value(), valueChanged(false) {}

    bool handleValueChange(
        const vcd_reader<TranslatingSignalWrapper>::ValueUpdate &value) {
        if (this->value != value.valueStr) {
            this->valueChanged = true;
            this->value = value.valueStr;
            this->type = value.type;
        }
        return true;
    }

    void handleTimestepEnd(std::vector<std::string> &printBacklog) {
        if (valueChanged) {
            valueChanged = false;
            switch (type) {
                case vcd_reader<TranslatingSignalWrapper>::SINGLE_BIT:
                    printBacklog.push_back(value + vcdAlias);
                    break;
                case vcd_reader<TranslatingSignalWrapper>::MULTI_BIT:
                    printBacklog.push_back('b' + value + ' ' + vcdAlias);
                    break;
                case vcd_reader<TranslatingSignalWrapper>::REAL:
                    printBacklog.push_back('r' + value + ' ' + vcdAlias);
                    break;
                default:
                    std::cout << "ERROR: unexpected value type!" << std::endl;
                    break;
            }
        }
    }

  private:
    const std::string vcdAlias;
    std::string value;
    vcd_reader<TranslatingSignalWrapper>::ValueType type;
    bool valueChanged;
};

int main(int argc, char **argv) {
    std::string outputFile;

    std::vector<std::string> inputVcdFiles;

    int opt;
    while ((opt = getopt(argc, argv, "i:o:")) != -1) {
        switch (opt) {
            case 'i': {
                inputVcdFiles.push_back(optarg);
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

    if (inputVcdFiles.empty() || outputFile.empty()) {
        std::cout
            << "You need to specify a input vcd file and a output vcd file!"
            << std::endl;
        printHelp();
        return 1;
    }

    uint64_t offset = 0;
    uint64_t lastTimestamp = 0;
    std::ofstream out(outputFile);

    std::map<std::string, std::string> signalNameTranslation;

    for (const auto &inputVcdFile : inputVcdFiles) {
        const bool firstRun = offset == 0;
        vcd_reader<TranslatingSignalWrapper> vcdReader(
            inputVcdFile,
            [&](const std::stack<std::string> & /*scopes*/,
                const std::string &signalName, const std::string &vcdAlias,
                const std::string &typeStr, const std::string &bitwidthStr)
                -> std::optional<TranslatingSignalWrapper> {
                // keep everything!
                if (firstRun) {
                    out << VAR_TOKEN << ' ' << typeStr << ' ' << bitwidthStr
                        << ' ' << vcdAlias << ' ' << signalName << ' '
                        << END_TOKEN << std::endl;
                    signalNameTranslation.emplace(signalName, vcdAlias);
                } else {
                    auto it = signalNameTranslation.find(signalName);
                    if (it == signalNameTranslation.end()) {
                        std::cout
                            << "WARNING: can not concat signal: " << signalName
                            << std::endl;
                        return std::nullopt;
                    }

                    return TranslatingSignalWrapper(it->second);
                }

                return std::nullopt;
            },
            [&](std::vector<std::string> &printBacklog) {
                // on timestamp end -> patch the timestamp
                if (!printBacklog.empty()) {
                    // Check if this is a regular timestamp
                    if (printBacklog[0][0] == '#') {
                    patchBacklog:
                        printBacklog[0] =
                            std::string("#") +
                            std::to_string(lastTimestamp + offset);
                    } else if (printBacklog[0] == DUMPVARS_TOKEN) {
                        // Value initialization
                        if (!firstRun) {
                            // Remove the $end!
                            printBacklog.pop_back();
                            goto patchBacklog;
                        }
                    } else {
                        std::cout << "ERROR: unknown timestampEnd cause with "
                                     "first token: "
                                  << printBacklog[0] << std::endl;
                        return;
                    }
                }
                for (auto &[first, second] : vcdReader.getVcdAliasHandler()) {
                    second.handleTimestepEnd(printBacklog);
                }
            },
            [&](uint64_t timestamp) {
                lastTimestamp = timestamp;
                // print it all
                return false;
            },
            [&](const std::string &line, bool isHeader) {
                if (firstRun || !isHeader) {
                    out << line << std::endl;
                }
            });

        if (!vcdReader.good() || !out.good()) {
            return 2;
        }

        // run the vcdReader
        vcdReader.process(!firstRun, !firstRun);

        offset += lastTimestamp;
    }

    return 0;
}
