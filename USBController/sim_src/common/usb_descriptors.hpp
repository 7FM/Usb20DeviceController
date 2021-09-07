#pragma once

#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>

#include "common/print_utils.hpp"

enum DescriptorType : uint8_t {
    DESC_DEVICE = 1,
    DESC_CONFIGURATION = 2,
    DESC_STRING = 3,
    DESC_INTERFACE = 4,
    DESC_ENDPOINT = 5,
    DESC_DEVICE_QUALIFIER = 6,
    DESC_OTHER_SPEED_CONFIGURATION = 7,
    DESC_INTERFACE_POWER = 8, // described in the USB Interface Power Management Specification
    IMPL_SPECIFIC_9_255 = 9
};

#define STRINGIFY_CASE(x) \
    case x:               \
        return #x

std::string descTypeToString(DescriptorType descType) {
    switch (descType) {
        STRINGIFY_CASE(DESC_DEVICE);
        STRINGIFY_CASE(DESC_CONFIGURATION);
        STRINGIFY_CASE(DESC_STRING);
        STRINGIFY_CASE(DESC_INTERFACE);
        STRINGIFY_CASE(DESC_ENDPOINT);
        STRINGIFY_CASE(DESC_DEVICE_QUALIFIER);
        STRINGIFY_CASE(DESC_OTHER_SPEED_CONFIGURATION);
        STRINGIFY_CASE(DESC_INTERFACE_POWER);
        default:
            if (descType >= IMPL_SPECIFIC_9_255) {
                return "IMPLEMENTATION SPECIFIC";
            }
            break;
    }

    std::stringstream ss;
    ss << "Unknown PID: 0x";
    ss << std::hex << static_cast<unsigned int>(descType);

    return ss.str();
}

#undef STRINGIFY_CASE

struct DeviceDescriptor {
    uint8_t bLength;
    DescriptorType bDescriptorType;
    uint16_t bcdUsb;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;

    uint16_t idVendor;
    uint16_t idProduct;
    uint16_t bcdDevice;
    uint8_t iManufacturer;
    uint8_t iProduct;
    uint8_t iSerialNumber;

    uint8_t bNumConfigurations;
} __attribute__((packed));

void prettyPrintBcd(uint16_t bcd) {
    int fractionPos = 2;

    IosFlagSaver flagSaver(std::cout);

    for (int shift = sizeof(bcd) * 8 - 4; shift > 0; shift -= 4, --fractionPos) {
        int literal = (bcd >> shift) & 0x0F;
        std::cout << std::hex << literal;

        if (fractionPos == 1) {
            std::cout << '.';
        }
    }

    std::cout << std::endl;
}

void prettyPrintDeviceDescriptor(const DeviceDescriptor& devDesc) {
    std::cout << "    bLength: " << static_cast<int>(devDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(devDesc.bDescriptorType) << std::endl;
    std::cout << "    Usb Version: ";
    prettyPrintBcd(devDesc.bcdUsb);
    std::cout << "    EP0 Max Packet Size: " << static_cast<int>(devDesc.bMaxPacketSize0) << std::endl;
    std::cout << "    BCD Device: ";
    prettyPrintBcd(devDesc.bcdDevice);
    std::cout << "    #Configurations: " << static_cast<int>(devDesc.bNumConfigurations) << std::endl;
}
