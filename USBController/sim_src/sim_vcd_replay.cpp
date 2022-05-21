#include <atomic>
#include <cassert>
#include <csignal>
#include <cstdint>
#include <cstring>
#include <functional>
#include <string>

#define TOP_MODULE Vsim_vcd_replay
#include "Vsim_vcd_replay.h"       // basic Top header
#include "Vsim_vcd_replay__Syms.h" // all headers to access exposed internal signals

#include "../../tools/vcd_signal_merger/include/vcd_reader.hpp"
#include "common/VerilatorTB.hpp"

static std::atomic_bool forceStop = false;

static void signalHandler(int signal) {
    if (signal == SIGINT) {
        forceStop = true;
    }
}

/******************************************************************************/

class UsbVcdReplaySim : public VerilatorTB<UsbVcdReplaySim, TOP_MODULE> {

  public:
    void simReset() {
        // Idle state
        top->USB_DP = 1;
        top->USB_DN = 0;

        // Finally run the usb reset procedure
        usbReset();
    }

    bool stopCondition() { return forceStop; }

    void usbReset() {
        top->forceSE0 = 1;
        // Run with the reset signal for some time //TODO how many cycles
        // exactly???
        run<true, false>(200);
        top->forceSE0 = 0;
    }

    bool customInit(int opt, const char *optarg) {
        switch (opt) {
            case 'r': {
                // Replay file
                replayFile = optarg;
                return true;
            }
        }
        return false;
    }
    void onRisingEdge() {}
    void onFallingEdge() {}
    void sanityChecks() {}

    bool updateUSB_DP(bool value) {
        top->USB_DP = value;
        return false;
    }
    bool updateUSB_DN(bool value) {
        top->USB_DN = value;
        return false;
    }

  public:
    bool tickEqualsClockFreq = false;
    const char *replayFile = nullptr;
};

bool getForceStop() { return forceStop; }

/******************************************************************************/

struct DummyForwarder {
    DummyForwarder(std::function<bool(bool)> handler) : handler(handler) {}

    bool
    handleValueChange(const vcd_reader<DummyForwarder>::ValueUpdate &value) {
        assert(value.type == vcd_reader<DummyForwarder>::SINGLE_BIT);
        return handler(value.value.singleBit);
    }

  private:
    const std::function<bool(bool)> handler;
};

struct SimWrapper {
    SimWrapper(UsbVcdReplaySim *sim) : sim(sim) {}

    std::optional<DummyForwarder> handlerCreator(
        const std::stack<std::string> & /*scopes*/,
        const std::string &signalName, const std::string & /*vcdAlias*/,
        const std::string & /*typeStr*/, const std::string & /*bitwidthStr*/) {
        auto usbP = signalName.find("USB_DP");
        auto usbN = signalName.find("USB_DN");
        if (usbP != std::string::npos) {
            return DummyForwarder(std::bind(&UsbVcdReplaySim::updateUSB_DP, sim,
                                            std::placeholders::_1));
        } else if (usbN != std::string::npos) {
            return DummyForwarder(std::bind(&UsbVcdReplaySim::updateUSB_DN, sim,
                                            std::placeholders::_1));
        }

        return std::nullopt;
    }
    bool handleTimestampStart(uint64_t timestamp) {
        // run sim for the expired cycles
        uint64_t cyclesPassed = timestamp - lastTimestamp;

        sim->run<true>(cyclesPassed);

        lastTimestamp = timestamp;
        return true;
    }

  private:
    uint64_t lastTimestamp = 0;
    UsbVcdReplaySim *const sim;
};

int main(int argc, char **argv) {
    std::signal(SIGINT, signalHandler);

    UsbVcdReplaySim sim;
    if (!sim.init(argc, argv)) {
        return 1;
    }

    if (sim.replayFile == nullptr) {
        std::cout << "Missing vcd file to replay!" << std::endl;
        std::cout << "Usage: ./Vsim_vcd_replay -r <path_to_vcd_file> [other "
                     "sim options]"
                  << std::endl;
        return 2;
    }

    // issue a usb reset before starting with the replay!
    sim.reset();

    SimWrapper wrapper(&sim);

    vcd_reader<DummyForwarder> vcdParser(
        sim.replayFile,
        std::bind(&SimWrapper::handlerCreator, &wrapper, std::placeholders::_1,
                  std::placeholders::_2, std::placeholders::_3,
                  std::placeholders::_4, std::placeholders::_5),
        [&](std::vector<std::string> &printBacklog) {},
        std::bind(&SimWrapper::handleTimestampStart, &wrapper,
                  std::placeholders::_1),
        [](auto &, bool) {});

    vcdParser.process();

    return 0;
}

// Don't do this at home!
#include "../../tools/vcd_signal_merger/include/tokenizer.cpp"
