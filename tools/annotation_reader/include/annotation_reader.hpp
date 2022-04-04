#pragma once

#include <fstream>
#include <ostream>
#include <string>
#include <vector>

enum UsbPacket {
    NONE,
    SOF,
    SETUP,
    IN,
    OUT,
    DATA,
    HANDSHAKE,
};

struct Packet {
    int64_t startTime, endTime;
    UsbPacket type;
    bool ignore;

    friend std::ostream &operator<<(std::ostream &s, const Packet& p);
};

class annotation_reader {
  public:
    annotation_reader(const std::string &path) : in(path) {}

    bool operator()() {
        return good();
    }
    bool good() {
        return in.good();
    }

    void parse(std::vector<Packet> &packets);

  private:
    std::ifstream in;
};
