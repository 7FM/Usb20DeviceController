#pragma once

#include <set>
#include <string>
#include <vector>

struct MergeSignals
{
    std::set<std::string> signalNames;
    bool mergeViaAND; // Else merges with OR
};

int mergeVcdFiles(const std::string &inputFile, const std::string &outputFile, const std::vector<MergeSignals> &mergeSignals, bool truncate);
