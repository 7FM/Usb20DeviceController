#pragma once

#include <fstream>
#include <string>

class Tokenizer {
  public:
    Tokenizer(const std::string &path);

    bool getNextField(std::string &fieldOut);
    bool expectHasNextField(std::string &fieldOut);
    bool expectToken(const std::string &token);

    bool good() const;

  private:
    unsigned lineNr;
    unsigned tokenNr;
    std::ifstream in;
    std::string buffer;
};
