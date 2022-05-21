#include <cassert>
#include <fstream>
#include <getopt.h>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "vcd_reader.hpp"

static void printHelp() {
    std::cout
        << "Usage: ./vcd_annotation_masking -i <input.vcd> -o <output.vcd>"
        << std::endl;
}

struct SignalAveraging {
    static constexpr unsigned subgroupSize = 16;
    std::vector<std::vector<double>> avgState;

    SignalAveraging() {
        std::vector<double> doubles;
        doubles.reserve(subgroupSize);
        avgState.push_back(std::move(doubles));
    }

  private:
    double avg;

    void insertValue(double newValue, unsigned idx) {
        auto &i = avgState[idx];
        i.push_back(newValue);
        // propergate the subaverages
        if (i.size() == subgroupSize) {
            double subAvg = 0.0;
            for (double d : i) {
                subAvg += d;
            }
            subAvg /= subgroupSize;
            i.clear();

            // insert the new subaverage if the following group already exists,
            // else create it
            ++idx;
            if (idx == avgState.size()) {
                std::vector<double> doubles;
                doubles.reserve(subgroupSize);
                doubles.push_back(subAvg);
                avgState.push_back(std::move(doubles));
            } else {
                insertValue(subAvg, idx);
            }
        }
    }

  public:
    bool handleValueChange(double newValue) {
        insertValue(newValue, 0);
        // We dont want to print anything
        return false;
    }

    void handleTimestepEnd(std::vector<std::string> & /*printBacklog*/) {}

    void finalizeAveraging() {
        unsigned samplesTaken = 0;
        for (auto rIt = avgState.rbegin(), endIt = avgState.rend();
             rIt != endIt; ++rIt) {
            samplesTaken = rIt->size() + samplesTaken * subgroupSize;
        }

        double correctionTerm = 1.0 / samplesTaken;
        double overallAvg = 0.0;
        for (const auto &l : avgState) {
            double localSum = 0.0;
            for (double d : l) {
                localSum += d;
            }
            localSum *= correctionTerm;
            overallAvg += localSum;
            correctionTerm *= subgroupSize;
        }

        avgState.clear();
        avg = overallAvg;
    }

    double getFinalAverage() { return avg; }
};

struct SignalWrapper {
    SignalWrapper(SignalAveraging *state) : state(state) {}

    bool
    handleValueChange(const vcd_reader<SignalWrapper>::ValueUpdate &value) {
        assert(value.type == vcd_reader<SignalWrapper>::REAL);
        return state->handleValueChange(value.value.real);
    }

    SignalAveraging *const state;
};

int main(int argc, char **argv) {
    std::string inputVcdFile;
    std::string outputFile;

    int opt;
    while ((opt = getopt(argc, argv, "i:o:")) != -1) {
        switch (opt) {
            case 'i': {
                inputVcdFile = optarg;
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

    if (inputVcdFile.empty() || outputFile.empty()) {
        std::cout
            << "You need to specify a input vcd file and a output vcd file!"
            << std::endl;
        printHelp();
        return 1;
    }

    std::map<std::string, std::unique_ptr<SignalAveraging>> realSignals;

    vcd_reader<SignalWrapper> vcdAvgReader(
        inputVcdFile,
        [&](const std::stack<std::string> & /*scopes*/,
            const std::string & /*line*/, const std::string & /*signalName*/,
            const std::string &vcdAlias, const std::string &typeStr,
            const std::string & /*bitwidthStr*/)
            -> std::optional<SignalWrapper> {
            if (typeStr != "real") {
                return std::nullopt;
            }

            auto ref = std::make_unique<SignalAveraging>();
            SignalWrapper wrapper(ref.get());
            realSignals.emplace(vcdAlias, std::move(ref));

            return wrapper;
        },
        [&](std::vector<std::string> & /*printBacklog*/) {},
        [&](uint64_t /*timestamp*/) {
            // ignore it all
            return true;
        },
        [&](const std::string & /*line*/) { /*nothing to print here*/ });

    if (!vcdAvgReader.good()) {
        return 3;
    }

    bool truncate = true;
    // run the vcdReader
    vcdAvgReader.process(truncate);
    for (auto &[first, second] : realSignals) {
        second->finalizeAveraging();
        // TODO remove
        std::cout << "Calculated Avg: " << second->getFinalAverage()
                  << std::endl;
    }

    /* TODO read the vcd file again but this time apply the averaging create
       binary output! std::ofstream out(outputFile); if (!vcdReader.good() ||
       !out.good()) { return 3;
        }
    */
    return 0;
}
