#include "annotation_reader.hpp"

#include <fstream>
#include <ostream>
#include <string>
#include <vector>

#include <iostream>

#define STRINGIFY_CASE(x) \
    case (x):             \
        return #x

static const char *usbPacketToStr(UsbPacket p) {
    switch (p) {
        STRINGIFY_CASE(NONE);
        STRINGIFY_CASE(SOF);
        STRINGIFY_CASE(SETUP);
        STRINGIFY_CASE(IN);
        STRINGIFY_CASE(OUT);
        STRINGIFY_CASE(DATA);
        STRINGIFY_CASE(HANDSHAKE);
    }
    return "INVALID";
}

std::ostream &operator<<(std::ostream &s, const Packet &p) {
    s << usbPacketToStr(p.type) << " start: " << p.startTime << " end: " << p.endTime << " ignore: " << p.ignore;
    return s;
}

void annotation_reader::parse(std::vector<Packet> &packets) {
    std::string line;
    Packet currentPacket;
    currentPacket.type = NONE;

    while (in.good()) {
        std::getline(in, line);

        if (line.empty()) {
            continue;
        }

#define SEARCH_TERM " USB packet: Packet fields: "
        auto constexpr searchTermSize = sizeof(SEARCH_TERM) / sizeof(SEARCH_TERM[0]);
#define DELIMITER_TERM ": "
        auto constexpr delimiterTermSize = sizeof(DELIMITER_TERM) / sizeof(DELIMITER_TERM[0]);
        auto it = line.find(SEARCH_TERM);
        if (it != std::string::npos) {
            std::string region = line.substr(0, it);

            auto regionSplit = region.find('-');

            if (regionSplit == std::string::npos) {
                // TODO warn?
                continue;
            }

            uint64_t regionStart = std::stoull(region.substr(0, regionSplit));
            uint64_t regionEnd = std::stoull(region.substr(regionSplit + 1));
            // regionStart = static_cast<decltype(regionStart)>(regionStart * 1'000'000'000.0 / (2 * 48'000'000));
            // regionEnd = static_cast<decltype(regionEnd)>(regionEnd * 1'000'000'000.0 / (2 * 48'000'000));

            line = line.substr(it + searchTermSize - 1);
            it = line.find(DELIMITER_TERM);

            if (it != std::string::npos) {
                std::string packetField = line.substr(0, it);
                if (packetField == "SYNC") {
                    if (currentPacket.type != NONE) {
                        packets.push_back(currentPacket);
                    }
                    currentPacket.type = NONE;
                    currentPacket.startTime = regionStart;
                    currentPacket.ignore = false;
                } else if (packetField == "PID") {
                    if (currentPacket.type == NONE) {
                        std::string pid = line.substr(it + delimiterTermSize - 1);
                        currentPacket.type = NONE;

                        if (pid == "ACK" || pid == "NAK" || pid == "STALL" || pid == "NYET") {
                            currentPacket.type = HANDSHAKE;
                        } else if (pid == "IN") {
                            currentPacket.type = IN;
                        } else if (pid == "OUT") {
                            currentPacket.type = OUT;
                        } else if (pid == "SETUP") {
                            currentPacket.type = SETUP;
                        } else if (pid == "SOF") {
                            currentPacket.type = SOF;
                        } else if (pid.starts_with("DATA")) {
                            currentPacket.type = DATA;
                        } else {
                            std::cout << "WARNING: unknown PID: " << pid << std::endl;
                        }
                    }
                } else {
                    // They dont really care about us
                }
                currentPacket.endTime = regionEnd;
            }
        }
    }

    if (currentPacket.type != NONE) {
        packets.push_back(currentPacket);
    }
}
