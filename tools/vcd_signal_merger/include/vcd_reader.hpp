#pragma once

#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <stack>
#include <string>
#include <utility>
#include <vector>

template <class T> class vcd_reader {
  public:
    using HandlerCreator = std::function<std::optional<T>(
        const std::stack<std::string> & /*scopes*/,
        const std::string & /*line*/, const std::string & /*signalName*/,
        const std::string & /*vcdAlias*/, const std::string & /*typeStr*/,
        const std::string & /*bitwidthStr*/)>;
    using TimestampEndHandler =
        std::function<void(std::vector<std::string> & /*printBacklog*/)>;
    using TimestampStartHandler = std::function<bool(uint64_t /*timestamp*/)>;
    using LinePrinter = std::function<void(const std::string & /*line*/)>;

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
    bool good() { return in.good(); }

    void process(bool truncate = true);

  private:
    bool parseVariableUpdates(bool truncate, std::string &line,
                              std::vector<std::string> &printBacklog);

  private:
    std::ifstream in;

    const std::function<void(std::vector<std::string> & /*printBacklog*/)>
        handleTimestampEnd;
    const std::function<bool(uint64_t /*timestamp*/)> handleTimestampStart;
    const std::function<void(const std::string & /*line*/)> linePrinter;
    std::map<std::string, T> vcdAliases;
};

#include "vcd_reader.tpp"
