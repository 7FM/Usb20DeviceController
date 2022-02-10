`ifndef USB_EP_PKG_SV
`define USB_EP_PKG_SV

`include "usb_desc_pkg.sv"
`include "util_macros.sv"

package usb_ep_pkg;

    typedef enum logic[2:0] {
        CONTROL = 0,
        ISOCHRONOUS = 1,
        BULK = 2,
        INTERRUPT = 3,
        NONE = 4
    } EndpointType;

    typedef struct packed {
        EndpointType epTypeDevIn;
        EndpointType epTypeDevOut;
        logic [10:0] maxPacketSize;
    } NonControlEndpointConfig;

    typedef struct packed {
        usb_desc_pkg::EP0_MaxPacketSize maxPacketSize;
    } ControlEndpointConfig;

    typedef union packed {
        ControlEndpointConfig controlEpConf;
        NonControlEndpointConfig nonControlEp;
    } EpConfigUnion;

    typedef struct packed {
        logic isControlEP;
        EpConfigUnion conf;
    } EndpointConfig;


    typedef struct packed {
        usb_desc_pkg::InterfaceDescriptor ifaceDesc;
        // The amount of used endpoints is specified in the interface descriptor
        // However, it can not exceed 15! (exclusive EP0)
        usb_desc_pkg::EndpointDescriptor [14:0] endpointDescs;
    } InterfaceDescCollection;

    typedef struct packed {
        usb_desc_pkg::ConfigurationDescriptor confDesc;
        InterfaceDescCollection [config_pkg::MAX_INTERFACE_DESCRIPTORS-1:0] ifaces;
    } ConfigurationDescCollection;

    typedef struct packed {
        int unsigned endpointCount; // Exclusive EP0
        EndpointConfig [14:0] epConfs; // There can be at most 16 endpoints and one is already reserved for control!
        usb_desc_pkg::DeviceDescriptor deviceDesc;
        // At least a single configuration is required!
        ConfigurationDescCollection [config_pkg::MAX_CONFIG_DESCRIPTORS-1:0] devConfigs;

        // String descriptors are optional
        int unsigned stringDescCount;
        usb_desc_pkg::StringDescriptorZero supportedLanguages;
        usb_desc_pkg::StringDescriptor [config_pkg::MAX_STRING_DESCRIPTORS-1:0] stringDescs;
    } UsbDeviceEpConfig;

    localparam ControlEndpointConfig DefaultControlEpConfig = '{
        //maxPacketSize: usb_desc_pkg::EP0_MAX_8_BYTES
        // maxPacketSize: usb_desc_pkg::EP0_MAX_16_BYTES
        // maxPacketSize: usb_desc_pkg::EP0_MAX_32_BYTES
        maxPacketSize: usb_desc_pkg::EP0_MAX_64_BYTES
    };

    localparam NonControlEndpointConfig DefaultNonControlEpConfig = '{
        epTypeDevIn: BULK,
        epTypeDevOut: BULK,
        maxPacketSize: 64 // At max 512 bytes per transaction
    };

    localparam EndpointConfig DefaultEpConfig = '{
        isControlEP: 1'b0,
        conf: DefaultNonControlEpConfig
    };

    localparam usb_desc_pkg::DeviceDescriptor DefaultDeviceDesc = '{
        bcdUSB: usb_desc_pkg::USB_2_0_0,
        bDeviceClass: 42, //TODO
        bDeviceSubClass: 42, //TODO
        bDeviceProtocol: 42, //TODO
        bMaxPacketSize0: DefaultControlEpConfig.maxPacketSize,
        idVendor: 0, //TODO
        idProduct: 0, //TODO
        bcdDevice: 16'h0010, //TODO
        iManufact: 1, // string descriptor idx 1
        iProduct: 2, // string descriptor idx 2
        iSerialNumber: 3, // string descriptor idx 3
        bNumConfigurations: 1
    };

    localparam usb_desc_pkg::StringDescriptorZero DefaultStringDescriptorZero = '{
        // Default: only English (GB)
        wLANGID: {16'h0809}
    };
    localparam usb_desc_pkg::StringDescriptor DefaultManufacturerStringDescriptor = '{
        bLength: 2 + 3 * 2, // String length * 2 + 2
        bDescriptorType: usb_desc_pkg::DESC_STRING, // DESC_STRING
        bString: "7FM",
        isUnicode: 0
    };
    localparam usb_desc_pkg::StringDescriptor DefaultProductStringDescriptor = '{
        bLength: 2 + 16 * 2, // String length * 2 + 2
        bDescriptorType: usb_desc_pkg::DESC_STRING, // DESC_STRING
        bString: "dummy USB device",
        isUnicode: 0
    };
    localparam usb_desc_pkg::StringDescriptor DefaultSerialNumberStringDescriptor = '{
        bLength: 2 + 16 * 2, // String length * 2 + 2
        bDescriptorType: usb_desc_pkg::DESC_STRING, // DESC_STRING
        bString: "DEADBEEFF457F00D",
        isUnicode: 0
    };


    localparam usb_desc_pkg::EndpointDescriptor DefaultEndpointINDescriptor = '{
        bEndpointAddress: {1'b0 /* Dir */, 3'b0 /* Reserved */, 4'd1 /* EP addr */}, // Address Zero is reserved
        bmAttributes: {2'b0 /* Reserved */, 2'b0 /* Usage Type */, 2'b0 /* Sync type */, BULK[1:0]},
        wMaxPacketSize: {3'b0 /* Reserved */, 2'b0 /* Trans/Microframe -1 */, DefaultNonControlEpConfig.maxPacketSize[10:0]},
        bInterval: 1
    };

    localparam usb_desc_pkg::EndpointDescriptor DefaultEndpointOUTDescriptor = '{
        bEndpointAddress: {1'b1 /* Dir */, 3'b0 /* Reserved */, 4'd1 /* EP addr */}, // Address Zero is reserved
        bmAttributes: {2'b0 /* Reserved */, 2'b0 /* Usage Type */, 2'b0 /* Sync type */, BULK[1:0]},
        wMaxPacketSize: {3'b0 /* Reserved */, 2'b0 /* Trans/Microframe -1 */, DefaultNonControlEpConfig.maxPacketSize[10:0]},
        bInterval: 1
    };

    localparam usb_desc_pkg::InterfaceDescriptor DefaultInterfaceDescriptor = '{
        bInterfaceNumber: 0, // Default interface 0
        bAlternateSetting: 0,
        // Number of endpoints. Note that both EP IN as well as EP OUT count independently.
        bNumEndpoints: 2,
        bInterfaceClass: 0, //TODO
        bInterfaceSubClass: 0, //TODO
        bInterfaceProtocol: 0, //TODO
        // iInterface: 0 // No string descriptor
        iInterface: 5 // string descriptor idx 5
    };

    localparam usb_desc_pkg::StringDescriptor DefaultInterfaceStringDescriptor = '{
        bLength: 2 + 15 * 2, // String length * 2 + 2
        bDescriptorType: usb_desc_pkg::DESC_STRING, // DESC_STRING
        bString: "dummy interface",
        isUnicode: 0
    };

    localparam InterfaceDescCollection DefaultInterfaceDescCollection = '{
        ifaceDesc: DefaultInterfaceDescriptor,
        `MUTE_LINT(WIDTH)
        endpointDescs: {DefaultEndpointINDescriptor, DefaultEndpointOUTDescriptor}
        `UNMUTE_LINT(WIDTH)
    };

    localparam usb_desc_pkg::ConfigurationDescriptor DefaultConfigurationDescriptor = '{
        // As we only have a single interface and 1 IN & OUT endpoint -> we can sum all descriptor sizes
        wTotalLength: {8'b0, usb_desc_pkg::ConfigurationDescriptorHeader.bLength} + {8'b0, usb_desc_pkg::InterfaceDescriptorHeader.bLength} + 2 * {8'b0, usb_desc_pkg::EndpointDescriptorHeader.bLength},
        bNumInterfaces: 1, // Lets keep it simple and use a single interface!
        bConfigurationValue: 1, // This is the only configuration
        // iConfiguration: 0, // No string descriptor
        iConfiguration: 4, // string descriptor idx 4
        bmAttributes: {1'b1 /*must be set*/, 1'b0 /*Self-powered*/, 1'b0 /*Remote Wakeup*/, 5'b0 /*must be cleared*/},
        // 500mA
        bMaxPower: 250
    };

    localparam usb_desc_pkg::StringDescriptor DefaultConfigurationStringDescriptor = '{
        bLength: 2 + 19 * 2, // String length * 2 + 2
        bDescriptorType: usb_desc_pkg::DESC_STRING, // DESC_STRING
        bString: "dummy configuration",
        isUnicode: 0
    };

    localparam ConfigurationDescCollection DefaultConfigurationDescCollection = '{
        confDesc: DefaultConfigurationDescriptor,
        // Single interface
        `MUTE_LINT(WIDTH)
        ifaces: {DefaultInterfaceDescCollection}
        `UNMUTE_LINT(WIDTH)
    };

    localparam UsbDeviceEpConfig DefaultUsbDeviceEpConfig = '{
        endpointCount: 1,
        epConfs: {
            DefaultEpConfig, // EP 15
            DefaultEpConfig, // EP 14
            DefaultEpConfig, // EP 13
            DefaultEpConfig, // EP 12
            DefaultEpConfig, // EP 11
            DefaultEpConfig, // EP 10
            DefaultEpConfig, // EP 09
            DefaultEpConfig, // EP 08
            DefaultEpConfig, // EP 07
            DefaultEpConfig, // EP 06
            DefaultEpConfig, // EP 05
            DefaultEpConfig, // EP 04
            DefaultEpConfig, // EP 03
            DefaultEpConfig, // EP 02
            DefaultEpConfig  // EP 01
        },
        deviceDesc: DefaultDeviceDesc,
        `MUTE_LINT(WIDTH)
        devConfigs: {DefaultConfigurationDescCollection},
        `UNMUTE_LINT(WIDTH)

        // Optional String descriptors -> omit
        stringDescCount: 5,
        supportedLanguages: DefaultStringDescriptorZero,
        `MUTE_LINT(WIDTH)
        stringDescs: {
            DefaultInterfaceStringDescriptor, // Idx 5
            DefaultConfigurationStringDescriptor, // Idx 4
            DefaultSerialNumberStringDescriptor, // Idx 3
            DefaultProductStringDescriptor, // Idx 2
            DefaultManufacturerStringDescriptor // Idx 1
        }
        `UNMUTE_LINT(WIDTH)
    };

    `MUTE_LINT(UNUSED)
    function automatic int requiredDescROMSize(UsbDeviceEpConfig usbDevConfig);
    `UNMUTE_LINT(UNUSED)
        automatic int byteCount;
        byteCount = 0;

        // A device descriptor is always required!
        byteCount += {24'b0, usb_desc_pkg::DeviceDescriptorHeader.bLength};

        // Iterate over all available configurations
        for (int unsigned confIdx = 0; confIdx < usbDevConfig.deviceDesc.bNumConfigurations; confIdx++) begin
            // wTotalLength must specify the total length for all corresponding configuration, interface & endpoint descriptors
            // -> no need yet to iterate manually over all!
            byteCount += {16'b0, usbDevConfig.devConfigs[confIdx].confDesc.wTotalLength};
        end

        // Optional string descriptors:
        if (usbDevConfig.stringDescCount > 0) begin
            byteCount += {24'b0, usb_desc_pkg::StringDescriptorZeroHeader.bLength};
            for (int unsigned k = 0; k < usbDevConfig.stringDescCount; k++) begin
                byteCount += {24'b0, usbDevConfig.stringDescs[k].bLength};
            end
        end

        return byteCount;
    endfunction

    `MUTE_LINT(UNUSED)
    function automatic int requiredLUTEntries(UsbDeviceEpConfig usbDevConfig);
    `UNMUTE_LINT(UNUSED)
        automatic int lutEntries;
        lutEntries = 1 + {24'b0, usbDevConfig.deviceDesc.bNumConfigurations} + usbDevConfig.stringDescCount + (usbDevConfig.stringDescCount > 0 ? 1 : 0);

        return lutEntries;
    endfunction

    function automatic int requiredROMSize(UsbDeviceEpConfig usbDevConfig);
        automatic int byteCount;
        automatic int romIdxWid;
        automatic int romIdxBytes;
        automatic int lutEntries;
        automatic int newRomIdxWid;
        automatic int newRomIdxBytes;

        byteCount = requiredDescROMSize(usbDevConfig);
        romIdxWid = $clog2(byteCount);
        romIdxBytes = (romIdxWid + 8-1) / 8;
        lutEntries = requiredLUTEntries(usbDevConfig);

        // update the byteCount to reflect the new byte count needed to store the LUT too
        byteCount += lutEntries * romIdxBytes;

        // By adding the LUT we might need an larger address width
        newRomIdxWid = $clog2(byteCount);
        // If the wid increased, then we might also need more bytes to store the address!
        newRomIdxBytes = (newRomIdxWid + 8-1) / 8;

        // Update the byte count accordingly, if we need more address bytes
        byteCount += (newRomIdxBytes - romIdxBytes) * lutEntries;
        // Lets hope that we do not have to loop this bit extension and a single time checking is enough!

        return byteCount;
    endfunction

    function automatic int requiredLUTROMSize(UsbDeviceEpConfig usbDevConfig);
        automatic int lutEntries;
        automatic int romSize;
        automatic int romIdxWid;
        automatic int romIdxBytes;

        lutEntries = requiredLUTEntries(usbDevConfig);
        romSize = requiredROMSize(usbDevConfig);

        romIdxWid = $clog2(romSize);
        romIdxBytes = (romIdxWid + 8-1) / 8;

        return lutEntries * romIdxBytes;
    endfunction

endpackage

`endif
