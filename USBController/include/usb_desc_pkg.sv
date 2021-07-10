`ifndef USB_DESC_PKG_SV
`define USB_DESC_PKG_SV

`include "config_pkg.sv"
`include "util_macros.sv"

package usb_desc_pkg;

    // Each Usb Device can have 1 or more configurations
    // Each configuration has 1 or more interfaces, identified with bInterfaceNumber
    // Each interface can have alternate settings which are identified by bAlternateSetting (bInterfaceNumber stays the same)
    // Each interface descriptor has bNumEndpoints many to EP0 additional endpoints associated
    // The additional endpoints are described with Endpoint descriptors

    // Data returned by GET_DESCRIPTOR(DESC_CONFIGURATION, DescIdx X):
    // - Configuration Descriptor with bConfigurationValue = X (specifies N interfaces)
    //     - Interface Descriptor 0.0 (specifies M Endpoints) ->  version format: bInterfaceNumber.bAlternateSetting
    //         - Endpoint Descriptor 0
    //         ...
    //         - Endpoint Descriptor M-1
    //     i.e. also Alternate settings for the same interface:
    //     - Interface Descriptor 0.1 (Specifies L Endpoints) -> i.e. same interface as previous interface descriptor BUT an ALTERNATE Setting (1)
    //         ... (Endpoint Descriptors)
    //     ... (More Interfaces / Alternate settings)
    //     - Interface Descriptor N-1.0
    //         ... (Enpoint Descriptors)
    //     ... (More Alternate settings)
    //


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

    typedef struct packed {
        DescriptorType bDescriptorType;
        logic [7:0] bLength;
    } DescriptorHeader;
    localparam DESCRIPTOR_HEADER_BYTES = 2;

    // Device Descriptor
    typedef enum logic[7:0] {
        EP0_MAX_8_BYTES = 8,
        EP0_MAX_16_BYTES = 16,
        EP0_MAX_32_BYTES = 32,
        EP0_MAX_64_BYTES = 64
    } EP0_MaxPacketSize;
    typedef enum logic[15:0] {
        USB_1_1_0 = 16'h0110,
        USB_2_0_0 = 16'h0200
    } UsbVersionBCD;

    typedef struct packed {
        // Number of possible configurations for the current operating speed
        // The configration value is an one based index (because zero is reserved to indicate that the device is not yet configured!)
        logic [7:0] bNumConfigurations;

        // index of string descriptor describing the device's serial number: if not supported set to 0
        logic [7:0] iSerialNumber;

        // index of string descriptor describing product: if not supported set to 0urer;
        logic [7:0] iProduct;

        // index of string descriptor describing manufacturer: if not supported set to 0
        logic [7:0] iManufact;

        // Device release number in  binary coded decimal
        logic [15:0] bcdDevice;

        logic [15:0] idProduct;
        logic [15:0] idVendor;

        // Maximum packet size for EP0: only 8, 16, 32 or 64 bytes are valid!
        // MUST be 64 for high speed (EP0 only)!
        EP0_MaxPacketSize bMaxPacketSize0/* = 8*/;

        logic [7:0] bDeviceProtocol;
        logic [7:0] bDeviceSubClass;
        logic [7:0] bDeviceClass;

        // Binary Coded Decimal (i.e. 2.10 is 0x210). Specifies the USB Spec with which this device is compliant.
        // format: 0xJJMN for version JJ.M.N (JJ - major version, M - minor version, N - sub-minor version number)
        // USB 2.0 -> 0x0200
        UsbVersionBCD bcdUSB;
    } DeviceDescriptor;

    localparam DescriptorHeader DeviceDescriptorHeader = '{
        bLength: 18,
        bDescriptorType: DESC_DEVICE
    };
    localparam DeviceDescriptorBodyBytes = {24'b0, DeviceDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;


    // Device_Qualifier Descriptor: describes information about a high-speed capable device that would change if the device changes its operating speed
    // if HS device is operating at FS -> return info about HS and vice-versa
    // For FS or LS only devices -> respond with request error!
    `MUTE_LINT(UNUSED)
    typedef struct packed {
        logic [7:0] bReserved; // Zero
        logic [7:0] bNumConfigurations;
        logic [7:0] bMaxPacketSize0;
        logic [7:0] bDeviceProtocol;
        logic [7:0] bDeviceSubClass;
        logic [7:0] bDeviceClass;
        UsbVersionBCD bcdUSB;
    } DeviceQualifierDescriptor;

    localparam DescriptorHeader DeviceQualifierDescriptorHeader = '{
        bLength: 10,
        bDescriptorType: DESC_DEVICE_QUALIFIER
    };
    localparam DeviceQualifierDescriptorBodyBytes = {24'b0, DeviceQualifierDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;
    `UNMUTE_LINT(UNUSED)


    // Configuration Descriptor
    // When the host requests the configuration descriptor, all related interface and endpoint descriptors are returned (refer to Section 9.4.3).
    // -> combines all required decriptors and send them in a single transaction!
    typedef struct packed {
        // Maximum Power consumption of the USB device from the bus. Expressed in 2mA units -> value of 1 corresponds to 2mA
        logic [7:0] bMaxPower;

        // bmAttributes[7] = bmAttributes[4:0] = 0 (reserved)
        // bmAttributes[6] = Self-powered: is set if the device has a local power source, if a device uses power from bus as well as a local source then bMaxPower has a non zero value
        // bmAttributes[5] = Remote Wakeup, is set if device supports it
        logic [7:0] bmAttributes;

        logic [7:0] iConfiguration; // Index of string descriptor describing this configuration: if not supported set to 0
        logic [7:0] bConfigurationValue; // Value to use as an argument to select this configuration
        logic [7:0] bNumInterfaces; // Number of interfaces supported by this configuration //TODO are alternate settings included here?
        logic [15:0] wTotalLength; // Total length of data returned for this configuration: length of all descriptors: configuration, interface, endpoint, and class/vendor specific
    } ConfigurationDescriptor;

    localparam DescriptorHeader ConfigurationDescriptorHeader = '{
        bLength: 9,
        bDescriptorType: DESC_CONFIGURATION
    };
    localparam ConfigurationDescriptorBodyBytes = {24'b0, ConfigurationDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;


    // Other_Speed_Configuration Descriptor
    // Has identical fields as the ConfigurationDescriptor but is used as description for the other operation speed!
    `MUTE_LINT(UNUSED)
    typedef struct packed {
        // Maximum Power consumption of the USB device from the bus. Expressed in 2mA units -> value of 1 corresponds to 2mA
        logic [7:0] bMaxPower;

        // bmAttributes[7] = bmAttributes[4:0] = 0 (reserved)
        // bmAttributes[6] = Self-powered: is set if the device has a local power source, if a device uses power from bus as well as a local source then bMaxPower has a non zero value
        // bmAttributes[5] = Remote Wakeup, is set if device supports it
        logic [7:0] bmAttributes;

        logic [7:0] iConfiguration; // Index of string descriptor describing this configuration: if not supported set to 0
        logic [7:0] bConfigurationValue; // Value to use as an argument to select this configuration
        logic [7:0] bNumInterfaces; // Number of interfaces supported by this configuration
        logic [15:0] wTotalLength; // Total length of data returned for this configuration: length of all descriptors: configuration, interface, endpoint, and class/vendor specific
    } OtherSpeedConfigurationDescriptor;

    localparam DescriptorHeader OtherSpeedConfigurationDescriptorHeader = '{
        bLength: 9,
        bDescriptorType: DESC_OTHER_SPEED_CONFIGURATION
    };
    localparam OtherSpeedConfigurationDescriptorBodyBytes = {24'b0, OtherSpeedConfigurationDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;
    `UNMUTE_LINT(UNUSED)


    // Interface Descriptor
    typedef struct packed {
        logic [7:0] iInterface; // Index for string descriptor describing this interface
        logic [7:0] bInterfaceProtocol;
        logic [7:0] bInterfaceSubClass;
        logic [7:0] bInterfaceClass;
        logic [7:0] bNumEndpoints; // Number of used endpoints (exclusive EP0)
        logic [7:0] bAlternateSetting; // Alternate Setting for the interface specified with bInterfaceNumber, also zero based
        logic [7:0] bInterfaceNumber; // Number of this interfaces -> zero based index for the array of interfaces of the current selected configuration
    } InterfaceDescriptor;

    localparam DescriptorHeader InterfaceDescriptorHeader = '{
        bLength: 9,
        bDescriptorType: DESC_INTERFACE
    };
    localparam InterfaceDescriptorBodyBytes = {24'b0, InterfaceDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;


    // Endpoint Descriptor
    // An endpoint descriptor is always returned as part of GetDescriptor(Configuration) request.
    // An endpoint descriptor cannot be directly accessed with a GetDescriptor() or SetDescriptor() request.
    // There is NEVER an endpoint descriptor for endpoint zero
    typedef struct packed {
        // Interval for polling the endpoint for data transfers
        // Epressed in frames or microframes, depending on the device operation speed
        // For full-/high-speed isochronous endpoints, this value must be in the range from 1 to 16
        // For full-/low-speed interrupt endpoints, the value of this field may be from 1 to 255.
        // bInterval is used as pow(2, bInterval - 1) to calculate the polling period!

        // "For high-speed bulk/control OUT endpoints, the bInterval must specify the maximum NAK rate of the endpoint.
        // A value of 0 indicates the endpoint never NAKs.
        // Other values indicate at most 1 NAK each bInterval number of microframes.
        // This value must be in the range from 0 to 255." page 271 //TODO and for full/low speed endpoints??? I guess a value of 1 should be fine in either case
        logic [7:0] bInterval;

        // wMaxPacketSize[10:0] specify the maximum packet size in bytes
        // wMaxPacketSize[12:11] specify the number of additional transaction opertunities per microframe
        //     00 = None (1 transaction per microframe)
        //     01 = 1 addtional (2 per microframe)
        //     10 = 2 addtional (3 per microframe)
        //     11 = reserved
        // wMaxPacketSize[15:13] are reserved and must be 0!
        logic [15:0] wMaxPacketSize;

        // bmAttributes[1:0] Transfer Type:
        //     00 = Control
        //     01 = Isochronous
        //     10 = Bulk
        //     11 = Interrupt
        // bmAttributes[3:2] Synchronization Type: (only for Isochronous transfer type else this must be 0!)
        //     00 = No Synchronization
        //     01 = Asynchronous
        //     10 = Adaptive
        //     11 = Synchronous
        // bmAttributes[5:4] Usage Type: (only for Isochronous transfer type else this must be 0!)
        //     00 = Data endpoint
        //     01 = Feedback endpoint
        //     10 = implicit feedback Data endpoint
        //     11 = Reserved
        // bmAttributes[15:6] are reserved and must be 0!
        logic [15:0] bmAttributes;

        // bEndpointAddress[7] Direction (0 = Host Out, 1 = Host In), ignored for control endpoints
        // bEndpointAddress[6:4] Reserved, reset to zero
        // bEndpointAddress[3:0] Endpoint number
        logic [7:0] bEndpointAddress;
    } EndpointDescriptor;

    localparam DescriptorHeader EndpointDescriptorHeader = '{
        bLength: 7,
        bDescriptorType: DESC_ENDPOINT
    };
    localparam EndpointDescriptorBodyBytes = {24'b0, EndpointDescriptorHeader.bLength} - DESCRIPTOR_HEADER_BYTES;


    // String Descriptor: are NOT NULL-terminated!
    typedef struct packed {
        // See: https://www.voidtools.com/support/everything/language_ids/
        // English (GB): 0x0809
        // English (USA): 0x0409
        // German (DE): 0x0407
        logic [16 * config_pkg::SUPPORTED_LANGUAGES - 1:0] wLANGID;
    } StringDescriptorZero;

    localparam DescriptorHeader StringDescriptorZeroHeader = '{
        bLength: 2 + 2 * config_pkg::SUPPORTED_LANGUAGES,
        bDescriptorType: DESC_STRING
    };
    localparam StringDescriptorZeroBodyBytes = {24'b0, StringDescriptorZeroHeader.bLength} - DESCRIPTOR_HEADER_BYTES;

    typedef struct packed {
        logic [8 * config_pkg::MAX_STRING_LEN - 1:0] bString;
        logic [7:0] bDescriptorType; // DESC_STRING
        logic [7:0] bLength; // String length + 2
    } StringDescriptor;


endpackage

`endif
