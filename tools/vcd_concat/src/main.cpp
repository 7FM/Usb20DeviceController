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

struct DummySignalWrapper {
    bool handleValueChange(
        const vcd_reader<DummySignalWrapper>::ValueUpdate &value) {
        return true;
    }
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
    for (const auto &inputVcdFile : inputVcdFiles) {
        vcd_reader<DummySignalWrapper> vcdReader(
            inputVcdFile,
            [&](const std::stack<std::string> & /*scopes*/,
                const std::string & /*signalName*/,
                const std::string & /*vcdAlias*/,
                const std::string & /*typeStr*/,
                const std::string & /*bitwidthStr*/)
                -> std::optional<DummySignalWrapper> {
                // keep everything!
                return std::nullopt;
            },
            [&](std::vector<std::string> &printBacklog) {
                // on timestamp end -> patch the timestamp
                if (!printBacklog.empty()) {
                    printBacklog[0] = std::string("#") +
                                      std::to_string(lastTimestamp + offset);
                }
            },
            [&](uint64_t timestamp) {
                lastTimestamp = timestamp;
                // print it all
                return false;
            },
            [&](const std::string &line, bool isHeader) {
                if (offset == 0 || !isHeader) {
                    out << line << std::endl;
                }
            });

        if (!vcdReader.good() || !out.good()) {
            return 2;
        }

        // run the vcdReader
        vcdReader.process(false);

        // TODO prevent printing the header stuff twice! iff offset
        offset += lastTimestamp;
    }

    return 0;
}
