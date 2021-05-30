#include "common/usb_utils.hpp"

#include <bitset>
#include <iostream>
#include <vector>

int main() {

    {
        std::vector<uint8_t> bytes(2);

        for (int i = 0; i < 256; ++i) {
            for (int j = 0; j < 256; ++j) {
                bytes[0] = i;
                bytes[1] = j;
                uint16_t crc = calculateDataCRC(CRC_Type::CRC16, bytes, bytes.size());

                // We are only intereseted in the last 7 bit
                crc >>= 9;
                // We desire first a zero bit followed by 6 ones to ensure that the after the crc 1 bit is stuffed!
                if (crc == 0b11'1111'0) {
                    std::cout << "Found 2 byte example for the CRC Bitstuffing Edge Case!" << std::endl;
                    std::cout << "Byte 0: " << std::hex << static_cast<uint32_t>(bytes[0]) << std::endl;
                    std::cout << "Byte 1: " << std::hex << static_cast<uint32_t>(bytes[1]) << std::endl;
                }
            }
        }
    }

    {
        std::vector<uint8_t> bytes(1);

        for (int i = 0; i < 256; ++i) {
            bytes[0] = i;
            uint16_t crc = calculateDataCRC(CRC_Type::CRC16, bytes, bytes.size());

            // We are only intereseted in the last 7 bit
            crc >>= 9;
            // We desire first a zero bit followed by 6 ones to ensure that the after the crc 1 bit is stuffed!
            if (crc == 0b11'1111'0) {
                std::cout << "Found 1 byte example for the CRC Bitstuffing Edge Case!" << std::endl;
                std::cout << "Byte 0: " << std::hex << static_cast<uint32_t>(bytes[0]) << std::endl;
            }
        }
    }

    std::cout << "Found edge case example CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0x0), static_cast<uint8_t>(0xB9)>(CRC_Type::CRC16)) << std::endl;
    std::cout << "Found edge case example CRC: " << std::bitset<16>(constExprCRC<static_cast<uint8_t>(0xF9)>(CRC_Type::CRC16)) << std::endl;

    return 0;
}