#pragma once

#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>
#include <array>

#define BIT_STUFF_AFTER_X_ONES 6

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

typedef enum {
    NO_CRC,
    CRC5,
    CRC16,
    CRC_INVALID
} CRC_Type;

template <std::size_t N>
struct USBSignal {
    constexpr USBSignal() : dp(), dn() {}

    static constexpr std::size_t size = N;
    uint8_t dp[N];
    uint8_t dn[N];
};

constexpr CRC_Type getCRCTypeFromPID(PID_Types pid, bool allowInvalid = false) {
    switch (pid) {
        case PID_OUT_TOKEN:
        case PID_IN_TOKEN:
        case PID_SOF_TOKEN:
        case PID_SETUP_TOKEN:
            return CRC5;
        case PID_DATA0:
        case PID_DATA1:
        case PID_DATA2:
        case PID_MDATA:
            return CRC16;
        case PID_HANDSHAKE_ACK:
        case PID_HANDSHAKE_NACK:
        case PID_HANDSHAKE_STALL:
        case PID_HANDSHAKE_NYET:
            return NO_CRC;
        case PID_SPECIAL_PRE__ERR:
            // PRE can only be send from host and is a token type
            //return CRC5;
            // ERR is a handshake for a Slit transaction
            return NO_CRC;
        case PID_SPECIAL_SPLIT:
            return CRC5;
        case PID_SPECIAL_PING:
            return CRC5;
        case _PID_RESERVED:
            return CRC_INVALID;
        default:
            if (!allowInvalid) {
                throw std::invalid_argument("Unknown PID");
            }
            break;
    }

    return CRC_INVALID;
}

#define CALCULATE_CRC_FUN_BODY()                                                            \
    constexpr uint16_t crc5_polynom = 0b0'0101;                                             \
    constexpr uint16_t crc16_polynom = 0b1000'0000'0000'0101;                               \
    constexpr uint16_t crc5_residual = 0b0'1100;                                            \
    /*constexpr uint16_t crc16_residual = 0b1000'0000'0000'1101;*/                          \
                                                                                            \
    if (crcType != CRC5 && crcType != CRC16) {                                              \
        return crc5_residual;                                                               \
    }                                                                                       \
                                                                                            \
    if (initCRC) {                                                                          \
        return static_cast<uint16_t>(-1);                                                   \
    }                                                                                       \
                                                                                            \
    const uint8_t shiftAmount = crcType == CRC16 ? 15 : 4;                                  \
    const uint16_t crc_polynom = crcType == CRC16 ? crc16_polynom : crc5_polynom;           \
                                                                                            \
    for (int i = 0; i < sizeof(T) && bitsInData > 0; ++i, bitsInData -= 8) {                \
        uint8_t d = static_cast<uint8_t>((data >> (i * 8)) & 0x0FF);                        \
                                                                                            \
        for (int j = (bitsInData > 8 ? 8 : bitsInData); j > 0; --j, d >>= 1) {              \
            uint16_t dataInBit = (d & 1) ^ ((crcState >> shiftAmount) & 1);                 \
            crcState <<= 1;                                                                 \
                                                                                            \
            if (dataInBit == 1) {                                                           \
                crcState ^= crc_polynom;                                                    \
            }                                                                               \
        }                                                                                   \
    }                                                                                       \
                                                                                            \
    /* Ensure that only as many bits are used as needed for the chosen CRC*/                \
    crcState &= static_cast<uint16_t>((static_cast<uint32_t>(1) << (shiftAmount + 1)) - 1); \
                                                                                            \
    return crcState

template <typename T>
static uint16_t calculateCRC(bool initCRC, uint16_t crcState, CRC_Type crcType, const T data, int bitsInData) {
    CALCULATE_CRC_FUN_BODY();
}

template <typename T>
static constexpr uint16_t calculateCRC_constExpr(bool initCRC, uint16_t crcState, CRC_Type crcType, const T data, int bitsInData) {
    CALCULATE_CRC_FUN_BODY();
}

#define NEEDS_BIT_STUFFING_FUN_BODY()               \
    if (dataBit == 1) {                             \
        ++oneCounter;                               \
        if (oneCounter >= BIT_STUFF_AFTER_X_ONES) { \
            oneCounter = 0;                         \
            return true;                            \
        }                                           \
    } else {                                        \
        oneCounter = 0;                             \
    }                                               \
    return false

bool needsBitStuffing(uint8_t &oneCounter, uint8_t dataBit) {
    NEEDS_BIT_STUFFING_FUN_BODY();
}

constexpr bool needsBitStuffing_constExpr(uint8_t &oneCounter, uint8_t dataBit) {
    NEEDS_BIT_STUFFING_FUN_BODY();
}

template <uint8_t... dataBytes>
static constexpr int requiredBitStuffings() {
    int requiredBitStuffing = 0;
    uint8_t ones = 0;

    for (uint8_t data : {dataBytes...}) {
        for (int i = 0; i < sizeof(data) * 8; ++i) {

            if (needsBitStuffing_constExpr(ones, data & 1)) {
                ++requiredBitStuffing;
            }

            // Next data bit
            data >>= 1;
        }
    }

    return requiredBitStuffing;
}

template <uint8_t... dataBytes>
constexpr uint16_t constExprCRC(CRC_Type crcType);

#define CRC_HELPER_FUN_BODY(crcFunName)                                                  \
    uint16_t crcState = 0;                                                               \
    crcState = crcFunName<uint8_t>(true, crcState, crcType, static_cast<uint8_t>(0), 8); \
                                                                                         \
    int dataIdx = 0;                                                                     \
    int lastDataBitCount = crcType == CRC5 ? 3 : 8;                                      \
                                                                                         \
    for (uint8_t data : bytes) {                                                         \
        int bitsInData = dataIdx < byteCount - 1 ? sizeof(data) * 8 : lastDataBitCount;  \
                                                                                         \
        crcState = crcFunName<uint8_t>(false, crcState, crcType, data, bitsInData);      \
        ++dataIdx;                                                                       \
    }                                                                                    \
                                                                                         \
    crcState = ~crcState;                                                                \
    uint16_t correctlyEncodedCRC = 0;                                                    \
                                                                                         \
    for (int i = crcType == CRC5 ? 5 : (crcType == CRC16 ? 16 : 0); i > 0; --i) {        \
        correctlyEncodedCRC <<= 1;                                                       \
        correctlyEncodedCRC |= crcState & 1;                                             \
        crcState >>= 1;                                                                  \
    }                                                                                    \
                                                                                         \
    return correctlyEncodedCRC

template <class Bytes>
uint16_t calculateDataCRC(CRC_Type crcType, Bytes bytes, int byteCount) {
    CRC_HELPER_FUN_BODY(calculateCRC);
}

template <class Bytes>
static constexpr uint16_t constExprCRC_helper(CRC_Type crcType, Bytes bytes, int byteCount) {
    CRC_HELPER_FUN_BODY(calculateCRC_constExpr);
}

template <uint8_t... dataBytes>
constexpr uint16_t constExprCRC(CRC_Type crcType) {
    return constExprCRC_helper<std::initializer_list<uint8_t>>(crcType, {dataBytes...}, sizeof...(dataBytes));
}

template <>
constexpr uint16_t constExprCRC<>(CRC_Type crcType) {
    return 0;
}

#define APPLY_NRZI_ENCODE_FUN_BODY()                     \
    /* XNOR first bit*/                                  \
    nrziEncoderState = 1 ^ (nrziEncoderState ^ dataBit); \
                                                         \
    *dp = nrziEncoderState;                              \
    *dn = 1 ^ nrziEncoderState

/*
static void applyNrziEncode(uint8_t &nrziEncoderState, uint8_t dataBit, uint8_t *dp, uint8_t *dn) {
    APPLY_NRZI_ENCODE_FUN_BODY();
}
*/

static constexpr void applyNrziEncode_constExpr(uint8_t &nrziEncoderState, uint8_t dataBit, uint8_t *dp, uint8_t *dn) {
    APPLY_NRZI_ENCODE_FUN_BODY();
}

// Source: https://stackoverflow.com/questions/5438671/static-assert-on-initializer-listsize
template <bool considerCRC, uint8_t pid, uint8_t... dataBytes>
constexpr auto nrziEncode(uint8_t initialOneCount = 1, uint8_t encoderStartState = 0) {
    constexpr CRC_Type crcType = considerCRC ? getCRCTypeFromPID(static_cast<PID_Types>(pid), considerCRC) : CRC_INVALID;
    constexpr int crcBits = crcType == CRC5 ? 5 : (crcType == CRC16 ? 16 : 0);
    constexpr int lastDataBitCount = crcType == CRC5 ? 3 : 8;
    constexpr uint16_t crc = constExprCRC<dataBytes...>(crcType);

    USBSignal<crcBits + lastDataBitCount + sizeof...(dataBytes) * 8 + requiredBitStuffings<pid, dataBytes..., static_cast<uint8_t>(crc & 0x0FF), static_cast<uint8_t>((crc >> 8) & 0x0FF)>()> signal;
    int signalIdx = 0;

    uint8_t bitStuffingOneCounter = initialOneCount;
    uint8_t nrziEncoderState = encoderStartState;

    int dataIdx = 0;
    for (uint8_t data : {pid, dataBytes...}) {
        int bitsInData = dataIdx != sizeof...(dataBytes) - 1 ? sizeof(data) * 8 : lastDataBitCount;

        for (int i = bitsInData; i > 0; --i, ++signalIdx) {

            uint8_t dataBit = data & 1;
            // Next data bit
            data >>= 1;

            applyNrziEncode_constExpr(nrziEncoderState, dataBit, signal.dp + signalIdx, signal.dn + signalIdx);

            if (needsBitStuffing_constExpr(bitStuffingOneCounter, dataBit)) {
                // If the allowed amount of consecutive one's are exceeded a 0 needs to be stuffed into the signal!
                ++signalIdx;
                applyNrziEncode_constExpr(nrziEncoderState, 0, signal.dp + signalIdx, signal.dn + signalIdx);
            }
        }
        ++dataIdx;
    }

    uint16_t crcCopy = crc;
    for (int crcBitsCopy = crcBits; crcBitsCopy > 0; --crcBitsCopy, ++signalIdx) {
        uint8_t dataBit = crcCopy & 1;
        // Next data bit
        crcCopy >>= 1;

        applyNrziEncode_constExpr(nrziEncoderState, dataBit, signal.dp + signalIdx, signal.dn + signalIdx);

        if (needsBitStuffing_constExpr(bitStuffingOneCounter, dataBit)) {
            // If the allowed amount of consecutive one's are exceeded a 0 needs to be stuffed into the signal!
            ++signalIdx;
            applyNrziEncode_constExpr(nrziEncoderState, 0, signal.dp + signalIdx, signal.dn + signalIdx);
        }
    }

    return signal;
}

template <class... SignalPart>
static constexpr int determineSignalLength() {
    return (0 + ... + SignalPart::size);
}

template <class SignalPart, std::size_t N>
static constexpr void constructSignalHelper(const SignalPart &signalPart, int &idx, std::array<uint8_t, N> &storage) {
    for (int j = 0; j < signalPart.size; ++j) {
        storage[idx++] = signalPart.dp[j];
        storage[idx++] = signalPart.dn[j];
    }
}

template <class... SignalPart>
constexpr auto constructSignal(const SignalPart &...signalParts) {
    std::array<uint8_t, determineSignalLength<SignalPart...>() * 2> signal{};

    int i = 0;
    (constructSignalHelper(signalParts, i, signal), ...);

    return signal;
}

static constexpr auto createEOPSignal() {
    USBSignal<3> signal;

    signal.dp[0] = signal.dn[0] = signal.dp[1] = signal.dn[1] = 0;
    signal.dp[2] = 1;
    signal.dn[2] = 0;

    return signal;
}

constexpr auto usbSyncSignal = nrziEncode<false, static_cast<uint8_t>(0b1000'0000)>(0, 1);
constexpr auto usbEOPSignal = createEOPSignal();

typedef struct {
    std::vector<uint8_t> receivedData;
    bool receivedLastByte = false;
    bool keepPacket = false;
    uint8_t delayedDataAccept = 0;
    const uint8_t acceptAfterXAvailableCycles = 5;

    void reset() {
        receivedData.clear();
        receivedLastByte = false;
        keepPacket = false;
        delayedDataAccept = 0;
    }
} UsbReceiveState;

template <typename T>
void receiveDeserializedInput(T ptop, UsbReceiveState &usbRxState) {
    if (ptop->rxAcceptNewData && ptop->rxDataValid) {
        usbRxState.receivedData.push_back(ptop->rxData);

        if (ptop->rxIsLastByte) {
            if (usbRxState.receivedLastByte) {
                std::cerr << "Error: received bytes after last signal was set!" << std::endl;
            } else {
                usbRxState.keepPacket = ptop->keepPacket;
                std::cout << "Received last byte! Overall packet size: " << usbRxState.receivedData.size() << std::endl;
                std::cout << "Usb RX module keepPacket: " << usbRxState.keepPacket << std::endl;
            }
            usbRxState.receivedLastByte = true;
        }

        ptop->rxAcceptNewData = 0;
        usbRxState.delayedDataAccept = 0;
    } else {
        if (ptop->rxDataValid) {
            // New data is available but wait for x cycles before accepting!
            if (usbRxState.acceptAfterXAvailableCycles == usbRxState.delayedDataAccept) {
                ptop->rxAcceptNewData = 1;
            }

            ++usbRxState.delayedDataAccept;
        }
    }
}

typedef struct {
    std::vector<uint8_t> dataToSend;
    std::size_t transmitIdx = 0;
    bool requestedSendPacket = false;

    void reset() {
        dataToSend.clear();
        transmitIdx = 0;
        requestedSendPacket = false;
    }
} UsbTransmitState;

template <typename T>
void feedTransmitSerializer(T ptop, UsbTransmitState &usbTxState) {
    if (usbTxState.requestedSendPacket) {
        ptop->txIsLastByte = usbTxState.transmitIdx == usbTxState.dataToSend.size() - 1 ? 1 : 0;
        if (usbTxState.transmitIdx < usbTxState.dataToSend.size()) {
            ptop->txData = usbTxState.dataToSend[usbTxState.transmitIdx];
        }

        if (ptop->txAcceptNewData) {
            if (ptop->txDataValid) {
                // clear send packet request, once send data is requested
                // else we might trigger several packet sends which is illegal
                ptop->txReqSendPacket = 0;

                // Triggered Handshake!
                ptop->txDataValid = 0;
                // Update index of data that should be send!
                ++usbTxState.transmitIdx;
            } else {
                // Only signal data is valid if there is still data left to send!
                if (usbTxState.transmitIdx < usbTxState.dataToSend.size()) {
                    // Data was requested but not yet signaled that txData is valid, lets change the later
                    ptop->txDataValid = 1;
                }
            }
        }
    } else {
        // Start send packet request
        usbTxState.requestedSendPacket = true;
        ptop->txReqSendPacket = 1;
    }
}
