#include <fstream>
#include <getopt.h>
#include <iostream>
#include <sstream>
#include <string>
#include <tuple>
#include <vector>

#include "tokenizer.hpp"

static void printHelp() {
    std::cout << "Usage: ./tla_to_vcd -i <input.txt> -o <output.vcd> "
              << std::endl;
}

int main(int argc, char **argv) {
    std::string outputFile;
    std::string inputFile;

    int opt;
    while ((opt = getopt(argc, argv, "i:o:")) != -1) {
        switch (opt) {
            case 'i': {
                inputFile = optarg;
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

    if (inputFile.empty() || outputFile.empty()) {
        std::cout << "You need to specify an input text and an output vcd file!"
                  << std::endl;
        printHelp();
        return 1;
    }

    std::ofstream out(outputFile);
    if (!out.good()) {
        std::cout << "Error: could not open output file!" << std::endl;
        return 2;
    }
    Tokenizer tokenizer(inputFile);
    if (!tokenizer.good()) {
        std::cout << "Error: could not open input file!" << std::endl;
        return 3;
    }

    std::vector<std::tuple<std::string, uint8_t>> variableStates;

    // Parse the header!
    std::string field;
    if (tokenizer.expectToken("Sample")) {
        return 4;
    }
headerLoop:
    if (tokenizer.expectHasNextField(field)) {
        return 5;
    }
    if (field != "Timestamp") {
        variableStates.push_back({field, 0});
        goto headerLoop;
    }

    // create the VCD header
    out << "$timescale 1ns $end\n";
    for (const auto &p : variableStates) {
        for (unsigned i = 0; i < 8 * sizeof(decltype(std::get<1>((p)))); ++i) {
            std::stringstream s;
            s << std::get<0>(p) << '[' << i << ']';
            out << "$var wire 1 " << s.str() << ' ' << s.str() << " $end\n";
        }
    }
    out << "$enddefinitions $end\n";
    out << "#1\n";
    out << "$dumpvars\n";
    // Zero initialize the variables
    for (const auto &p : variableStates) {
        for (unsigned i = 0; i < 8 * sizeof(decltype(std::get<1>((p)))); ++i) {
            std::stringstream s;
            s << std::get<0>(p) << '[' << i << ']';
            out << "0" << s.str() << "\n";
        }
    }
    out << "$end\n";

    // Parse all lines!
    uint64_t timestamp = 1;
    std::vector<std::string> backlog;
    while (!tokenizer.getNextField(field)) {
        // Get the variables values
        for (auto &p : variableStates) {
            if (tokenizer.expectHasNextField(field)) {
                return 6;
            }
            // convert hex value to uint8_t
            uint8_t newValue = std::stoul(field, nullptr, 16);

            // add variable updates to the backlog
            for (uint8_t change = std::get<1>(p) ^ newValue; change;
                 change &= change - 1) {
                unsigned idx = __builtin_ctz(change);
                unsigned bitValue = (newValue >> idx) & 1;
                std::stringstream s;
                s << bitValue << std::get<0>(p) << '[' << idx << "]\n";
                backlog.push_back(s.str());
            }

            // save the updated value
            std::get<1>(p) = newValue;
        }

        if (tokenizer.expectHasNextField(field)) {
            return 7;
        }
        // parse timestep & update timestamp!
        timestamp += std::stod(field);

        // timescale unit: ps, ns, ...
        if (tokenizer.expectHasNextField(field)) {
            return 8;
        }

        // print timestamp & backlog
        if (!backlog.empty()) {
            out << '#' << timestamp << '\n';
            for (auto &&s : backlog) {
                out << s;
            }
            backlog.clear();
        }
    }

    return 0;
}
