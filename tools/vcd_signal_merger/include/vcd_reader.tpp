#include "vcd_reader.hpp"

#include <iostream>

static bool extractNextField(const std::string &line, std::string &field,
                             std::string::size_type &searchOffset) {
    searchOffset = line.find_first_not_of(" ", searchOffset);
    if (searchOffset == std::string::npos) {
        return true;
    }

    auto nextSearchOffset = line.find(" ", searchOffset);
    if (nextSearchOffset == std::string::npos) {
        return true;
    }

    field =
        std::string(line.substr(searchOffset, nextSearchOffset - searchOffset));
    searchOffset = nextSearchOffset;

    return false;
}

template <class T>
vcd_reader<T>::vcd_reader(const std::string &path,
                          HandlerCreator handlerCreator,
                          TimestampEndHandler handleTimestampEnd,
                          TimestampStartHandler handleTimestampStart,
                          IgnoredLineHandler handleIgnoredLine)
    : in(path), handleTimestampEnd(handleTimestampEnd),
      handleTimestampStart(handleTimestampStart),
      handleIgnoredLine(handleIgnoredLine) {

    std::string line;
    std::stack<std::string> scopes;

    // Parse the header
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        if (line.starts_with("$var")) {
            // Expected format:
            // `$var` <type> <bitWidth> <vcdAlias> <signalName> `$end`
            std::string::size_type searchOffset = 4;

            std::string typeStr;
            std::string bitwidthStr;
            std::string vcdAlias;
            std::string signalName;

            if (extractNextField(line, typeStr, searchOffset) ||
                extractNextField(line, bitwidthStr, searchOffset) ||
                extractNextField(line, vcdAlias, searchOffset) ||
                extractNextField(line, signalName, searchOffset)) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }

            if (auto handler = handlerCreator(scopes, line, signalName,
                                              vcdAlias, typeStr, bitwidthStr)) {
                vcdAliases.insert({vcdAlias, handler.value()});
            }
        } else if (line.starts_with("$scope")) {
            // Expected format: $scope <type> <name> $end
            std::string::size_type searchOffset = 6;
            std::string typeStr; // TODO useful?
            std::string scopeName;

            handleIgnoredLine(line);

            if (extractNextField(line, typeStr, searchOffset) ||
                extractNextField(line, scopeName, searchOffset)) {
                std::cout << "ERROR: Invalid $scope define!" << std::endl;
                continue;
            }

            scopes.push(std::move(scopeName));
        } else if (line.starts_with("$upscope")) {
            // Expected format: $upscope $end
            scopes.pop();
        } else {
            // We dont care about this line, just write it too
            handleIgnoredLine(line);

            // We are done with the header!
            if (line.starts_with("$dumpvars") ||
                line.starts_with("$enddefinitions")) {
                break;
            }
        }
    }
}

static auto updateIt(std::string &line, std::string &variableUpdate) {
    auto it = line.find(' ');
    if (it != std::string::npos) {
        variableUpdate = line.substr(0, it);
        line = line.substr(it + 1);
        it = line.find_first_not_of(' ');
        if (it != std::string::npos) {
            line = line.substr(it);
        }
    } else {
        variableUpdate = line;
    }
    return it;
}

template <class T>
bool vcd_reader<T>::parseVariableUpdates(
    bool truncate, std::string &line, std::vector<std::string> &printBacklog) {
    // Expected format: <value><vcdAlias> or b<multibit value> <vcdAlias>
    std::string vcdAlias;
    bool value;
    bool print = false;

    decltype(line.find(' ')) it;
    do {
        std::string variableUpdate;

        it = updateIt(line, variableUpdate);

        if (variableUpdate[0] == 'b') {
            // Multibit value: currently we can not handle this
            if (!showedMultibitWarning) {
                showedMultibitWarning = true;
                std::cout << "Warning: multibit values are unsupported!"
                          << std::endl;
            }
            if (!truncate) {
                print = true;
                printBacklog.push_back(variableUpdate);
            }
            it = updateIt(line, variableUpdate);
            if (!truncate) {
                printBacklog.push_back(variableUpdate);
            }
            continue;
        } else {
            // Single bit value
            char valueChar = variableUpdate[0];
            if (valueChar != '0' && valueChar != '1') {
                std::cout << "Warning: unsupported value: '" << valueChar
                          << '\'' << std::endl;
                if (!truncate) {
                    print = true;
                    printBacklog.push_back(variableUpdate);
                }
                continue;
            }
            value = valueChar == '1';
            vcdAlias = variableUpdate.substr(1);
        }

        auto vcdHandlerIt = vcdAliases.find(vcdAlias);
        if (vcdHandlerIt != vcdAliases.end()) {
            print |= vcdHandlerIt->second.handleValueChange(value);
        } else if (!truncate) {
            std::cout << "Warning: no entry found for vcd alias: " << vcdAlias
                      << std::endl;
            std::cout << "    raw line: " << variableUpdate << std::endl;
            // We still want to keep this signal!
            print = true;
            printBacklog.push_back(variableUpdate);
        }
    } while (it != std::string::npos);

    return print;
}

template <class T> void vcd_reader<T>::process(bool truncate) {
    std::string line;

    std::vector<std::string> printBacklog;
    bool print = false;
    bool maskPrinting = true;

    // Handle the actual dump data!
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        bool isTimestampEnd = line.starts_with('#');
        bool isVariableUpdate = !isTimestampEnd && !line.starts_with('$');
        if (isVariableUpdate) {
            print |= parseVariableUpdates(truncate, line, printBacklog);
        } else if (isTimestampEnd) {
            if (!maskPrinting && print) {
                handleTimestampEnd(printBacklog);
                for (const auto &s : printBacklog) {
                    handleIgnoredLine(s);
                }
            }
            printBacklog.clear();
            maskPrinting = true;
            print = false;

            // extract the new timestamp value!
            auto it = line.find(' ');
            std::string timestempStr;
            if (it != std::string::npos) {
                timestempStr = line.substr(0, it);
            } else {
                timestempStr = line;
            }

            uint64_t timestamp = std::stoull(timestempStr.substr(1));
            maskPrinting = handleTimestampStart(timestamp);
            // Also print this line that signaled the end of an timestamp
            printBacklog.push_back(timestempStr);

            if (it != std::string::npos) {
                std::string updates = line.substr(it + 1);

                auto it = updates.find_first_not_of(' ');
                if (it != std::string::npos) {
                    updates = updates.substr(it);
                    if (!updates.empty()) {
                        // TODO test inline updates within the same line as the
                        // timestamp!
                        print |= parseVariableUpdates(truncate, updates,
                                                      printBacklog);
                    }
                }
            }

        } else {
            // TODO this might change the position of that line! ADD BIG
            // WARNING!
            //  We neither know nor want to know what this line is, just pass it
            //  on!
            handleIgnoredLine(line);
        }
    }

    if (!maskPrinting && print) {
        handleTimestampEnd(printBacklog);
        for (const auto &s : printBacklog) {
            handleIgnoredLine(s);
        }
    }
}
