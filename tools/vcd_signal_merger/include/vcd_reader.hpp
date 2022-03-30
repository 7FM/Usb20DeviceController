#pragma once

#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>

template <class T>
class vcd_reader {
  public:
    vcd_reader(const std::string &path,
               std::function<std::optional<T>(const std::string & /*line*/, const std::string & /*signalName*/, const std::string & /*vcdAlias*/, const std::string & /*typeStr*/, const std::string & /*bitwidthStr*/)> handlerCreator,
               std::function<void(uint64_t /*timestamp*/)> handleTimestamp,
               std::function<void(const std::string & /*line*/)> handleIgnoredLine);

    bool operator()() {
        return good();
    }
    bool good() {
        return in.good();
    }

    bool singleStep(bool truncate = true);

  private:
    void parseVariableUpdates(bool truncate, std::string& line);

  private:
    std::ifstream in;

    const std::function<void(uint64_t /*timestamp*/)> handleTimestamp;
    const std::function<void(const std::string & /*line*/)> handleIgnoredLine;
    std::map<std::string, T> vcdAliases;

    bool showedMultibitWarning = false;
};

#include "vcd_reader.tpp"
