`ifndef USB_EP_PKG_SV
`define USB_EP_PKG_SV

package usb_ep_pkg;

    typedef enum logic[2:0] {
        BULK,
        INTERRUPT,
        ISOCHRONOUS,
        NONE
    } EndpointType;

    typedef struct packed {
        EndpointType epType;
        //TODO
    } EndpointConfig;

    typedef struct packed {
        //TODO
        int dummy; //TODO remove
    } ControlEndpointConfig;


    typedef struct packed {
        ControlEndpointConfig ep0Conf;
        int unsigned endpointCount; // Exclusive EP0
        EndpointConfig[14:0] epConfs; // There can be at most 16 endpoints and one is already reserved for control!
        //TODO
    } UsbDeviceEpConfig;


    localparam ControlEndpointConfig DefaultControlEpConfig = '{
        dummy: 0 //TODO remove
    };

    localparam EndpointConfig DefaultEpConfig = '{
        epType: BULK
    };

    localparam UsbDeviceEpConfig DefaultUsbDeviceEpConfig = '{
        ep0Conf: DefaultControlEpConfig,
        endpointCount: 0,
        epConfs: {
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
        }
    };

endpackage

`endif
