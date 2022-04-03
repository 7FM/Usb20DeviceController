#pragma once

#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

template <class T>
class vcd_reader {
  public:
    vcd_reader(const std::string &path,
               std::function<std::optional<T>(const std::string & /*line*/, const std::string & /*signalName*/, const std::string & /*vcdAlias*/, const std::string & /*typeStr*/, const std::string & /*bitwidthStr*/)> handlerCreator,
               std::function<void(std::vector<std::string> & /*printBacklog*/)> handleTimestampEnd,
               std::function<bool(uint64_t /*timestamp*/)> handleTimestampStart,
               std::function<void(const std::string & /*line*/)> handleIgnoredLine);

    bool operator()() {
        return good();
    }
    bool good() {
        return in.good();
    }

    void process(bool truncate = true);

  private:
    bool parseVariableUpdates(bool truncate, std::string &line, std::vector<std::string> &printBacklog);

  private:
    std::ifstream in;

    const std::function<void(std::vector<std::string> & /*printBacklog*/)> handleTimestampEnd;
    const std::function<bool(uint64_t /*timestamp*/)> handleTimestampStart;
    const std::function<void(const std::string & /*line*/)> handleIgnoredLine;
    std::map<std::string, T> vcdAliases;

    bool showedMultibitWarning = false;
};

#include "vcd_reader.tpp"
