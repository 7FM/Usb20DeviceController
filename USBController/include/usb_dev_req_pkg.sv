`ifndef USB_DEV_REQ_PKG_SV
`define USB_DEV_REQ_PKG_SV

package usb_dev_req_pkg;

    /*
    Standard Device Requests:

    bmRequestType |      bRequest      |      wValue         |    wIndex    | wLength    | Data
    ===========================================================================================================
    Recipient = Device, Interface, Endpoint:
    -----------------------------------------------------------------------------------------------------------
    8'b0000_0000  | CLEAR_FEATURE      | Feature Selector    | Zero         | Zero       | None
    8'b0000_0001  |                    |                     | Interface    |            |
    8'b0000_0010  |                    |                     | Endpoint     |            |
    -----------------------------------------------------------------------------------------------------------
    8'b0000_0000  | SET_FEATURE        | Feature Selector    | Zero         | Zero       | None
    8'b0000_0001  |                    |                     | Interface    |            |
    8'b0000_0010  |                    |                     | Endpoint     |            |
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0000  | GET_STATUS         | Zero                | Zero         | Two        | Device, Interface,
    8'b1000_0001  |                    |                     | Interface    |            | OR
    8'b1000_0010  |                    |                     | Endpoint     |            | Endpoint Status
    ===========================================================================================================
    Recipient = Interface ONLY:
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0001  | GET_INTERFACE      | Zero                | Interface    | One        | Alternate Interface
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0001  | SET_INTERFACE      | Alternate Setting   | Interface    | Zero       | None
    ===========================================================================================================
    Recipient = Endpoint ONLY:
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0010  | SYNCH_FRAME        | Zero                | Endpoint     | Two        | Frame Number
    ===========================================================================================================
    Recipient = Device ONLY:
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0000  | GET_CONFIGURATION  | Zero                | Zero         | One        | Configuration Value
    -----------------------------------------------------------------------------------------------------------
    8'b0000_0000  | SET_CONFIGURATION  | Configuration Value | Zero         | Zero       | None
    -----------------------------------------------------------------------------------------------------------
    8'b1000_0000  | GET_DESCRIPTOR     | Descriptor Type     | Zero OR      | Descriptor | Descriptor
                |                    | Descriptor Index    | Language ID  | Length     |
    -----------------------------------------------------------------------------------------------------------
    8'b0000_0000  | SET_DESCRIPTOR     | Descriptor Type &   | Zero OR      | Zero       | None
                |                    | Descriptor Index    | Language ID  |            |
    -----------------------------------------------------------------------------------------------------------
    8'b0000_0000  | SET_ADDRESS        | Device Address      | Zero         | Zero       | None
    ===========================================================================================================
    */


//=========================================================================================================================

    /* CLEAR_FEATURE:
    FeatureSelector values are used in wValue and must be appropriate to the recipient!
    A ClearFeature() request that references a feature that cannot be cleared, that does not exist, or that
    references an interface or endpoint that does not exist, will cause the device to respond with a Request Error.

    If wLength is non-zero, then the device behavior is not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified -> lets just ignore it
    - DEVICE_ADDR_ASSIGNED: valid iff interface/endpoint select = 0, else respond with request error
    - DEVICE_CONFIGURED: valid for all existing interfaces & endpoints

    Misc: Test_Mode feature cannot be cleared by CLEAR_FEATURE!
    */
    typedef enum logic[15:0] {
        ENDPOINT_HALT = 0, // For recipient == endpoint only
        DEVICE_REMOTE_WAKEUP = 1, // For recipient == device only
        TEST_MODE = 2, // For recipient == device only
        IMPL_SPECIFIC_3_65535
    } FeatureSelector;

//=========================================================================================================================

    /* GET_CONFIGURATION:
    If wValue != 0, wIndex != 0, or wLength != 1, then the device behavior is not specified.

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified -> return current configuration value as in the other states: bConfigurationValue
    - DEVICE_ADDR_ASSIGNED: returns 0
    - DEVICE_CONFIGURED: return non-zero bConfigurationValue that was set
    */

//=========================================================================================================================

    /* GET_DESCRIPTOR:
    wValue[15:8] = descriptor type
    wValue[7:0] = descriptor index
    Descriptor index is used to select a specific descriptor if DescriptorType == DESC_CONFIGURATION OR DescriptorType == DESC_STRING
    For other STANDARD descriptors the index must be 0

    wIndex specifies the Language ID if DescriptorType == DESC_STRING else zero

    wLength field specifies #bytes to return
    If the descriptor is shorter than the wLength field, the device indicates the end of the control transfer by sending a short packet when further data is requested.
    A short packet is defined as a packet shorter than the maximum payload size or a zero length data packet (refer to Chapter 5)

    All devices must provide a device descriptor and at least one configuration descriptor. If a device does not
    support a requested descriptor, it responds with a Request Error

    DeviceState dependent behaviour:
    - DEVICE_RESET: valid
    - DEVICE_ADDR_ASSIGNED: valid
    - DEVICE_CONFIGURED: valid
    */

    typedef enum logic[7:0] {
        DESC_DEVICE = 1,
        DESC_CONFIGURATION = 2,
        DESC_STRING = 3,
        DESC_INTERFACE = 4,
        DESC_ENDPOINT = 5,
        DESC_DEVICE_QUALIFIER = 6,
        DESC_OTHER_SPEED_CONFIGURATION = 7,
        DESC_INTERFACE_POWER = 8, // described in the USB Interface Power Management Specification
        IMPL_SPECIFIC_9_255
    } DescriptorType;
//=========================================================================================================================

//TODO GET_INTERFACE page 254ff.

//=========================================================================================================================

    typedef enum logic[7:0] {
        GET_STATUS = 0,
        CLEAR_FEATURE = 1,
        RESERVED_2 = 2,
        SET_FEATURE = 3,
        RESERVED_4 = 4,
        SET_ADDRESS = 5,
        GET_DESCRIBTOR = 6,
        SET_DESCRIPTOR = 7,
        GET_CONFIGURATION = 8,
        SET_CONFIGURATION = 9,
        GET_INTERFACE = 10,
        SET_CONFIGURATION = 11,
        SYNCH_FRAME = 12,
        IMPL_SPECIFIC_13_255
    } RequestCode;

    typedef enum logic[4:0] {
        RECIP_DEVICE = 0,
        RECIP_INTERFACE = 1,
        RECIP_ENDPOINT = 2,
        RECIP_OTHER = 3,
        RESERVED_4_31,
    } Recipient;

    typedef enum logic[1:0] {
        Standard = 0,
        Class = 1,
        Vendor = 2,
        Reserved = 3
    } RequestType;

    typedef struct packed {
        logic dataTransHostToDev;
        RequestType type;
        Recipient recipient;
    } BmRequestType;

    // Might be used in wIndex[15]
    typedef enum logic[0:0] {
        DEV_IN = 0,
        DEV_OUT = 1
    } EndPointDir;

    // Setup Packet consists of 8 bytes: page 248ff.
    typedef struct packed {
        BmRequestType bmRequestType; // 1 byte
        RequestCode bRequest; // 1 byte
        logic [15:0] wValue;
        logic [15:0] wIndex; // In the case of a control pipe, the request should have the Direction bit set to zero but the device may accept either value of the Direction bit.
        //  The state of the Direction bit is ignored if the wLength field is zero, signifying there is no Data stage
        logic [15:0] wLength;
    } SetupPacket;

endpackage

`endif