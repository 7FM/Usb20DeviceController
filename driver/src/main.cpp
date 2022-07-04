#include <libusb.h>

#include <cstdint>
#include <cstdio>
#include <iostream>
#include <memory>
#include <vector>

// hardcoded paths... I dont like it
#include "../../USBController/sim_src/common/print_utils.hpp"

// Future versions of libusb will use usb_interface instead of interface
// in libusb_config_descriptor => catter for that
#define usb_interface interface

class LibUsbDeviceHandleRAII {
  public:
    LibUsbDeviceHandleRAII(uint16_t vid, uint16_t pid) : handle(libusb_open_device_with_vid_pid(NULL, vid, pid)) {
    }

    ~LibUsbDeviceHandleRAII() {
        if (isValid()) {
            libusb_close(handle);
        }
    }

    bool isValid() const {
        return handle != NULL;
    }

    libusb_device_handle *const handle;
};

static int test_device(uint16_t vid, uint16_t pid) {

    LibUsbDeviceHandleRAII deviceHandle(vid, pid);

    std::printf("Opening device %04X:%04X...\n", vid, pid);
    libusb_device_handle *const handle = deviceHandle.handle;

    if (!deviceHandle.isValid()) {
        std::cout << "  Failed." << std::endl;
        return -1;
    }

    libusb_device *dev = libusb_get_device(handle);

    std::cout << "Reading first configuration descriptor." << std::endl;
    struct libusb_config_descriptor *conf_desc;
    int res = libusb_get_config_descriptor(dev, 0, &conf_desc);
    if (res != LIBUSB_SUCCESS) {
        std::printf("   %s\n", libusb_strerror(static_cast<libusb_error>(res)));
        return -1;
    }
    const int nb_ifaces = conf_desc->bNumInterfaces;
    libusb_free_config_descriptor(conf_desc);

    libusb_set_auto_detach_kernel_driver(handle, 1);
    for (int iface = 0; iface < nb_ifaces; iface++) {
        int ret = libusb_kernel_driver_active(handle, iface);
        std::printf("\nKernel driver attached for interface %d: %d\n", iface, ret);
        std::printf("\nClaiming interface %d...\n", iface);
        int res = libusb_claim_interface(handle, iface);
        if (res != LIBUSB_SUCCESS) {
            std::cout << "   Failed." << std::endl;
        }
    }

    // Test the echoing behaviour!
    std::vector<uint8_t> sendData;
    for (int i = 0; i < 512; ++i) {
        sendData.push_back(i);
    }
    int transferred = -1;
    int timeout = 20;
    res = libusb_bulk_transfer(handle,
                               LIBUSB_ENDPOINT_OUT | 1 /* host -> endpoint 1 */,
                               sendData.data(),
                               sendData.size(),
                               &transferred,
                               timeout);
    if (sendData.size() != static_cast<std::vector<uint8_t>::size_type>(transferred)) {
        std::cout << "ERROR: less data was sent than requested!" << std::endl;
        std::cout << "    Expected: " << sendData.size() << " but got: " << transferred << std::endl;
    }
    if (res != LIBUSB_SUCCESS) {
        std::cout << "Bulk transfer to EP1 failed!" << std::endl;
        std::printf("   %s\n", libusb_strerror(static_cast<libusb_error>(res)));
    } else {
        std::vector<uint8_t> receiveData;
        receiveData.resize(transferred);

        res = libusb_bulk_transfer(handle,
                                   LIBUSB_ENDPOINT_IN | 1 /* endpoint 1 -> host */,
                                   receiveData.data(),
                                   receiveData.size(),
                                   &transferred,
                                   timeout);

        if (receiveData.size() != static_cast<std::vector<uint8_t>::size_type>(transferred)) {
            std::cout << "ERROR: less data was received than expected!" << std::endl;
            std::cout << "    Expected: " << receiveData.size() << " but got: " << transferred << std::endl;
            receiveData.resize(transferred);
        }

        if (res != LIBUSB_SUCCESS) {
            std::cout << "Bulk transfer to EP1 failed!" << std::endl;
            std::printf("   %s\n", libusb_strerror(static_cast<libusb_error>(res)));
        } else {
            if (!compareVec(sendData, receiveData, "Echo length mismatch!", "Echo data mismatch!")) {
                std::cout << "Successfully checked the echo functionality!" << std::endl;
            }
        }
    }

    std::cout << std::endl;
    for (int iface = 0; iface < nb_ifaces; iface++) {
        std::printf("Releasing interface %d...\n", iface);
        libusb_release_interface(handle, iface);
    }

    std::cout << "Closing device..." << std::endl;
    // RAII takes care of this!

    return 0;
}

class LibUsbRAII {
  public:
    LibUsbRAII() : res(libusb_init(NULL)) {
    }

    ~LibUsbRAII() {
        if (isValid()) {
            libusb_exit(NULL);
        }
    }

    bool isValid() {
        return res >= 0;
    }

  private:
    const int res;
};

int main() {

    const struct libusb_version *version = libusb_get_version();
    std::printf("Using libusb v%d.%d.%d.%d\n\n", version->major, version->minor, version->micro, version->nano);

    LibUsbRAII init;
    if (!init.isValid()) {
        return 1;
    }

    uint16_t VID = 105; // nice
    uint16_t PID = 4919;
    test_device(VID, PID);

    return 0;
}
