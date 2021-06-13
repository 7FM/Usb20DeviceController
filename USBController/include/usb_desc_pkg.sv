`ifndef USB_DESC_PKG_SV
`define USB_DESC_PKG_SV

package usb_desc_pkg;

    typedef enum logic[7:0] {
        DESC_DEVICE = 1,
        DESC_CONFIGURATION = 2,
        DESC_STRING = 3,
        DESC_INTERFACE = 4,
        DESC_ENDPOINT = 5,
        DESC_DEVICE_QUALIFIER = 6,
        DESC_OTHER_SPEED_CONFIGURATION = 7,
        DESC_INTERFACE_POWER = 8, // described in the USB Interface Power Management Specification
        IMPL_SPECIFIC_9_255 = 9
    } DescriptorType;

    // Device Descriptor
    typedef struct packed {
        // Size of the descriptor in bytes
        logic [7:0] bLength; // In this case: 'd18
        // DEVICE Descriptor Type == 'd1
        DescriptorType bDescriptorType;
        // Binary Coded Decimal (i.e. 2.10 is 0x210). Specifies the USB Spec with which this device is compliant.
        // format: 0xJJMN for version JJ.M.N (JJ - major version, M - minor version, N - sub-minor version number)
        // USB 2.0 -> 0x0200
        logic [15:0] bcdUSB;
        logic [7:0] bDeviceClass;
        logic [7:0] bDeviceSubClass;
        logic [7:0] bDeviceProtocol;
        // Maximum packet size for EP0: only 8, 16, 32 or 64 bytes are valid!
        // MUST be 64 for high speed (EP0 only)!
        logic [7:0] bMaxPacketSize0;
        logic [15:0] idVendor;
        logic [15:0] idProduct;
        // Device release number in  binary coded decimal
        logic [15:0] bcdDevice;
        // index of string descriptor describing manufacturer: if not supported set to 0
        logic [7:0] iManufact;
        // index of string descriptor describing product: if not supported set to 0urer;
        logic [7:0] iProduct;
        // index of string descriptor describing the device's serial number: if not supported set to 0
        logic [7:0] iSerialNumber;
        // Number of possible configurations for the current operating speed
        logic [7:0] bNumConfigurations;
    } DeviceDescriptor;

    // Device_Qualifier Descriptor: describes information about a high-speed capable device that would change if the device changes its operating speed
    // if HS device is operating at FS -> return info about HS and vice-versa
    // For FS or LS devices only -> respond with request error!
    typedef struct packed {
        logic [7:0] bLength; // In this case: 'd10
        DescriptorType bDescriptorType; // Device Qualifier Descriptor type == 'd6
        logic [15:0] bcdUSB;
        logic [7:0] bDeviceClass;
        logic [7:0] bDeviceSubClass;
        logic [7:0] bDeviceProtocol;
        logic [7:0] bMaxPacketSize0;
        logic [7:0] bNumConfigurations;
        logic [7:0] bReserved; // Zero
    } DeviceQualifierDescriptor;

    // Configuration Descriptor
    // When the host requests the configuration descriptor, all related interface and endpoint descriptors are returned (refer to Section 9.4.3).
    // -> combines all required decriptors and send them in a single transaction!
    typedef struct packed {
        logic [7:0] bLength; // In this case: 'd9
        DescriptorType bDescriptorType; // Configuration Descriptor type == 'd2
        logic [15:0] wTotalLength; // Total length of data returned for this configuration: length of all descriptors: configuration, interface, endpoint, and class/vendor specific
        logic [7:0] bNumInterfaces; // Number of interfaces supported by this configuration
        logic [7:0] bConfigurationValue; // Value o use as an argument to select this configuration
        logic [7:0] iConfiguration; // Index of string descriptor describing this configuration: if not supported set to 0
         // bmAttributes[7] = bmAttributes[4:0] = 0 (reserved)
         // bmAttributes[6] = Self-powered: is set if the device has a local power source, if a device uses power from bus as well as a local source then bMaxPower has a non zero value
         // bmAttributes[5] = Remote Wakeup, is set if device supports it
        logic [7:0] bmAttributes;
        // Maximum Power consumption of the USB device from the bus. Expressed in 2mA units -> value of 1 corresponds to 2mA
        logic [7:0] bMaxPower;
    } ConfigurationDescriptor;

    // Other_Speed_Configuration Descriptor page 266ff. TODO

endpackage

`endif
