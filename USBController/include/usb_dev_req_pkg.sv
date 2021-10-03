`ifndef USB_DEV_REQ_PKG_SV
`define USB_DEV_REQ_PKG_SV

package usb_dev_req_pkg;

    // Reduce sanity checks to the bare minimum -> exploit undefined behaviour
`ifndef RUN_SIM
    `define DEV_REQ_MINIMAL_SANITY_CHECKS
`endif

    /*
    Standard Device Requests: starts at page 248

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
    8'b0000_0001  | SET_INTERFACE      | Alternate Setting   | Interface    | Zero       | None
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

    wValue[15:0] = feature selector
    wIndex = interface/endpoint select
    If wLength is non-zero, then the device behaviour is not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified -> lets just ignore it
    - DEVICE_ADDR_ASSIGNED: valid iff interface/endpoint select aka wIndex = 0, else respond with request error
    - DEVICE_CONFIGURED: valid for all existing interfaces & endpoints

    Misc: TEST_MODE feature cannot be cleared by CLEAR_FEATURE! -> requires power cycle
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState == DEVICE_CONFIGURED || setupDataPacket.wIndex == 0)
`else
    `define CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 0 && (deviceState == DEVICE_CONFIGURED || setupDataPacket.wIndex == 0))
`endif

    /* SET_FEATURE:

    wValue[15:0] = feature selector
    If wLength is non-zero, then the device behaviour is not specified

    For TEST_MODE: recipient must be the device!
    wIndex[15:8] = test mode selector
    wIndex[7:0] = 0
    Requires a power cycle to exit the test mode!

    Else:
    wIndex = interface/endpoint select

    DeviceState dependent behaviour:
    - DEVICE_RESET: valid for feature selector = TEST_MODE, otherwise not specified
    - DEVICE_ADDR_ASSIGNED: interface/endpoint select != 0 -> respond with request error
    - DEVICE_CONFIGURED: valid for all existing interfaces & endpoints
    */
    // Note that we do not support TEST_MODE here!
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState == DEVICE_CONFIGURED || setupDataPacket.wIndex == 0)
`else
    `define SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 0 && (deviceState == DEVICE_CONFIGURED || setupDataPacket.wIndex == 0))
`endif

    typedef enum logic[15:0] {
        ENDPOINT_HALT = 0, // For recipient == endpoint only
        DEVICE_REMOTE_WAKEUP = 1, // For recipient == device only
        TEST_MODE = 2, // For recipient == device only
        IMPL_SPECIFIC_3_65535 = 3
    } FeatureSelector;

    typedef enum logic[7:0] {
        RESERVED_0 = 0,
        TEST_J = 1,
        TEST_K = 2,
        TEST_SE0_NAK = 3,
        TEST_PACKET = 4,
        TEST_FORCE_ENABLE = 5,
        RESERVED_STD_TEST_SEL_6_63 = 6,
        RESERVED_64_191 = 64,
        IMPL_SPECIFIC_192_255 = 192
    } TestModeSelector; // Further explained in Section 7.1.20

//=========================================================================================================================

    /* GET_CONFIGURATION:
    If wValue != 0, wIndex != 0, or wLength != 1, then the device behaviour is not specified.

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified -> return current configuration value as in the other states: bConfigurationValue
    - DEVICE_ADDR_ASSIGNED: returns 0
    - DEVICE_CONFIGURED: return non-zero bConfigurationValue that was set
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState) 1'b1
`else
    `define GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 1 && setupDataPacket.wValue == 0 && setupDataPacket.wIndex == 0)
`endif

    /* SET_CONFIGURATION:
    if wIndex != 0 || wLength != 0 || wValue[15:8] != 0 -> behaviour is not specified

    wValue[7:0] = configuration value
    if the configuration value is 0 then the device state changes back to DEVICE_ADDR_ASSIGNED
    else the configuration value has to match an configuration descriptor!

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: if configuration value == 0 -> stay at DEVICE_ADDR_ASSIGNED state
                            else if configuration value mathces an configuration descriptor change state to DEVICE_CONFIGURED
                            else request ERROR
    - DEVICE_CONFIGURED: same logic as DEVICE_ADDR_ASSIGNED
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState > DEVICE_RESET)
`else
    `define SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 0 && setupDataPacket.wValue[15:8] == 0 && setupDataPacket.wIndex == 0 && deviceState > DEVICE_RESET)
`endif

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
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    //TODO do we have to check this? Lets assume no!
    `define GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState) 1'b1
`else
    `define GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wValue[15:8] == usb_desc_pkg::DESC_STRING || setupDataPacket.wIndex == 0)
`endif


    /* SET_DESCRIPTOR: OPTIONAL
    wValue[15:8] = descriptor type
    wValue[7:0] = descriptor index
    Descriptor index is used to select a specific descriptor if DescriptorType == DESC_CONFIGURATION OR DescriptorType == DESC_STRING
    For other STANDARD descriptors the index must be 0

    wIndex specifies the Language ID if DescriptorType == DESC_STRING else zero

    wLength specifies the number of bytes to transfer to the device

    The only allowed descriptor types are DESC_DEVICE, DESC_CONFIGURATION and DESC_STRING

    If this request is not supported (as it is optional) -> respond with request error

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: if supported -> valid
    - DEVICE_CONFIGURED: if supported -> valid
    */
    // This is optional to implement -> hence, we always respond with a request error
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define SET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState) (1'b0)
`else
    `define SET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState) (1'b0)
`endif


//=========================================================================================================================

    /* GET_INTERFACE
    wValue = 0
    wIndex = interface index
    This request returns the selected alternate setting for the specified interface
    If the interface specified does not exist, then the device responds with a Request Error

    if wValue != 0 || wLength != 1 -> device behaviour is not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: repsonse with request error
    - DEVICE_CONFIGURED: valid
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState == DEVICE_CONFIGURED)
`else
    `define GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wValue == 0 && setupDataPacket.wLength == 1 && deviceState == DEVICE_CONFIGURED)
`endif

    /* SET_INTERFACE
    select an alternate setting for the specified interface

    if the interface of the device only supports a single settings (-> has no alternate setting) -> respond with STALL in the status stage
    if the interface or the alternate setting does not exist -> responds with Request Error // TODO if only a single default setting exist, then this might be ambiguous!

    if wLength != 0 -> device behaviour is not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: repsonse with request error
    - DEVICE_CONFIGURED: valid
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState == DEVICE_CONFIGURED)
`else
    `define SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 0 && deviceState == DEVICE_CONFIGURED)
`endif

//=========================================================================================================================

    /* GET_STATUS
    This requests returns the status for the specified recipient
    if an interface or an endpoint is specified that does not exist, then the device responds with a Request Error.

    if wValue != 0 || wLength != 2 || (deviceRequest && wIndex != 0) -> device behaviour not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: if interface != 0 || endpoint != 0 -> Request error
    - DEVICE_CONFIGURED: valid

    Returned Data Format: 2 bytes

    - For a device: 
        d0 = Self Powered (0 on reset): indicates if the device is currently self-powered d0 == 1'b0 -> powered by usb-bus.
                                        May NOT be changed by SetFeature/ClearFeature
        d1 = Remote Wakeup (0 on reset): indicates whether the device is currently enabled to request remote wakeup.
                                            CAN be modified with SetFeature/ClearFeature with the DEVICE_REMOTE_WAKEUP feature selector
        d2-d15 = reserved (0 on reset)

    - For an interface:
        d0-d15 = reserved (0 on reset)

    - For an endpoint:
        d0 = Halt (0 on reset): required to be implemented for interrupt & bulk endpoint types! indicates whether the endpoint is currently halted.
                                Optionally settable with SetFeature(ENDPOINT_HALT) and clearable with ClearFeature(ENDPOINT_HALT) -> endpoint no longer responds with STALL
                                ClearFeature(ENDPOINT_HALT) always reinitializes data toggle to DATA0!
                                Halt flag is reset to zero at each SetConfiguration or SetInterface request
        d1-d15 = reserved (0 on reset)
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wIndex == 0 || deviceState == DEVICE_CONFIGURED)
`else
    //TODO add sanity check for (deviceRequest && wIndex != 0) ?
    `define GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wValue == 0 && setupDataPacket.wLength == 2 && (setupDataPacket.wIndex == 0 || deviceState == DEVICE_CONFIGURED))
`endif

//=========================================================================================================================

    /* SET_ADDRESS
    wValue = device address

    Transaction stages:
    Setup packet
    Data packet (optional)
    Status packet (in opposite direction than data stage or from device to host in case of no data stage)

    Stages after the initial setup packet assume the SAME device address as the setup packet
    -> device changes its address AFTER the status stage is completed SUCCESSFULLY!
    Note that for all other requests the operation indicated must be completed BEFORE the status stage!

    If wValue > 127 || wIndex != 0 || wLength != 0 -> device behaviour is not specified

    DeviceState dependent behaviour:
    - DEVICE_RESET: valid: changes state to DEVICE_ADDR_ASSIGNED iff wValue != 0
    - DEVICE_ADDR_ASSIGNED: valid: if wValue = 0 -> change back in device reset state! Else overwrite current addr
    - DEVICE_CONFIGURED: not specified
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    // `define SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState < DEVICE_CONFIGURED)
    `define SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState) 1'b1 // Full YOLO
`else
    `define SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 0 && setupDataPacket.wValue[15:7] == 0 && setupDataPacket.wIndex == 0 && deviceState < DEVICE_CONFIGURED)
`endif

//=========================================================================================================================

    /* SYNCH_FRAME
    Is only used for isochronous data transfers using implicit pattern synchronization.
    For isochronous transfers, the endpoint might require varying sizes per frame transfers according to a specific pattern.
    The host and endpoint must agree on which frame the repeating pattern begins.
    -> endpoint returns the number of the frame in which the pattern began

    wIndex = endpoint select
    if wLength != 2 || wValue != 0 -> behaviour not specified
    if the specified endpoint does not support this request -> respond with request error

    DeviceState dependent behaviour:
    - DEVICE_RESET: not specified
    - DEVICE_ADDR_ASSIGNED: Request Error
    - DEVICE_CONFIGURED: valid
    */
`ifdef DEV_REQ_MINIMAL_SANITY_CHECKS
    `define SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState) (deviceState == DEVICE_CONFIGURED)
`else
    `define SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState) (setupDataPacket.wLength == 2 && setupDataPacket.wValue == 0 && deviceState == DEVICE_CONFIGURED)
`endif

//=========================================================================================================================

    typedef enum logic[7:0] {
        GET_STATUS = 0,
        CLEAR_FEATURE = 1,
        RESERVED_2 = 2,
        SET_FEATURE = 3,
        RESERVED_4 = 4,
        SET_ADDRESS = 5,
        GET_DESCRIPTOR = 6,
        SET_DESCRIPTOR = 7,
        GET_CONFIGURATION = 8,
        SET_CONFIGURATION = 9,
        GET_INTERFACE = 10,
        SET_INTERFACE = 11,
        SYNCH_FRAME = 12,
        IMPL_SPECIFIC_13_255 = 13
    } RequestCode;

    typedef enum logic[4:0] {
        RECIP_DEVICE = 0,
        RECIP_INTERFACE = 1,
        RECIP_ENDPOINT = 2,
        RECIP_OTHER = 3,
        RESERVED_4_31 = 4
    } Recipient;

    typedef enum logic[1:0] {
        Standard = 0,
        Class = 1,
        Vendor = 2,
        Reserved = 3
    } RequestType;

    typedef struct packed {
        logic dataTransDevToHost;
        RequestType reqType;
        Recipient recipient;
    } BmRequestType;

    // Might be used in wIndex[15]
    typedef enum logic[0:0] {
        DEV_IN = 0,
        DEV_OUT = 1
    } EndPointDir;

    // Setup Packet consists of 8 bytes: page 248ff.
    typedef struct packed {
        //  The state of the Direction bit is ignored if the wLength field is zero, signifying there is no Data stage
        logic [15:0] wLength;
        logic [15:0] wIndex; // In the case of a control pipe, the request should have the Direction bit set to zero but the device may accept either value of the Direction bit.
        logic [15:0] wValue;
        RequestCode bRequest; // 1 byte
        BmRequestType bmRequestType; // 1 byte
    } SetupDataPacket;

    localparam SETUP_DATA_PACKET_BYTE_COUNT = 8;

endpackage

`endif
