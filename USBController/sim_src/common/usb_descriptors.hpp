#pragma once

#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>

#include <vector>

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

struct DeviceQualifierDescriptor {
    uint8_t bLength;
    DescriptorType bDescriptorType;

    uint16_t bcdUsb;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;

    uint8_t bNumConfigurations;
    uint8_t bReserved;
} __attribute__((packed));

struct ConfigurationDescriptor {
    uint8_t bLength;
    DescriptorType bDescriptorType;

    uint16_t wTotalLength;
    uint8_t bNumInterfaces;
    uint8_t bConfigurationValue;
    uint8_t iConfiguration;
    uint8_t bmAttributes;

    uint8_t bMaxPower;
} __attribute__((packed));

struct InterfaceDescriptor {
    uint8_t bLength;
    DescriptorType bDescriptorType;

    uint8_t bInterfaceNumber;
    uint8_t bAlternateSetting;
    uint8_t bNumEndpoints;

    uint8_t bInterfaceClass;
    uint8_t bInterfaceSubClass;
    uint8_t bInterfaceProtocol;

    uint8_t iInterface;
} __attribute__((packed));

struct EndpointDescriptor {
    uint8_t bLength;
    DescriptorType bDescriptorType;

    uint8_t bEndpointAddress;
    uint8_t bmAttributes;

    uint16_t wMaxPacketSize;
    uint8_t bInterval;
} __attribute__((packed));

void prettyPrintBcd(uint16_t bcd) {
    int fractionPos = 2;

    IosFlagSaver flagSaver(std::cout);

    for (int shift = sizeof(bcd) * 8 - 4; shift >= 0; shift -= 4, --fractionPos) {
        int literal = (bcd >> shift) & 0x0F;
        std::cout << std::hex << literal;

        if (fractionPos == 1) {
            std::cout << '.';
        }
    }

    std::cout << std::endl;
}

template <class Desc>
static void fillDesc(Desc &desc, const uint8_t *data) {
    std::memset(&desc, 0, sizeof(desc));
    uint8_t *rawDevDesc = reinterpret_cast<uint8_t *>(&desc);
    for (int i = 0; i < sizeof(desc); ++i) {
        *rawDevDesc = data[i];
        ++rawDevDesc;
    }
}

static void prettyPrintDeviceDescriptor(const uint8_t *data) {

    DeviceDescriptor devDesc;
    fillDesc(devDesc, data);

    std::cout << "    bLength: " << static_cast<int>(devDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(devDesc.bDescriptorType) << std::endl;
    std::cout << "    Usb Version: ";
    prettyPrintBcd(devDesc.bcdUsb);
    std::cout << "    EP0 Max Packet Size: " << static_cast<int>(devDesc.bMaxPacketSize0) << std::endl;
    std::cout << "    BCD Device: ";
    prettyPrintBcd(devDesc.bcdDevice);
    std::cout << "    #Configurations: " << static_cast<int>(devDesc.bNumConfigurations) << std::endl;
}

static void prettyPrintDeviceQualifierDescriptor(const uint8_t *data) {

    DeviceQualifierDescriptor devDesc;
    fillDesc(devDesc, data);

    std::cout << "    bLength: " << static_cast<int>(devDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(devDesc.bDescriptorType) << std::endl;
    std::cout << "    Usb Version: ";
    prettyPrintBcd(devDesc.bcdUsb);
    std::cout << "    EP0 Max Packet Size: " << static_cast<int>(devDesc.bMaxPacketSize0) << std::endl;
    std::cout << "    #Configurations: " << static_cast<int>(devDesc.bNumConfigurations) << std::endl;
}

static void prettyPrintConfigurationDescriptor(const uint8_t *data) {

    ConfigurationDescriptor confDesc;
    fillDesc(confDesc, data);

    IosFlagSaver flagSaver(std::cout);

    std::cout << "    bLength: " << static_cast<int>(confDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(confDesc.bDescriptorType) << std::endl;
    std::cout << "    Config Value: " << static_cast<int>(confDesc.bConfigurationValue) << std::endl;
    std::cout << "    Total Length: " << static_cast<int>(confDesc.wTotalLength) << std::endl;
    std::cout << "    Num Interfaces: " << static_cast<int>(confDesc.bNumInterfaces) << std::endl;
    std::cout << "    Max Power: " << static_cast<int>(confDesc.bMaxPower) << "mA" << std::endl;

    //TODO pretty print
    std::cout << "    Attributes: 0x" << std::hex << static_cast<int>(confDesc.bmAttributes) << std::endl;
}

static void prettyPrintInterfaceDescriptor(const uint8_t *data) {

    InterfaceDescriptor ifaceDesc;
    fillDesc(ifaceDesc, data);

    std::cout << "    bLength: " << static_cast<int>(ifaceDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(ifaceDesc.bDescriptorType) << std::endl;
    std::cout << "    Iface Number: " << static_cast<int>(ifaceDesc.bInterfaceNumber) << std::endl;
    std::cout << "    Alternate Setting: " << static_cast<int>(ifaceDesc.bAlternateSetting) << std::endl;
    std::cout << "    #Endpoints: " << static_cast<int>(ifaceDesc.bNumEndpoints) << std::endl;
}

static void prettyPrintEndpointDescriptor(const uint8_t *data) {

    EndpointDescriptor epDesc;
    fillDesc(epDesc, data);

    IosFlagSaver flagSaver(std::cout);

    std::cout << "    bLength: " << static_cast<int>(epDesc.bLength) << std::endl;
    std::cout << "    Descriptor Type: " << descTypeToString(epDesc.bDescriptorType) << std::endl;
    bool input = ((epDesc.bEndpointAddress >> 7) & 1) == 1;
    std::cout << "    EP Type: " << (input ? "INPUT" : "OUTPUT") << std::endl;
    std::cout << "    EP Address: " << static_cast<int>(epDesc.bEndpointAddress & 0x0F) << std::endl;
    std::cout << "    Max Packet Size: " << static_cast<int>(epDesc.wMaxPacketSize & 0x7FF) << std::endl;
    std::cout << "    Additional transactions per microframe: " << static_cast<int>((epDesc.wMaxPacketSize >> 11) & 0x3) << std::endl;

    //TODO epDesc.bInterval
    //TODO pretty print
    std::cout << "    Attributes: 0x" << std::hex << static_cast<int>(epDesc.bmAttributes) << std::endl;
}

static void prettyPrintStringDescriptor(const uint8_t *data) {
    uint8_t descLength = *data;

    descLength -= 2;
    data += 2;

    std::cout << "    Content: ";
    for (int i = 0; i < descLength; ++i) {
        std::cout << *reinterpret_cast<const char *>(data);
        ++data;
    }
    std::cout << std::endl;
}

void prettyPrintDescriptors(const std::vector<uint8_t> &data) {

    for (int i = 0; i + 1 < data.size();) {
        uint8_t descLength = data[i];
        DescriptorType descType = static_cast<DescriptorType>(data[i + 1]);

        std::cout << "Found Descriptor " << descTypeToString(descType) << " at offset " << i << std::endl;
        if (i + descLength <= data.size()) {
            const uint8_t *descData = data.data() + i;
            switch (descType) {
                case DESC_DEVICE:
                    prettyPrintDeviceDescriptor(descData);
                    break;
                case DESC_CONFIGURATION:
                    prettyPrintConfigurationDescriptor(descData);
                    break;
                case DESC_STRING:
                    prettyPrintStringDescriptor(descData);
                    break;
                case DESC_INTERFACE:
                    prettyPrintInterfaceDescriptor(descData);
                    break;
                case DESC_ENDPOINT:
                    prettyPrintEndpointDescriptor(descData);
                    break;
                case DESC_DEVICE_QUALIFIER:
                    prettyPrintDeviceQualifierDescriptor(descData);
                    break;
                case DESC_OTHER_SPEED_CONFIGURATION:
                    prettyPrintConfigurationDescriptor(descData);
                    break;
                case DESC_INTERFACE_POWER:
                    std::cout << "Not yet implemented" << std::endl;
                    break;

                case IMPL_SPECIFIC_9_255:
                default:
                    std::cout << "Warning cannot pretty print implementation specific descriptor: " << static_cast<int>(descType) << std::endl;
                    break;
            }
        } else {
            std::cerr << "Error, not enough data to print last descriptor: " << descTypeToString(descType) << std::endl;
        }

        std::cout << std::endl;

        if (descLength == 0) {
            std::cerr << "ERROR: invalid descriptor length of 0!" << std::endl;
            return;
        }

        i += descLength;
    }
}