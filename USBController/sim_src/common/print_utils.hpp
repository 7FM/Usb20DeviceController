#pragma once

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