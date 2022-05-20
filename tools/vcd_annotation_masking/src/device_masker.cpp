#include "device_masker.hpp"

#include <cassert>
#include <iostream>

enum Transaction {
    NO_TRANS,
    SETUP_TRANS,
    IN_TRANS,
    OUT_TRANS,
};

void maskDevicePackets(std::vector<Packet> &packets) {
    Transaction ongoingTrans = NO_TRANS;
    for (decltype(packets.size()) i = 0; i < packets.size(); ++i) {
        auto &p = packets[i];
        switch (p.type) {
            case SOF: {
                p.ignore = false;
                ongoingTrans = NO_TRANS;
                break;
            }
            case SETUP: {
                p.ignore = false;
                if (ongoingTrans != NO_TRANS) {
                    std::cout << "SETUP: prev failed Trans: " << ongoingTrans;
                    std::cout << " at: " << i << std::endl;
                }
                ongoingTrans = SETUP_TRANS; // TODO can we use OUT_TRANS here?
                break;
            }
            case IN: {
                p.ignore = false;
                if (ongoingTrans != NO_TRANS) {
                    std::cout << "IN: prev failed Trans: " << ongoingTrans;
                    std::cout << " at: " << i << std::endl;
                }
                ongoingTrans = IN_TRANS;
                break;
            }
            case OUT: {
                p.ignore = false;
                if (ongoingTrans != NO_TRANS) {
                    std::cout << "OUT: prev failed Trans: " << ongoingTrans;
                    std::cout << " at: " << i << std::endl;
                }
                ongoingTrans = OUT_TRANS;
                break;
            }
            case DATA: {
                assert(ongoingTrans != NO_TRANS);
                p.ignore = ongoingTrans == IN_TRANS;
                break;
            }
            case HANDSHAKE: {
                assert(ongoingTrans != NO_TRANS);
                p.ignore =
                    ongoingTrans == OUT_TRANS || ongoingTrans == SETUP_TRANS;
                // clear on going trans
                ongoingTrans = NO_TRANS;
                break;
            }
            case NONE:
            default: {
                std::cout << "Error: I cant distinguish the host packets from "
                             "the device packets at index: "
                          << i << std::endl;
                return;
            }
        }
    }
}
