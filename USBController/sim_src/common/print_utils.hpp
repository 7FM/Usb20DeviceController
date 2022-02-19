#pragma once

#include <iostream>
#include <ostream>

// Taken from: https://stackoverflow.com/questions/2273330/restore-the-state-of-stdcout-after-manipulating-it/18822888#18822888
class IosFlagSaver {
  public:
    explicit IosFlagSaver(std::ostream &_ios) : ios(_ios),
                                                f(_ios.flags()) {
    }
    ~IosFlagSaver() {
        ios.flags(f);
    }

    IosFlagSaver(const IosFlagSaver &rhs) = delete;
    IosFlagSaver &operator=(const IosFlagSaver &rhs) = delete;

  private:
    std::ostream &ios;
    std::ios::fmtflags f;
};

template <class V>
bool compareVec(const V &expected, const V &got,
                const std::string &lengthErrMsg, const std::string &dataErrMsg) {
    bool failed = false;
    if (got.size() != expected.size()) {
        std::cout << lengthErrMsg << std::endl;
        std::cout << "  Expected: " << expected.size() << " but got: " << got.size() << std::endl;
        failed = true;
    }

    IosFlagSaver _(std::cout);
    int minSize = std::min(got.size(), expected.size());
    for (int i = 0; i < minSize; ++i) {
        if (got[i] != expected[i]) {
            failed = true;
            std::cout << dataErrMsg << std::dec << i << std::endl;
            std::cout << "  Expected: 0x" << std::hex << static_cast<int>(expected[i]) << " but got: 0x" << static_cast<int>(got[i]) << std::endl;
        }
    }
    return failed;
}
