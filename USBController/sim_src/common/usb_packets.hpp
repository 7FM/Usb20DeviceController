#pragma once

#include <cstdint>
#include <sstream>
#include <string>

static constexpr uint8_t createPID(int pid) {
    uint8_t out_pid = (pid & 0x0F);
    out_pid |= static_cast<uint8_t>(~out_pid) << 4;
    return out_pid;
}

typedef enum : uint8_t {
    // TOKEN: last lsb bits are 01
    PID_OUT_TOKEN = createPID(0b0001),
    PID_IN_TOKEN = createPID(0b1001),
    PID_SOF_TOKEN = createPID(0b0101),
    PID_SETUP_TOKEN = createPID(0b1101),
    // DATA: last lsb bits are 11
    PID_DATA0 = createPID(0b0011),
    PID_DATA1 = createPID(0b1011),
    PID_DATA2 = createPID(0b0111), // unused: High-speed only
    PID_MDATA = createPID(0b1111), // unused: High-speed only
    // HANDSHAKE: last lsb bits are 10
    PID_HANDSHAKE_ACK = createPID(0b0010),
    PID_HANDSHAKE_NACK = createPID(0b1010),
    PID_HANDSHAKE_STALL = createPID(0b1110),
    PID_HANDSHAKE_NYET = createPID(0b0110),
    // SPECIAL: last lsb bits are 00
    PID_SPECIAL_PRE__ERR = createPID(0b1100), // Meaning depends on context
    PID_SPECIAL_SPLIT = createPID(0b1000),    // unused: High-speed only
    PID_SPECIAL_PING = createPID(0b0100),     // unused: High-speed only
    _PID_RESERVED = createPID(0b0000)
} PID_Types;

#define STRINGIFY_CASE(x) \
    case x:               \
        return #x

std::string pidToString(PID_Types pid) {
    switch (pid) {
        STRINGIFY_CASE(PID_OUT_TOKEN);
        STRINGIFY_CASE(PID_IN_TOKEN);
        STRINGIFY_CASE(PID_SOF_TOKEN);
        STRINGIFY_CASE(PID_SETUP_TOKEN);
        STRINGIFY_CASE(PID_DATA0);
        STRINGIFY_CASE(PID_DATA1);
        STRINGIFY_CASE(PID_DATA2);
        STRINGIFY_CASE(PID_MDATA);
        STRINGIFY_CASE(PID_HANDSHAKE_ACK);
        STRINGIFY_CASE(PID_HANDSHAKE_NACK);
        STRINGIFY_CASE(PID_HANDSHAKE_STALL);
        STRINGIFY_CASE(PID_HANDSHAKE_NYET);
        STRINGIFY_CASE(PID_SPECIAL_PRE__ERR);
        STRINGIFY_CASE(PID_SPECIAL_SPLIT);
        STRINGIFY_CASE(PID_SPECIAL_PING);
        STRINGIFY_CASE(_PID_RESERVED);
        default:
            break;
    }

    std::stringstream ss;
    ss << "Unknown PID: 0x";
    ss << std::hex << static_cast<unsigned int>(pid);

    return ss.str();
}

#undef STRINGIFY_CASE

enum RequestCode : uint8_t {
    GET_STATUS = 0,
    CLEAR_FEATURE = 1,
    RESERVED_2 = 2,
    SET_FEATURE = 3,
    RESERVED_4 = 4,
    SET_ADDRESS = 5,
    GET_DESCRIPTOR = 6,
    SET_DESCRIPTOR = 7,
    GET_CONFIGURATION = 8,
    SET_CONFIGURATION = 9,
    GET_INTERFACE = 10,
    SET_INTERFACE = 11,
    SYNCH_FRAME = 12,
    IMPL_SPECIFIC_13_255 = 13
};

static constexpr uint16_t swapBytes(uint16_t input) {
    uint16_t immRes = 0;
    immRes |= input & 0x0FF;
    immRes <<= 8;
    input >>= 8;
    immRes |= input & 0x0FF;
    return immRes;
}

enum StandardDeviceRequest : uint16_t {
    DEVICE_CLEAR_FEATURE = swapBytes(0b0000'0000'0000'0000 + CLEAR_FEATURE),
    INTERFACE_CLEAR_FEATURE = swapBytes(0b0000'0001'0000'0000 + CLEAR_FEATURE),
    ENDPOINT_CLEAR_FEATURE = swapBytes(0b0000'0010'0000'0000 + CLEAR_FEATURE),

    DEVICE_SET_FEATURE = swapBytes(0b0000'0000'0000'0000 + SET_FEATURE),
    INTERFACE_SET_FEATURE = swapBytes(0b0000'0001'0000'0000 + SET_FEATURE),
    ENDPOINT_SET_FEATURE = swapBytes(0b0000'0010'0000'0000 + SET_FEATURE),

    DEVICE_GET_STATUS = swapBytes(0b1000'0000'0000'0000 + GET_STATUS),
    INTERFACE_GET_STATUS = swapBytes(0b1000'0001'0000'0000 + GET_STATUS),
    ENDPOINT_GET_STATUS = swapBytes(0b1000'0010'0000'0000 + GET_STATUS),

    INTERFACE_GET_INTERFACE = swapBytes(0b1000'0001'0000'0000 + GET_INTERFACE),
    INTERFACE_SET_INTERFACE = swapBytes(0b0000'0001'0000'0000 + SET_INTERFACE),

    ENDPOINT_SYNCH_FRAME = swapBytes(0b1000'0010'0000'0000 + SYNCH_FRAME),

    DEVICE_GET_CONFIGURATION = swapBytes(0b1000'0000'0000'0000 + GET_CONFIGURATION),
    DEVICE_SET_CONFIGURATION = swapBytes(0b0000'0000'0000'0000 + SET_CONFIGURATION),

    DEVICE_GET_DESCRIPTOR = swapBytes(0b1000'0000'0000'0000 + GET_DESCRIPTOR),
    DEVICE_SET_DESCRIPTOR = swapBytes(0b0000'0000'0000'0000 + SET_DESCRIPTOR),

    DEVICE_SET_ADDRESS = swapBytes(0b0000'0000'0000'0000 + SET_ADDRESS),
};

struct SetupPacket {
    StandardDeviceRequest request;
    uint8_t wValueLsB;
    uint8_t wValueMsB;
    uint8_t wIndexLsB;
    uint8_t wIndexMsB;
    uint8_t wLengthLsB;
    uint8_t wLengthMsB;
} __attribute__((packed));

struct TokenPacket {
    PID_Types token;
    uint16_t addr : 7;
    uint16_t endpoint : 4;
    uint16_t crc : 5;
} __attribute__((packed));
