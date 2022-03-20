#include "vcd_reader.hpp"

#include <iostream>

template <class T>
vcd_reader<T>::vcd_reader(
    const std::string &path,
    std::function<std::optional<T>(const std::string & /*line*/, const std::string & /*signalName*/, const std::string & /*vcdAlias*/, const std::string & /*typeStr*/, const std::string & /*bitwidthStr*/)> handlerCreator,
    std::function<void(uint64_t /*timestamp*/)> handleTimestamp,
    std::function<void(const std::string & /*line*/)> handleIgnoredLine) : in(path), handleTimestamp(handleTimestamp), handleIgnoredLine(handleIgnoredLine) {

    std::string line;

    // Parse the header
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        if (line.starts_with("$var")) {
            // Expected format: `$var` <type> <bitWidth> <vcdAlias> <signalName> `$end`
            auto typeStart = line.find_first_not_of(" ", 4);
            if (typeStart == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }
            auto typeEnd = line.find(" ", typeStart);
            if (typeEnd == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }

            auto bitWidthStart = line.find_first_not_of(" ", typeEnd);
            if (bitWidthStart == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }
            auto bitWidthEnd = line.find(" ", bitWidthStart);
            if (bitWidthEnd == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }

            auto vcdAliasStart = line.find_first_not_of(" ", bitWidthEnd);
            if (vcdAliasStart == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }
            auto vcdAliasEnd = line.find(" ", vcdAliasStart);
            if (vcdAliasEnd == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }

            auto signalNameStart = line.find_first_not_of(" ", vcdAliasEnd);
            if (signalNameStart == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }
            auto signalNameEnd = line.find(" ", signalNameStart);
            if (signalNameEnd == std::string::npos) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                handleIgnoredLine(line);
                continue;
            }

            std::string vcdAlias(line.substr(vcdAliasStart, vcdAliasEnd - vcdAliasStart));
            std::string signalName(line.substr(signalNameStart, signalNameEnd - signalNameStart));
            std::string typeStr(line.substr(typeStart, typeEnd - typeStart));
            std::string bitwidthStr(line.substr(bitWidthStart, bitWidthEnd - bitWidthStart));

            if (auto handler = handlerCreator(line, signalName, vcdAlias, typeStr, bitwidthStr)) {
                vcdAliases.insert({vcdAlias, handler.value()});
            }
        } else {
            // We dont care about this line, just write it too
            handleIgnoredLine(line);

            // We are done with the header!
            if (line.starts_with("$dumpvars")) {
                break;
            }
        }
    }
}

template <class T>
bool vcd_reader<T>::singleStep(bool truncate) {
    std::string line;

    // Handle the actual dump data!
    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

        bool isTimestampEnd = line.starts_with('#');
        bool isVariableUpdate = !isTimestampEnd && !line.starts_with('$');
        if (isVariableUpdate) {
            // Expected format: <value><vcdAlias> or b<multibit value> <vcdAlias>
            std::string vcdAlias;
            bool value;

            if (line[0] == 'b') {
                // Multibit value: currently we can not handle this
                if (!showedMultibitWarning) {
                    showedMultibitWarning = true;
                    std::cout << "Warning: multibit values are unsupported!" << std::endl;
                }
                if (!truncate) {
                    handleIgnoredLine(line);
                }
                continue;
            } else {
                // Single bit value
                char valueChar = line[0];
                if (valueChar != '0' && valueChar != '1') {
                    std::cout << "Warning: unsupported value: " << valueChar << std::endl;
                    if (!truncate) {
                        handleIgnoredLine(line);
                    }
                    continue;
                }
                value = valueChar == '1';
                vcdAlias = line.substr(1);
            }

            auto it = vcdAliases.find(vcdAlias);
            if (it != vcdAliases.end()) {
                it->second.handleValueChange(value);
            } else if (!truncate) {
                std::cout << "Warning: no entry found for vcd alias: " << vcdAlias << std::endl;
                std::cout << "    raw line: " << line << std::endl;
                // We still want to keep this signal!
                handleIgnoredLine(line);
            }
        } else if (isTimestampEnd) {
            // extract the new timestamp value!
            uint64_t timestamp = std::stoull(line.substr(1));

            handleTimestamp(timestamp);
            // Also print this line that signaled the end of an timestamp
            handleIgnoredLine(line);

            // Exit the loop as only wanted to process a single timestamp
            break;
        } else {
            // We neither know nor want to know what this line is, just pass it on!
            handleIgnoredLine(line);
        }
    }

    return in.good();
}
