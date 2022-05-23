#pragma once

#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <stack>
#include <string>
#include <utility>
#include <vector>

#include "tokenizer.hpp"

template <class T> class vcd_reader {
  public:
    using HandlerCreator = std::function<std::optional<T>(
        const std::stack<std::string> & /*scopes*/,
        const std::string & /*signalName*/, const std::string & /*vcdAlias*/,
        const std::string & /*typeStr*/, const std::string & /*bitwidthStr*/)>;
    using TimestampEndHandler =
        std::function<void(std::vector<std::string> & /*printBacklog*/)>;
    using TimestampStartHandler = std::function<bool(uint64_t /*timestamp*/)>;
    using LinePrinter =
        std::function<void(const std::string & /*line*/, bool /*isHeader*/)>;

    enum ValueType {
        SINGLE_BIT,
        MULTI_BIT,
        REAL,
    };

    struct ValueUpdate {
        std::string valueStr;
        union {
            double real;
            bool singleBit;
        } value;
        ValueType type;

        ValueUpdate() = default;
        // Prevent copies
        ValueUpdate(const ValueUpdate &) = delete;
        ValueUpdate(ValueUpdate &&) = delete;
        ValueUpdate &operator=(const ValueUpdate &) = delete;
        ValueUpdate &operator=(ValueUpdate &&other) = delete;
    };

    vcd_reader(const std::string &path, HandlerCreator handlerCreator,
               TimestampEndHandler handleTimestampEnd,
               TimestampStartHandler handleTimestampStart,
               LinePrinter linePrinter);

    bool operator()() { return good(); }
    bool good() { return tokenizer.good(); }

    void process(bool truncate = true);

    std::map<std::string, T> &getVcdAliasHandler() { return vcdAliases; };

    uint64_t getTickFrequency() const { return tickFreq; }

  private:
    uint64_t parseHeader(HandlerCreator handlerCreator);

    bool parseVariableUpdate(bool truncate, std::string &line,
                             std::vector<std::string> &printBacklog);

  private:
    Tokenizer tokenizer;
    std::map<std::string, T> vcdAliases;

    const TimestampEndHandler handleTimestampEnd;
    const TimestampStartHandler handleTimestampStart;
    const LinePrinter linePrinter;
    const uint64_t tickFreq;
};

#include "vcd_reader.tpp"
