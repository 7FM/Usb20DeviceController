#include "tokenizer.hpp"

#include <iostream>

Tokenizer::Tokenizer(const std::string &path)
    : lineNr(0), tokenNr(0), in(path), buffer() {}

bool Tokenizer::good() const { return in.good(); }

bool Tokenizer::getNextField(std::string &field) {
    field.clear();
    const std::string delims(" \t\r\b\a\f\v");

    auto fieldStart = buffer.find_first_not_of(delims);
    while (fieldStart == std::string::npos) {
        if (!in.good()) {
            return true;
        }
        std::getline(in, buffer);
        ++lineNr;
        tokenNr = 0;
        fieldStart = buffer.find_first_not_of(delims);
    }

    auto fieldEnd = buffer.find_first_of(delims, fieldStart);
    if (fieldEnd == std::string::npos) {
        field = buffer.substr(fieldStart);
        buffer.clear();
    } else {
        field = buffer.substr(fieldStart, fieldEnd - fieldStart);
        buffer = buffer.substr(fieldEnd + 1);
    }

    ++tokenNr;

    return field.empty();
}

bool Tokenizer::expectHasNextField(std::string &field) {
    if (getNextField(field)) {
        std::cout << "ERROR: expected a token after line " << lineNr
                  << " token " << tokenNr << std::endl;
        return true;
    }
    return false;
}

bool Tokenizer::expectToken(const std::string &token) {
    std::string nextToken;
    if (getNextField(nextToken)) {
        return true;
    }
    bool failed = nextToken != token;
    if (failed) {
        std::cout << "ERROR: at line " << lineNr << " token " << tokenNr
                  << " expected token: " << token << "but got: " << nextToken
                  << std::endl;
    }
    return failed;
}