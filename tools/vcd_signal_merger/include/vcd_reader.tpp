#include "vcd_reader.hpp"

#include <iostream>
#include <sstream>

static const std::string DATE_TOKEN("$date");
static const std::string VERSION_TOKEN("$version");
static const std::string TIMESCALE_TOKEN("$timescale");
static const std::string COMMENT_TOKEN("$comment");
static const std::string VAR_TOKEN("$var");
static const std::string SCOPE_TOKEN("$scope");
static const std::string UPSCOPE_TOKEN("$upscope");
static const std::string END_TOKEN("$end");
static const std::string DUMPVARS_TOKEN("$dumpvars");
static const std::string ENDDEFINITIONS_TOKEN("$enddefinitions");

template <class T>
vcd_reader<T>::vcd_reader(const std::string &path,
                          HandlerCreator handlerCreator,
                          TimestampEndHandler handleTimestampEnd,
                          TimestampStartHandler handleTimestampStart,
                          LinePrinter linePrinter)
    : tokenizer(path), vcdAliases(), handleTimestampEnd(handleTimestampEnd),
      handleTimestampStart(handleTimestampStart), linePrinter(linePrinter),
      tickFreq(parseHeader(std::move(handlerCreator))) {}

template <class T>
uint64_t vcd_reader<T>::parseHeader(HandlerCreator handlerCreator) {
    uint64_t immTickFreq = 0;
    std::stack<std::string> scopes;

    // Parse the header
    std::string token;
    while (!tokenizer.getNextField(token)) {
        if (token == VAR_TOKEN) {
            // Expected format:
            // `$var` <type> <bitWidth> <vcdAlias> <signalName> `$end`
            std::string typeStr;
            std::string bitwidthStr;
            std::string vcdAlias;
            std::string signalName;

            if (tokenizer.expectHasNextField(typeStr) ||
                tokenizer.expectHasNextField(bitwidthStr) ||
                tokenizer.expectHasNextField(vcdAlias) ||
                tokenizer.expectHasNextField(signalName) ||
                tokenizer.expectToken(END_TOKEN)) {
                std::cout << "ERROR: Invalid $var define!" << std::endl;
                continue;
            }

            if (auto handler = handlerCreator(scopes, signalName, vcdAlias,
                                              typeStr, bitwidthStr)) {
                vcdAliases.emplace(vcdAlias, handler.value());
            }
        } else if (token == SCOPE_TOKEN) {
            // Expected format: $scope <type> <name> $end
            std::string typeStr; // TODO useful?
            std::string scopeName;

            if (tokenizer.expectHasNextField(typeStr) ||
                tokenizer.expectHasNextField(scopeName) ||
                tokenizer.expectToken(END_TOKEN)) {
                std::cout << "ERROR: Invalid $scope define!" << std::endl;
                continue;
            }

            // Print the scope
            linePrinter(SCOPE_TOKEN + ' ' + typeStr + ' ' + scopeName + ' ' +
                            END_TOKEN,
                        true);

            scopes.push(std::move(scopeName));
        } else if (token == UPSCOPE_TOKEN) {
            // Expected format: $upscope $end
            scopes.pop();

            if (tokenizer.expectToken(END_TOKEN)) {
                std::cout << "ERROR: Invalid $upscope define!" << std::endl;
                continue;
            }

            // Print the upscope
            linePrinter(UPSCOPE_TOKEN + ' ' + END_TOKEN, true);
        } else if (token == ENDDEFINITIONS_TOKEN) {
            // Expected format: $enddefinitions $end
            linePrinter(token, true);

            // However, for $dumpvars <stuff> are value initializations!
            if (tokenizer.expectToken(END_TOKEN)) {
                std::cout << "ERROR: Illformed " << ENDDEFINITIONS_TOKEN
                          << std::endl;
                break;
            }

            // We are done with the header!
            linePrinter(END_TOKEN, true);
            break;
        } else if (token == DATE_TOKEN || token == VERSION_TOKEN ||
                   token == COMMENT_TOKEN) {
            // Expected format: <token> [<stuff>]* $end
            std::string collectedTokens;
            while (token != END_TOKEN) {
                collectedTokens += token + ' ';
                if (tokenizer.expectHasNextField(token)) {
                    break;
                }
            }
            linePrinter(collectedTokens, true);
            linePrinter(token, true);
        } else if (token == TIMESCALE_TOKEN) {
            // Expected format: $timescale <factor>[ ]*[<timescale>] $end
            // -> the timescale might be expressed with a single token or two
            linePrinter(token, true);
            if (tokenizer.expectHasNextField(token)) {
                // TODO error
                continue;
            }
            std::string factorPart = token;
            linePrinter(token, true);
            if (tokenizer.expectHasNextField(token)) {
                // TODO error
                continue;
            }
            std::string scalePart = token;
            linePrinter(token, true);

            if (token != END_TOKEN) {
                if (tokenizer.expectToken(END_TOKEN)) {
                    // TODO error
                    continue;
                }
                linePrinter(END_TOKEN, true);
            } else {
                // extract the factor and scale part from factorPart which
                // currently contains both!
                unsigned scalePartOffset = 0;
                for (unsigned end = factorPart.size(); scalePartOffset < end;
                     ++scalePartOffset) {
                    auto c = factorPart[scalePartOffset];
                    if (c < '0' || c > '9') {
                        break;
                    }
                }
                scalePart = factorPart.substr(scalePartOffset);
                factorPart = factorPart.substr(0, scalePartOffset);
            }

            uint64_t factor = 1;
            factor = std::stoull(factorPart);
            if (factor == 0) {
                // Avoid div by 0
                std::cout << "WARNING: timescale section would cause a "
                             "division by zero!"
                          << std::endl;
                continue;
            }
            uint64_t scaleFreq = 1;
            if (scalePart == "ps") {
                scaleFreq = static_cast<uint64_t>(1e12);
            } else if (scalePart == "ns") {
                scaleFreq = static_cast<uint64_t>(1e9);
            } else if (scalePart == "us") {
                scaleFreq = static_cast<uint64_t>(1e6);
            } else if (scalePart == "ms") {
                scaleFreq = static_cast<uint64_t>(1e3);
            } else if (scalePart != "s") {
                std::cout << "ERROR: unknown timescale '" << scalePart << "'"
                          << std::endl;
                continue;
            }
            immTickFreq = scaleFreq / factor;
        } else {
            linePrinter(token, true);
            if (token[0] != '$') {
                std::cout << "WARNING: illformed header! Unknown token: '"
                          << token << "'. Stopping header parsing!"
                          << std::endl;
                break;
            }
            // We dont care about this token, just write it too
            std::cout << "WARNING: unknown token: '" << token << '\''
                      << std::endl;
        }
    }

    return immTickFreq;
}

template <class T>
bool vcd_reader<T>::parseVariableUpdate(
    bool truncate, std::string &token, std::vector<std::string> &printBacklog) {
    // Expected format:
    // <value><vcdAlias> or b<multibit value> <vcdAlias> or r<decimal value>
    // <vcdAlias>
    std::string vcdAlias;

    ValueUpdate valueUpdate;

    bool print = false;

    if (token[0] == 'b') {
        // Expected format: b<multibit value> <vcdAlias>

        valueUpdate.type = MULTI_BIT;

        valueUpdate.valueStr = token.substr(1);

    // Extract the vcd alias
    extractVcdAlias:
        // backup the value field
        std::string valueField = token;
        if (tokenizer.expectHasNextField(token)) {
            // TODO?
        }
        vcdAlias = token;
        // reconstruct the whole variable update string
        token = valueField + ' ' + token;
    } else if (token[0] == 'r') {
        // Expected format: r<decimal value> <vcdAlias>

        valueUpdate.type = REAL;

        valueUpdate.valueStr = token.substr(1);
        std::stringstream realStream(valueUpdate.valueStr);
        realStream >> valueUpdate.value.real;

        if (realStream.fail()) {
            std::cout << "Warning: failed to parse real number: "
                      << valueUpdate.valueStr << std::endl;
            if (!truncate) {
                print = true;
                printBacklog.push_back(token);
                if (tokenizer.expectHasNextField(token)) {
                    // TODO?
                }
                printBacklog.push_back(token);
            }
            return print;
        }

        // Extract the vcd alias
        goto extractVcdAlias;
    } else {
        // Expected format: <value><vcdAlias>
        valueUpdate.type = SINGLE_BIT;

        char valueChar = token[0];
        valueUpdate.valueStr = valueChar;
        if (valueChar != '0' && valueChar != '1') {
            std::cout << "Warning: unsupported value: '" << valueChar << '\''
                      << std::endl;
            if (!truncate) {
                print = true;
                printBacklog.push_back(token);
            }
            return print;
        }
        valueUpdate.value.singleBit = valueChar == '1';
        vcdAlias = token.substr(1);
    }

    auto vcdHandlerIt = vcdAliases.find(vcdAlias);
    if (vcdHandlerIt != vcdAliases.end()) {
        print |= vcdHandlerIt->second.handleValueChange(std::cref(valueUpdate));
    } else if (!truncate) {
        std::cout << "Warning: no entry found for vcd alias: " << vcdAlias
                  << std::endl;
        std::cout << "    raw line: " << token << std::endl;
        // We still want to keep this signal!
        print = true;
        printBacklog.push_back(token);
    }

    return print;
}

template <class T> void vcd_reader<T>::process(bool truncate) {
    std::vector<std::string> printBacklog;
    bool print = false;
    bool maskPrinting = true;

    // Handle the actual dump data!
    std::string token;
    while (!tokenizer.getNextField(token)) {

        bool isTimestampEnd = token.starts_with('#');
        bool isVariableUpdate = !isTimestampEnd && !token.starts_with('$');
        if (isVariableUpdate) {
            print |= parseVariableUpdate(truncate, token, printBacklog);
        } else if (isTimestampEnd) {
            if (!maskPrinting && print) {
                handleTimestampEnd(printBacklog);
                for (const auto &s : printBacklog) {
                    linePrinter(s, false);
                }
            }
            printBacklog.clear();
            maskPrinting = true;
            print = false;

            uint64_t timestamp = std::stoull(token.substr(1));
            maskPrinting = handleTimestampStart(timestamp);
            // Also print this line that signaled the end of an timestamp
            printBacklog.push_back(token);
        } else if (token == DUMPVARS_TOKEN) {
            // Expected format: $dumpvars [<stuff>]* $end
            linePrinter(token,
                        true); // This is still somewhat part of the header
            std::vector<std::string> initBacklog;
            initBacklog.push_back(token);

            // However, for $dumpvars <stuff> are value initializations!
            if (tokenizer.expectHasNextField(token)) {
                break;
            }
            bool printInit = false;
            while (token != END_TOKEN) {
                printInit |= parseVariableUpdate(truncate, token, initBacklog);
                if (tokenizer.expectHasNextField(token)) {
                    break;
                }
            }
            initBacklog.push_back(END_TOKEN);

            if (!maskPrinting && printInit) {
                handleTimestampEnd(initBacklog);
                for (const auto &s : initBacklog) {
                    linePrinter(s, false);
                }
            }
        } else {
            std::cout << "WARNING: unknown token: '" << token << "'"
                      << std::endl;
            // TODO this might change the position of that line! ADD BIG
            // WARNING!
            //  We neither know nor want to know what this line is, just pass it
            //  on!
            linePrinter(token, false);
        }
    }

    if (!maskPrinting && print) {
        handleTimestampEnd(printBacklog);
        for (const auto &s : printBacklog) {
            linePrinter(s, false);
        }
    } else if (!printBacklog.empty()) {
        handleTimestampEnd(printBacklog);
        // Always print the last timestamp!
        linePrinter(printBacklog[0], false);
    }
}
