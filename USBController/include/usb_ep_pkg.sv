`ifndef USB_EP_PKG_SV
`define USB_EP_PKG_SV

`include "usb_desc_pkg.sv"

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
        //TODO
    } NonControlEndpointConfig;

    typedef struct packed {
        //TODO
        int dummy; //TODO remove
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
        ControlEndpointConfig ep0Conf;
        int unsigned endpointCount; // Exclusive EP0
        EndpointConfig [14:0] epConfs; // There can be at most 16 endpoints and one is already reserved for control!
        //TODO
        usb_desc_pkg::DeviceDescriptor deviceDesc;
    } UsbDeviceEpConfig;

    localparam ControlEndpointConfig DefaultControlEpConfig = '{
        dummy: 0 //TODO remove
    };

    localparam NonControlEndpointConfig DefaultNonControlEpConfig = '{
        epTypeDevIn: NONE,
        epTypeDevOut: BULK
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
        bMaxPacketSize0: usb_desc_pkg::EP0_MAX_8_BYTES,
        idVendor: 0, //TODO
        idProduct: 0, //TODO
        bcdDevice: 16'h0010, //TODO
        iManufact: 0, //TODO
        iProduct: 0, //TODO
        iSerialNumber: 0, //TODO
        bNumConfigurations: 1
    };

    localparam UsbDeviceEpConfig DefaultUsbDeviceEpConfig = '{
        ep0Conf: DefaultControlEpConfig,
        endpointCount: 1,
        epConfs: '{
            DefaultEpConfig, // EP 01
            DefaultEpConfig, // EP 02
            DefaultEpConfig, // EP 03
            DefaultEpConfig, // EP 04
            DefaultEpConfig, // EP 05
            DefaultEpConfig, // EP 06
            DefaultEpConfig, // EP 07
            DefaultEpConfig, // EP 08
            DefaultEpConfig, // EP 09
            DefaultEpConfig, // EP 10
            DefaultEpConfig, // EP 11
            DefaultEpConfig, // EP 12
            DefaultEpConfig, // EP 13
            DefaultEpConfig, // EP 14
            DefaultEpConfig  // EP 15
        },
        deviceDesc: DefaultDeviceDesc
    };

endpackage

`endif
