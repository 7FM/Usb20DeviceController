#pragma once

#include <cstdint>
#include <functional>
#include <iostream>
#include <vector>

#include "common/print_utils.hpp"
#include "common/usb_descriptors.hpp"
#include "common/usb_packets.hpp"

bool getForceStop();

template <class T>
void fillVector(std::vector<uint8_t> &vec, const T &data) {
    const uint8_t *rawPtr = reinterpret_cast<const uint8_t *>(&data);
    for (int i = 0; i < sizeof(T); ++i) {
        vec.push_back(*rawPtr);
        ++rawPtr;
    }
}

template <typename Sim>
bool sendStuff(Sim &sim, std::function<void()> fillSendData) {
    // Disable receive logic
    sim.rxState.actAsNop();

    // Reset done sending flag
    sim.txState.reset();

    fillSendData();

    // Execute till stop condition
    while (!sim.template run<true>(0)) {
    }

    assert(sim.txState.doneSending);

    return getForceStop();
}

template <typename Sim>
bool receiveStuff(Sim &sim, const char *errMsg) {
    // Enable timeout for receiving a response
    sim.rxState.reset();
    sim.rxState.enableTimeout = true;

    // Disable sending logic
    sim.txState.actAsNop();

    // Execute till stop condition
    while (!sim.template run<true>(0)) {
    }

    if (sim.rxState.timedOut) {
        std::cerr << errMsg << std::endl;
        return true;
    }
    assert(sim.rxState.receivedLastByte);

    return getForceStop();
}

template <typename Sim>
class InTransaction {
    /*
    In Transaction:
    1. Send Token packet
    2. Receive Data packet / Timeout
    3. (Send Handshake)
    */
  public:
    TokenPacket inTokenPacket;
    PID_Types handshakeToken;

    bool send(Sim &sim) {
        //=========================================================================
        // 1. Send Token packet
        std::cout << "Send IN token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, inTokenPacket);
        })) return true;

        //=========================================================================
        // 2. Receive Data packet / Timeout
        std::cout << "Receive IN data!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for input data!"))
            return true;

        //=========================================================================
        // 3. (Send Handshake)
        std::cout << "Send handshake!" << std::endl;

        if (sendStuff(sim, [&] {
                sim.txState.dataToSend.push_back(handshakeToken);
            }))
            return true;

        return false;
    }
};

template <typename Sim>
class OutTransaction {
    /*
    Out Transaction:
    1. Send Token packet
    2. Send Data packet
    3. Receive Handshake / Timeout
    */
  public:
    TokenPacket outTokenPacket;
    std::vector<uint8_t> dataPacket;

    bool send(Sim &sim) {
        //=========================================================================
        // 1. Send Token packet
        std::cout << "Send OUT token!" << std::endl;

        if(sendStuff(sim, [&]{
            fillVector(sim.txState.dataToSend, outTokenPacket);
        })) return true;

        // Execute a few more cycles to give the logic some time between the packages
        sim.template run<true, false>(10);

        //=========================================================================
        // 2. Send Data packet
        std::cout << "Send OUT data!" << std::endl;

        if(sendStuff(sim, [&]{
            for (uint8_t data : dataPacket) {
                sim.txState.dataToSend.push_back(data);
            }
        })) return true;

        //=========================================================================
        // 3. Receive Handshake / Timeout
        std::cout << "Wait for response!" << std::endl;

        if (receiveStuff(sim, "Timeout waiting for a response!"))
            return true;

        return false;
    }
};

void printResponse(const std::vector<uint8_t> &response) {
    if (response.empty()) {
        std::cerr << "No response received!" << std::endl;
        return;
    }

    std::cout << "Got Response:" << std::endl;
    bool first = true;
    IosFlagSaver flagSaver(std::cout);
    for (auto data : response) {
        if (first) {
            std::cout << "    " << pidToString(static_cast<PID_Types>(data)) << std::endl;
        } else {
            std::cout << "    0x" << std::hex << static_cast<int>(data) << std::endl;
        }
        first = false;
    }
}

template <typename Sim>
bool readItAll(std::vector<uint8_t> &result, Sim &sim, int addr, int readSize, uint8_t ep0MaxDescriptorSize, uint8_t ep = 0) {
    result.clear();

    InTransaction<Sim> getDesc;
    getDesc.inTokenPacket.token = PID_IN_TOKEN;
    getDesc.inTokenPacket.addr = addr;
    getDesc.inTokenPacket.endpoint = ep;
    getDesc.inTokenPacket.crc = 0b11111; // Should be a dont care!
    getDesc.handshakeToken = PID_HANDSHAKE_ACK;

    do {
        std::cout << std::endl << "Send Input transaction packet" << std::endl;
        bool failed = getDesc.send(sim);
        printResponse(sim.rxState.receivedData);

        if (failed) {
            return true;
        }

        // Skip PID
        for (int i = 1; i < sim.rxState.receivedData.size(); ++i) {
            result.push_back(sim.rxState.receivedData[i]);
        }

        readSize -= sim.rxState.receivedData.size() - 1;

        if (sim.rxState.receivedData.size() - 1 != ep0MaxDescriptorSize && readSize > 0) {
            std::cerr << "ERROR: Received non max sized packet but still expecting data to come!" << std::endl;
            return true;
        }

    } while (readSize > 0);

    return false;
}

template <typename Sim>
bool sendItAll(const std::vector<uint8_t> &dataToSend, bool &dataToggleState, Sim &sim, int addr, int epMaxDescriptorSize, uint8_t ep = 0) {
    OutTransaction<Sim> getDesc;
    getDesc.outTokenPacket.token = PID_OUT_TOKEN;
    getDesc.outTokenPacket.addr = addr;
    getDesc.outTokenPacket.endpoint = ep;
    getDesc.outTokenPacket.crc = 0b11111; // Should be a dont care!

    int i = 0;
    int sendSize = dataToSend.size();
    int subpackets = (sendSize + epMaxDescriptorSize - 1) / epMaxDescriptorSize;
    do {
        std::cout << std::endl << "Send Output transaction packet " << (i / epMaxDescriptorSize + 1) << "/" << subpackets << std::endl;

        getDesc.dataPacket.clear();
        getDesc.dataPacket.push_back(dataToggleState ? PID_DATA1 : PID_DATA0);
        dataToggleState = !dataToggleState;
        int nextPacketSize = std::min(sendSize, epMaxDescriptorSize);
        for (int j = 0; j < nextPacketSize; ++j) {
            getDesc.dataPacket.push_back(dataToSend[i + j]);
        }
        i += nextPacketSize;

        bool failed = getDesc.send(sim);
        printResponse(sim.rxState.receivedData);
        failed |= expectHandshake(sim.rxState.receivedData, PID_HANDSHAKE_ACK);
        if (failed) {
            return true;
        }

        sendSize -= nextPacketSize;
    } while (sendSize > 0);

    return false;
}

bool expectHandshake(std::vector<uint8_t> &response, PID_Types expectedResponse) {
    if (response.size() != 1) {
        std::cerr << "Expected only a Handshake as response but got multiple bytes!" << std::endl;
        return true;
    }

    if (response[0] != expectedResponse) {
        IosFlagSaver flagSaver(std::cerr);
        std::cerr << "Expected Response: " << pidToString(expectedResponse) << " but got: " << pidToString(static_cast<PID_Types>(response[0])) << std::endl;
        return true;
    }

    return false;
}

template <typename Sim>
void updateSetupTrans(OutTransaction<Sim> &setupTrans, SetupPacket &packet) {
    setupTrans.dataPacket.clear();
    setupTrans.dataPacket.push_back(PID_DATA0);
    fillVector(setupTrans.dataPacket, packet);
}

template <typename Sim>
OutTransaction<Sim> initDescReadTrans(SetupPacket &packet, DescriptorType descType, uint8_t descIdx, uint8_t addr, uint16_t initialReadSize, StandardDeviceRequest request) {
    OutTransaction<Sim> setupTrans;
    setupTrans.outTokenPacket.token = PID_SETUP_TOKEN;
    setupTrans.outTokenPacket.addr = addr;
    setupTrans.outTokenPacket.endpoint = 0;
    setupTrans.outTokenPacket.crc = 0b11111; // Should be a dont care!

    std::memset(&packet, 0, sizeof(packet));
    // Request type
    packet.request = request;

    // Descriptor type
    packet.wValueMsB = descType;
    // Descriptor index
    packet.wValueLsB = descIdx;
    // Zero or Language ID
    packet.wIndexLsB = packet.wIndexMsB = 0;
    // First Descriptor read length: if unknown just read the first 8 bytes
    packet.wLengthLsB = initialReadSize & 0x0FF;
    packet.wLengthMsB = (initialReadSize >> 8) & 0x0FF;

    updateSetupTrans(setupTrans, packet);

    return setupTrans;
}

uint16_t defaultGetDescriptorSize(const std::vector<uint8_t> &result) {
    return result[0];
}

uint16_t getConfigurationDescriptorSize(const std::vector<uint8_t> &result) {
    return static_cast<uint16_t>(result[2]) | (static_cast<uint16_t>(result[3]) << 8);
}

template <typename Sim>
bool sendOutputStage(Sim &sim, OutTransaction<Sim> &outTrans) {
    bool failed = outTrans.send(sim);
    printResponse(sim.rxState.receivedData);
    failed |= expectHandshake(sim.rxState.receivedData, PID_HANDSHAKE_ACK);
    return failed;
}

template <typename Sim>
bool statusStage(Sim &sim, OutTransaction<Sim> &outTrans) {
    // Status stage
    outTrans.outTokenPacket.token = PID_OUT_TOKEN;
    outTrans.dataPacket.clear();
    // For the status stage always DATA1 is used
    outTrans.dataPacket.push_back(PID_DATA1);
    // An empty data packet signals that everything was successful
    std::cout << "Status stage" << std::endl;
    return sendOutputStage(sim, outTrans);
}

template <typename Sim>
bool readDescriptor(std::vector<uint8_t> &result, Sim &sim, DescriptorType descType, uint8_t descIdx, uint8_t &ep0MaxDescriptorSize, uint8_t addr, uint16_t initialReadSize, std::function<uint16_t(const std::vector<uint8_t> &)> descSizeExtractor = defaultGetDescriptorSize, StandardDeviceRequest request = DEVICE_GET_DESCRIPTOR, bool recurse = true) {
    SetupPacket packet;
    OutTransaction<Sim> setupTrans = initDescReadTrans<Sim>(packet, descType, descIdx, addr, initialReadSize, request);

    std::cout << "Setup Stage" << std::endl;
    if (sendOutputStage(sim, setupTrans)) {
        return true;
    }

    std::cout << "Data Stage" << std::endl;
    bool failed = readItAll(result, sim, addr, initialReadSize, ep0MaxDescriptorSize == 0 ? 8 : ep0MaxDescriptorSize);

    if (result.size() != initialReadSize) {
        std::cerr << "Error: Desired to read first " << static_cast<int>(initialReadSize) << " bytes of the descriptor but got only: " << result.size() << " bytes!" << std::endl;
        failed = true;
    }

    if (failed) {
        return true;
    }

    if (result.size() == 0 && initialReadSize == 0) {
        // Zero length data phase -> ACK
        std::cout << "Received a zero length data phase and is interpret as an ACK!" << std::endl;
        return false;
    }

    uint16_t descriptorSize = descSizeExtractor(result);

    if (descType == DESC_DEVICE) {
        ep0MaxDescriptorSize = result[7];
        std::cout << "INFO: update EP0 Max packet size to: " << static_cast<int>(ep0MaxDescriptorSize) << std::endl;
    }

    // Status stage
    if (statusStage(sim, setupTrans)) {
        return true;
    }

    if (descriptorSize < initialReadSize) {
        std::cerr << "Error extracting the descriptor size: extracted " << static_cast<int>(descriptorSize) << " but expecting a size of at least " << static_cast<int>(initialReadSize) << std::endl;
        return true;
    } else if (descriptorSize > initialReadSize) {
        if (!recurse) {
            std::cerr << "No further read attempts are permitted, reading entire descriptor failed!" << std::endl;
            return true;
        }

        // Recursion to issue a new request! BUT this time with the correct initalReadSize set!
        // ALSO: further recursions will be disabled to ensure termination!
        return readDescriptor(result, sim, descType, descIdx, ep0MaxDescriptorSize, addr, descriptorSize, descSizeExtractor, request, false);
    }

    std::cout << "Successfully received a " << descTypeToString(descType) << " Descriptor!" << std::endl;

    return false;
}

template <typename Sim>
bool sendValueSetRequest(Sim &sim, StandardDeviceRequest request, uint16_t wValue, uint8_t &ep0MaxDescriptorSize, uint8_t addr, uint16_t initialReadSize) {
    std::vector<uint8_t> dummyRes;
    return readDescriptor(dummyRes, sim, static_cast<DescriptorType>((wValue >> 8) & 0x0FF), static_cast<uint8_t>((wValue >> 0) & 0x0FF), ep0MaxDescriptorSize, addr, initialReadSize, defaultGetDescriptorSize, request);
}
