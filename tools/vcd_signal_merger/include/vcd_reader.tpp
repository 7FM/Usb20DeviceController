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
    : tokenizer(path), handleTimestampEnd(handleTimestampEnd),
      handleTimestampStart(handleTimestampStart), linePrinter(linePrinter) {

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
                vcdAliases.insert({vcdAlias, handler.value()});
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
                        END_TOKEN);

            scopes.push(std::move(scopeName));
        } else if (token == UPSCOPE_TOKEN) {
            // Expected format: $upscope $end
            scopes.pop();

            if (tokenizer.expectToken(END_TOKEN)) {
                std::cout << "ERROR: Invalid $upscope define!" << std::endl;
                continue;
            }

            // Print the upscope
            linePrinter(UPSCOPE_TOKEN + ' ' + END_TOKEN);
        } else if (token == DUMPVARS_TOKEN || token == ENDDEFINITIONS_TOKEN) {
            linePrinter(token);

            // We are done with the header!
            break;
        } else if (token == DATE_TOKEN || token == TIMESCALE_TOKEN ||
                   token == VERSION_TOKEN || token == COMMENT_TOKEN) {
            // Expected format: <token> [<stuff>]* $end
            std::string collectedTokens;
            while (token != END_TOKEN) {
                collectedTokens += token + ' ';
                if (tokenizer.expectHasNextField(token)) {
                    break;
                }
            }
            linePrinter(collectedTokens);
            linePrinter(token);
        } else {
            // We dont care about this token, just write it too
            std::cout << "WARNING: unknown token: '" << token << '\''
                      << std::endl;
            linePrinter(token);
        }
    }
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
                    linePrinter(s);
                }
            }
            printBacklog.clear();
            maskPrinting = true;
            print = false;

            uint64_t timestamp = std::stoull(token.substr(1));
            maskPrinting = handleTimestampStart(timestamp);
            // Also print this line that signaled the end of an timestamp
            printBacklog.push_back(token);
        } else {
            std::cout << "WARNING: unknown token: '" << token << "'"
                      << std::endl;
            // TODO this might change the position of that line! ADD BIG
            // WARNING!
            //  We neither know nor want to know what this line is, just pass it
            //  on!
            linePrinter(token);
        }
    }

    if (!maskPrinting && print) {
        handleTimestampEnd(printBacklog);
        for (const auto &s : printBacklog) {
            linePrinter(s);
        }
    } else if (!printBacklog.empty()) {
        // Always print the last timestamp!
        linePrinter(printBacklog[0]);
    }
}
