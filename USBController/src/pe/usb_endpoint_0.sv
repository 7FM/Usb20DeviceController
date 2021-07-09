`include "usb_ep_pkg.sv"
`include "usb_desc_pkg.sv"
`include "usb_dev_req_pkg.sv"
`include "usb_packet_pkg.sv"

// AKA control endpoint with address 0
module usb_endpoint_0 #(
    parameter USB_DEV_ADDR_WID = 7,
    parameter USB_DEV_CONF_WID = 8,
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam usb_ep_pkg::ControlEndpointConfig EP_CONF = USB_DEV_EP_CONF.ep0Conf,
    // Maximum packet size for EP0: only 8, 16, 32 or 64 bytes are valid!
    // MUST be 64 for high speed (EP0 only)!
    localparam BUF_BYTE_COUNT = USB_DEV_EP_CONF.deviceDesc.bMaxPacketSize0
)(
    input logic clk48_i,

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,
    output logic [USB_DEV_ADDR_WID-1:0] deviceAddr_o,
    output logic [USB_DEV_CONF_WID-1:0] deviceConf_o,

    input logic gotTransStartPacket_i,
    input logic[1:0] transStartTokenID_i,

    // Device IN interface
    input logic EP_IN_fillTransDone_i,
    input logic EP_IN_fillTransSuccess_i,
    input logic EP_IN_dataValid_i,
    input logic [7:0] EP_IN_data_i,
    output logic EP_IN_full_o,

    /*
    input logic EP_IN_popTransDone_i,
    input logic EP_IN_popTransSuccess_i,
    input logic EP_IN_popData_i,
    output logic EP_IN_dataAvailable_o,
    output logic [7:0] EP_IN_data_o,
    */

    // Device OUT interface
    /*
    input logic EP_OUT_fillTransDone_i,
    input logic EP_OUT_fillTransSuccess_i,
    input logic EP_OUT_dataValid_i,
    input logic [7:0] EP_OUT_data_i,
    output logic EP_OUT_full_o,
    */

    input logic EP_OUT_popTransDone_i,
    input logic EP_OUT_popTransSuccess_i,
    input logic EP_OUT_popData_i,
    output logic EP_OUT_dataAvailable_o,
    output logic EP_OUT_isLastPacketByte_o, //TODO
    output logic [7:0] EP_OUT_data_o
);

    localparam EP0_ROM_SIZE = usb_ep_pkg::requiredROMSize(USB_DEV_EP_CONF);
    logic [7:0] rom [0:EP0_ROM_SIZE-1];

    localparam ROM_IDX_WID = $clog2(EP0_ROM_SIZE);
    logic [ROM_IDX_WID-1:0] romReadIdx, romTransReadIdx, romEndReadIdx;
    logic [ROM_IDX_WID-1:0] nextRomReadIdx, nextRomTransReadIdx, nextRomEndReadIdx;

    logic [ROM_IDX_WID * (USB_DEV_EP_CONF.deviceDesc.bNumConfigurations + 1 + USB_DEV_EP_CONF.stringDescCount + (USB_DEV_EP_CONF.stringDescCount > 0 ? 1 : 0)) - 1:0] descStartIdx;


    //TODO bounds check!
    logic [7:0] romReadData;
    assign romReadData = rom[romTransReadIdx];

    usb_dev_req_pkg::SetupDataPacket setupDataPacket;

    //===============================================================================================================
    // Device State

    //logic suspended; // Currently not supported / considered
    typedef enum logic[1:0] {
        DEVICE_NOT_RESET = 0, // Ignore all transactions except reset signal
        DEVICE_RESET, // Responds to device and configuration descriptor requests & return information, uses default address
        DEVICE_ADDR_ASSIGNED, // responds to requests to default control pipe with default address as long as no address was assigned
        DEVICE_CONFIGURED // processed a SetConfiguration() request with non zero configuration value & endpoints data toggles are set to DATA0. Now the device functions may be used
    } DeviceState;

    DeviceState deviceState, nextDeviceState;

    logic [USB_DEV_ADDR_WID-1:0] nextDeviceAddr;
    logic [USB_DEV_CONF_WID-1:0] nextDeviceConf;

    initial begin
        deviceState = DEVICE_NOT_RESET;
        //TODO does deviceAddr_o/deviceConf_o require an explicit initial Reset? or is relying on usb DEVICE RESET enough?
    end

    logic gotAddrAssigned, gotDevConfig;

    always_comb begin
        nextDeviceState = deviceState;
        nextDeviceAddr = deviceAddr_o;
        nextDeviceConf = deviceConf_o;

        // always ack usb resets if we are in the reset state 
        ackUsbResetDetect_o = deviceState == DEVICE_RESET;

        if (usbResetDetected_i) begin
            nextDeviceState = DEVICE_RESET;
            nextDeviceAddr = {USB_DEV_ADDR_WID{1'b0}};
            nextDeviceConf = {USB_DEV_CONF_WID{1'b0}};
        end else begin
            if (gotDevConfig) begin
                nextDeviceConf = setupDataPacket.wValue[USB_DEV_CONF_WID-1:0];

                // Update device state dependent on the configuration value!
                if (nextDeviceConf == 0) begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end else begin
                    nextDeviceState = DEVICE_CONFIGURED;
                end
            end else if (gotAddrAssigned) begin

                // Update device state dependent on the assigned address!
                nextDeviceAddr = setupDataPacket.wValue[USB_DEV_ADDR_WID-1:0];
                if (nextDeviceAddr == 0) begin
                    nextDeviceState = DEVICE_RESET;
                end else begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end
            end
        end
    end

    always_ff @(posedge clk48_i) begin
        deviceState <= nextDeviceState;
        deviceAddr_o <= nextDeviceAddr;
        deviceConf_o <= nextDeviceConf;
    end

    logic packetBufRst;
    logic packetBufFull;
    localparam BUF_WID = BUF_BYTE_COUNT * 8;
    logic [BUF_WID-1:0] packetBuf;

    logic byteIsData, nextByteIsData;

    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(BUF_BYTE_COUNT)
    ) packetBufWrapper (
        .clk_i(clk48_i),
        .rst_i(packetBufRst),

        .data_i(EP_IN_data_i),
        .dataValid_i(EP_IN_dataValid_i && byteIsData),

        .buffer_o(packetBuf),
        .isFull_o(packetBufFull)
    );

    //TODO adjust data width
    typedef enum logic[1:0] {
        //TODO
        NEW_DEV_REQUEST,
        HANDLE_REQUEST
    } EP0_State;
    EP0_State ep0State, nextEp0State;
    usb_dev_req_pkg::RequestCode deviceRequest;
    logic requestError, nextRequestError;
    logic pidData1Expected, nextPidData1Expected;

    assign setupDataPacket = usb_dev_req_pkg::SetupDataPacket'(packetBuf[usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT * 8 - 1 : 0]);

    initial begin
        pidData1Expected = 1'b0;
        ep0State = NEW_DEV_REQUEST;
    end

    assign EP_IN_full_o = packetBufFull || (ep0State == NEW_DEV_REQUEST ? 1'b0 //TODO
        : setupDataPacket.bmRequestType.dataTransDevToHost /*Error if we expect to send data!*/);

    generate
    always_comb begin
        nextEp0State = ep0State;
        gotAddrAssigned = 1'b0;
        gotDevConfig = 1'b0;
        packetBufRst = gotTransStartPacket_i;

        nextRomReadIdx = romReadIdx;
        nextRomEndReadIdx = romEndReadIdx;
        nextRequestError = requestError;
        // Set this byte as soon as we have a handshake -> we skipped PID
        nextByteIsData = byteIsData;
        nextPidData1Expected = pidData1Expected;

        // A new transaction started
        if (gotTransStartPacket_i) begin
            // Ignore the first byte which is the PID
            nextByteIsData = 1'b0;
            if (transStartTokenID_i == usb_packet_pkg::PID_SETUP_TOKEN[3:2]) begin
                // it is an setup token -> go to new_dev_req state
                nextEp0State = NEW_DEV_REQUEST;
                nextRequestError = 1'b0;
            end else begin
                //TODO check if token PID is valid, I guess we only allow Host IN tokens, otherwise it should be a setup TOKEN!
            end
        end else if (ep0State == NEW_DEV_REQUEST) begin
            if (!byteIsData && EP_IN_dataValid_i && !EP_IN_full_o) begin
                // Once we have skipped the PID we have data bytes!
                nextByteIsData = 1'b1;
                //TODO make PID checks (i.e. correct DATA toggle value)!
                if (EP_IN_data_i[0] != pidData1Expected) begin
                   //TODO ignore this packet (except its setup then it should not matter)
                end else begin
                    // Else if the DATA toggle value is as expected, toggle it for the next transaction!
                    //TODO this must be reverted if during rx an error occurred!
                    nextPidData1Expected = !pidData1Expected;
                end
            end else if (EP_IN_fillTransDone_i) begin
                nextEp0State = HANDLE_REQUEST;

                if (EP_IN_fillTransSuccess_i) begin
                    // Only handle successful transfers
                    unique case (setupDataPacket.bRequest)                    
                        usb_dev_req_pkg::GET_STATUS: begin
                            if (`GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO This requests returns the status for the specified recipient
                                //TODO as we currently do not support features as remote wakeup or endpoint halting, we can always return 2 bytes set to 0
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        /*
                        usb_dev_req_pkg::CLEAR_FEATURE: begin
                            if (`CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO do we want to support this?
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::SET_FEATURE: begin
                            if (`SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO do we want to support this?
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        */
                        usb_dev_req_pkg::SET_ADDRESS: begin
                            if (`SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotAddrAssigned = 1'b1;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::GET_DESCRIPTOR: begin
                            if (`GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply

                                case (setupDataPacket.wValue[15:8])
                                    usb_desc_pkg::DESC_DEVICE: begin
                                        // We only have a single device descriptor!
                                        nextRomReadIdx = {ROM_IDX_WID{1'b0}};
                                        nextRomEndReadIdx = usb_desc_pkg::DeviceDescriptorHeader.bLength - 1; // Last device descriptor idx, as we start at idx 0 this is also the global address!
                                    end
                                    usb_desc_pkg::DESC_CONFIGURATION: begin
                                        // Depends on the descriptor index!
                                        if (setupDataPacket[7:0] < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations) begin
                                            // Index is valid
                                            {nextRomEndReadIdx, nextRomReadIdx} = descStartIdx[setupDataPacket[7:0] * ROM_IDX_WID +: 2 * ROM_IDX_WID];
                                        end else begin
                                            // Index is out of bounds!
                                            // TODO request error
                                        end
                                    end
                                    usb_desc_pkg::DESC_STRING: begin
                                        // Depends on the descriptor index!
                                        if (USB_DEV_EP_CONF.stringDescCount > 0) begin
                                            if (setupDataPacket[7:0] < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations) begin
                                                // Index is valid
                                                {nextRomEndReadIdx, nextRomReadIdx} = descStartIdx[(USB_DEV_EP_CONF.deviceDesc.bNumConfigurations + setupDataPacket[7:0]) * ROM_IDX_WID +: 2 * ROM_IDX_WID];
                                            end else begin
                                                // Index is out of bounds!
                                                // TODO request error
                                            end
                                        end else begin
                                            // Index is out of bounds!
                                            // TODO request error
                                        end
                                    end
                                    default: begin
                                        nextRequestError = 1'b1;
                                    end
                                endcase

                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        /*
                        usb_dev_req_pkg::SET_DESCRIPTOR: begin
                            // This request is optional to implement
                            nextRequestError = 1'b1;
                        end
                        */
                        usb_dev_req_pkg::GET_CONFIGURATION: begin
                            if (`GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO send current configuration value
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::SET_CONFIGURATION: begin
                            if (`SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotDevConfig = 1'b1;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::GET_INTERFACE: begin
                            if (`GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO This request returns the selected alternate setting for the specified interface
                                //TODO as we currently do not allow setting an alternate interface we can simply return 1 byte set to 0 which is the default interface!
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        /*
                        usb_dev_req_pkg::SET_INTERFACE: begin
                            if (`SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO select an alternate setting for the specified interface
                                //TODO do we want to support alternate interfaces???
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        */
                        usb_dev_req_pkg::SYNCH_FRAME: begin
                            if (`SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                // Is only used for isochronous data transfers using implicit pattern synchronization.
                                //TODO apply
                                //TODO this is required for isochronous endpoints
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        /*
                        usb_dev_req_pkg::RESERVED_2, usb_dev_req_pkg::RESERVED_4: begin
                            nextRequestError = 1'b1;
                        end
                        */
                        default: begin
                            //IMPL_SPECIFIC_13_255
                            // Else we have vendor/implementation specific requests -> delegate?
                            // For now lets just issue an request error
                            nextRequestError = 1'b1;
                        end
                    endcase
                end
            end
        end
    end
    endgenerate

    always_ff @(posedge clk48_i) begin
        ep0State <= nextEp0State;
        requestError <= nextRequestError;
        //TODO this needs to be reset to 0 on transition to certain device states too
        pidData1Expected <= nextPidData1Expected;
    end

    //===============================================================================================================
    // Initialize the ROM
    `define INIT_ROM(OFFSET, UPPER_BOUND, SRC)                                      \
        for (romIdx=(OFFSET); romIdx < (OFFSET) + (UPPER_BOUND); romIdx++) begin    \
            initial begin                                                           \
                rom[romIdx] = SRC[(romIdx - (OFFSET)) * 8 +: 8];                    \
            end                                                                     \
        end

    //TODO do we want to use register or assigns here?
    `define INIT_ROM_IDX_LUT(OFFSET, IDX, LUT_NAME)                                    \
        /*initial begin*/                                                              \
        /*assign LUT_NAME[ROM_IDX_WID * (IDX) +: ROM_IDX_WID] = {OFFSET}[ROM_IDX_WID-1:0];*/ \
        /*as yosys does not seem to parse {x}[y:z] expressions correctly, this macro expects that OFFSET is no expression! */ \
        assign LUT_NAME[ROM_IDX_WID * (IDX) +: ROM_IDX_WID] = OFFSET[ROM_IDX_WID-1:0]; \
        /*end*/

    `MUTE_LINT(UNUSED)
    function automatic int calcROMOffset(usb_ep_pkg::UsbDeviceEpConfig usbDevConfig, int maxConfIdx, int maxIfaceIdx, int maxEpIdx);
        automatic int romOffset;
        automatic int confIdx;
        automatic int ifaceIdx;
        automatic int epIdx;
        romOffset = 0;

        // A device descriptor is always required!
        romOffset += {24'b0, usb_desc_pkg::DeviceDescriptorHeader.bLength};

        // Traverse all previous configurations
        for (confIdx = 0; confIdx < maxConfIdx; confIdx++) begin
            // Starting with the configuration descriptor!
            romOffset += {24'b0, usb_desc_pkg::ConfigurationDescriptorHeader.bLength};

            // Now traverse all associated interfaces!
            for (ifaceIdx = 0; ifaceIdx < USB_DEV_EP_CONF.devConfigs[confIdx].confDesc.bNumInterfaces; ifaceIdx++) begin
                // Again starting with the interface descriptor
                romOffset += {24'b0, usb_desc_pkg::InterfaceDescriptorHeader.bLength};

                // Finally traverse all endpoints associated with this interface!
                for (epIdx = 0; epIdx < USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
                    romOffset += {24'b0, usb_desc_pkg::EndpointDescriptorHeader.bLength};
                end
            end
        end

        // Check if there are configs left else maxConfIdx already includes all valid ones!
        if (maxConfIdx < usbDevConfig.deviceDesc.bNumConfigurations) begin
            // Traverse all previous interfaces of the current configuration
            for (ifaceIdx = 0; ifaceIdx < maxIfaceIdx; ifaceIdx++) begin
                // Again starting with the interface descriptor
                romOffset += {24'b0, usb_desc_pkg::InterfaceDescriptorHeader.bLength};

                // Finally traverse all endpoints associated with this interface!
                for (epIdx = 0; epIdx < USB_DEV_EP_CONF.devConfigs[maxConfIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
                    romOffset += {24'b0, usb_desc_pkg::EndpointDescriptorHeader.bLength};
                end
            end

            // Check if there are interfaces for this config left else maxIfaceIdx already includes all valid ones!
            if (maxIfaceIdx < USB_DEV_EP_CONF.devConfigs[maxConfIdx].confDesc.bNumInterfaces) begin
                // Traverse all previous endpoints of the current interface of the current configuration
                for (epIdx = 0; epIdx < maxEpIdx; epIdx++) begin
                    romOffset += {24'b0, usb_desc_pkg::EndpointDescriptorHeader.bLength};
                end
            end
        end

        return romOffset;
    endfunction


    function automatic int calcRelativeStrDescOffset(usb_ep_pkg::UsbDeviceEpConfig usbDevConfig, int maxStrDescIdx);
        automatic int romOffset;
        automatic int strDescIdx;
        romOffset = 0;

        for (strDescIdx = 0; strDescIdx < maxStrDescIdx; strDescIdx++) begin
            romOffset += {24'b0, usbDevConfig.stringDescs[strDescIdx].bLength};
        end

        return romOffset;
    endfunction
    `UNMUTE_LINT(UNUSED)

    generate
        genvar confIdx;
        genvar ifaceIdx;
        genvar epIdx;
        genvar strDescIdx;

        genvar romIdx;

        // First start with the device descriptor header
        `INIT_ROM(0, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::DeviceDescriptorHeader)
        // Then the device descriptor body
        `INIT_ROM(usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::DeviceDescriptorBodyBytes, USB_DEV_EP_CONF.deviceDesc)


        localparam FIXED_ROM_IFACE_OFFSET = usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::ConfigurationDescriptorBodyBytes;
        localparam FIXED_ROM_EP_OFFSET = FIXED_ROM_IFACE_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::InterfaceDescriptorBodyBytes;

        // Iterate over all available configurations
        for (confIdx = 0; confIdx < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations; confIdx++) begin
            localparam ROM_CONF_OFFSET = calcROMOffset(USB_DEV_EP_CONF, confIdx, 0, 0);
            `INIT_ROM_IDX_LUT(ROM_CONF_OFFSET, confIdx, descStartIdx)
            // Starting with the configuration descriptor!
            `INIT_ROM(ROM_CONF_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::ConfigurationDescriptorHeader)
            `INIT_ROM(ROM_CONF_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::ConfigurationDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].confDesc)

            // Now traverse all associated interfaces!
            for (ifaceIdx = 0; ifaceIdx < USB_DEV_EP_CONF.devConfigs[confIdx].confDesc.bNumInterfaces; ifaceIdx++) begin
                localparam ROM_IFACE_OFFSET = calcROMOffset(USB_DEV_EP_CONF, confIdx, ifaceIdx, 0) + FIXED_ROM_IFACE_OFFSET;
                // Again starting with the interface descriptor
                `INIT_ROM(ROM_IFACE_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::InterfaceDescriptorHeader)
                `INIT_ROM(ROM_CONF_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::InterfaceDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc)

                // Finally traverse all endpoints associated with this interface!
                for (epIdx = 0; epIdx < USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
                    localparam ROM_EP_OFFSET = calcROMOffset(USB_DEV_EP_CONF, confIdx, ifaceIdx, epIdx) + FIXED_ROM_EP_OFFSET;
                    `INIT_ROM(ROM_EP_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::EndpointDescriptorHeader)
                    `INIT_ROM(ROM_EP_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::EndpointDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].endpointDescs[epIdx])
                end
            end
        end

        localparam ROM_STR_OFFSET = calcROMOffset(USB_DEV_EP_CONF, {24'b0, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations}, 0, 0);

        `INIT_ROM_IDX_LUT(ROM_STR_OFFSET, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations, descStartIdx)

        // Optional string descriptors:
        if (USB_DEV_EP_CONF.stringDescCount > 0) begin
            // String Descriptor Zero provides a list of supported languages!
            `INIT_ROM(ROM_STR_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::StringDescriptorZeroHeader)
            `INIT_ROM(ROM_STR_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::StringDescriptorZeroBodyBytes, USB_DEV_EP_CONF.supportedLanguages)

            localparam FIXED_ROM_STR_OFFSET = ROM_STR_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::StringDescriptorZeroBodyBytes;

            `INIT_ROM_IDX_LUT(FIXED_ROM_STR_OFFSET, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations + 1, descStartIdx)

            // Now traverse all given string descriptors
            for (strDescIdx = 0; strDescIdx < USB_DEV_EP_CONF.stringDescCount; strDescIdx++) begin
                localparam ROM_STR_DESC_OFFSET = FIXED_ROM_STR_OFFSET + calcRelativeStrDescOffset(USB_DEV_EP_CONF, strDescIdx);

                `INIT_ROM_IDX_LUT(ROM_STR_DESC_OFFSET, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations + 1 + strDescIdx, descStartIdx)

                `INIT_ROM(ROM_STR_DESC_OFFSET, USB_DEV_EP_CONF.stringDescs[strDescIdx].bLength, USB_DEV_EP_CONF.stringDescs[strDescIdx])
            end
        end
    endgenerate

endmodule
