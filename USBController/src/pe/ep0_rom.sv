`include "usb_ep_pkg.sv"

module ep0_rom #(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam EP0_ROM_SIZE = usb_ep_pkg::requiredROMSize(USB_DEV_EP_CONF),
    localparam ROM_IDX_WID = $clog2(EP0_ROM_SIZE),
    localparam LUT_ENTRIES = usb_ep_pkg::requiredLUTEntries(USB_DEV_EP_CONF),
    localparam LUT_ROM_SIZE = usb_ep_pkg::requiredLUTROMSize(USB_DEV_EP_CONF)
)(
    input logic [ROM_IDX_WID-1:0] readAddr_i,
    output logic [7:0] romData_o
);

    logic [7:0] rom [0:EP0_ROM_SIZE-1];
    assign romData_o = rom[readAddr_i];

    //===============================================================================================================
    // Initialize the ROM

    `define INIT_ROM(OFFSET, UPPER_BOUND, SRC)                                                                  \
        `MUTE_LINT(WIDTH)                                                                                       \
        for (romIdx=(OFFSET); romIdx < (OFFSET) + (UPPER_BOUND); romIdx++) begin  \
            initial begin                                                                                       \
                rom[romIdx] = SRC[(romIdx - (OFFSET)) * 8 +: 8];                               \
`ifdef RUN_SIM                                                                                                  \
                $display("INIT: rom[%d] = 0x%h", romIdx, rom[romIdx]);                                          \
`endif                                                                                                          \
            end                                                                                                 \
        end                                                                                                     \
        `UNMUTE_LINT(WIDTH)

    `define INIT_ROM_STR(OFFSET, UPPER_BOUND, SRC, SRC_OFFSET)                                                          \
        `MUTE_LINT(WIDTH)                                                                                               \
        for (romIdx=(OFFSET); romIdx < (OFFSET) + (UPPER_BOUND); romIdx++) begin          \
            initial begin                                                                                               \
                rom[romIdx] = SRC[((SRC_OFFSET) + (UPPER_BOUND) - 1 - (romIdx - (OFFSET))) * 8 +: 8];  \
`ifdef RUN_SIM                                                                                                          \
                $display("INIT: rom[%d] = 0x%h '%s'", romIdx, rom[romIdx], rom[romIdx]);                                \
`endif                                                                                                                  \
            end                                                                                                         \
        end                                                                                                             \
        `UNMUTE_LINT(WIDTH)

    `define INIT_ROM_IDX_LUT(OFFSET, IDX)                                                   \
        /* If more than one byte is needed for the address then all first bytes for */      \
        /* the entries are stored before the second, third & so on */                       \
        /* -> offset of LUT_ENTRIES between address bytes of the same LUT entry */          \
        for (romIdx = (IDX); romIdx < LUT_ROM_SIZE; romIdx = romIdx + LUT_ENTRIES) begin    \
            initial begin                                                                   \
                rom[romIdx] = OFFSET[(romIdx / LUT_ENTRIES) * 8 +: 8];                      \
`ifdef RUN_SIM                                                                              \
                $display("INIT: LUT idx %d: rom[%d] = %d", (IDX), romIdx, rom[romIdx]);     \
`endif                                                                                      \
            end                                                                             \
        end

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
            for (ifaceIdx = 0; ifaceIdx < usbDevConfig.devConfigs[confIdx].confDesc.bNumInterfaces; ifaceIdx++) begin
                // Again starting with the interface descriptor
                romOffset += {24'b0, usb_desc_pkg::InterfaceDescriptorHeader.bLength};

                // Finally traverse all endpoints associated with this interface!
                for (epIdx = 0; epIdx < usbDevConfig.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
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
                for (epIdx = 0; epIdx < usbDevConfig.devConfigs[maxConfIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
                    romOffset += {24'b0, usb_desc_pkg::EndpointDescriptorHeader.bLength};
                end
            end

            // Check if there are interfaces for this config left else maxIfaceIdx already includes all valid ones!
            if (maxIfaceIdx < usbDevConfig.devConfigs[maxConfIdx].confDesc.bNumInterfaces) begin
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
        `INIT_ROM(LUT_ROM_SIZE, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::DeviceDescriptorHeader)
        // Then the device descriptor body
        `INIT_ROM(LUT_ROM_SIZE + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::DeviceDescriptorBodyBytes, USB_DEV_EP_CONF.deviceDesc)


        localparam FIXED_ROM_IFACE_OFFSET = usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::ConfigurationDescriptorBodyBytes;
        localparam FIXED_ROM_EP_OFFSET = FIXED_ROM_IFACE_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::InterfaceDescriptorBodyBytes;

        // Iterate over all available configurations
        for (confIdx = 0; confIdx < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations; confIdx++) begin
            localparam ROM_CONF_OFFSET = LUT_ROM_SIZE + calcROMOffset(USB_DEV_EP_CONF, confIdx, 0, 0);
            `INIT_ROM_IDX_LUT(ROM_CONF_OFFSET, confIdx)
            // Starting with the configuration descriptor!
            `INIT_ROM(ROM_CONF_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::ConfigurationDescriptorHeader)
            `INIT_ROM(ROM_CONF_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::ConfigurationDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].confDesc)

            // Now traverse all associated interfaces!
            for (ifaceIdx = 0; ifaceIdx < USB_DEV_EP_CONF.devConfigs[confIdx].confDesc.bNumInterfaces; ifaceIdx++) begin
                localparam ROM_IFACE_OFFSET = LUT_ROM_SIZE + calcROMOffset(USB_DEV_EP_CONF, confIdx, ifaceIdx, 0) + FIXED_ROM_IFACE_OFFSET;
                // Again starting with the interface descriptor
                `INIT_ROM(ROM_IFACE_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::InterfaceDescriptorHeader)
                `INIT_ROM(ROM_IFACE_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::InterfaceDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc)

                // Finally traverse all endpoints associated with this interface!
                for (epIdx = 0; epIdx < USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].ifaceDesc.bNumEndpoints; epIdx++) begin
                    localparam ROM_EP_OFFSET = LUT_ROM_SIZE + calcROMOffset(USB_DEV_EP_CONF, confIdx, ifaceIdx, epIdx) + FIXED_ROM_EP_OFFSET;
                    `INIT_ROM(ROM_EP_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::EndpointDescriptorHeader)
                    `INIT_ROM(ROM_EP_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::EndpointDescriptorBodyBytes, USB_DEV_EP_CONF.devConfigs[confIdx].ifaces[ifaceIdx].endpointDescs[epIdx])
                end
            end
        end

        // Optional string descriptors:
        if (USB_DEV_EP_CONF.stringDescCount > 0) begin
            localparam ROM_STR_OFFSET = LUT_ROM_SIZE + calcROMOffset(USB_DEV_EP_CONF, {24'b0, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations}, 0, 0);
            `INIT_ROM_IDX_LUT(ROM_STR_OFFSET, {24'b0, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations})

            // String Descriptor Zero provides a list of supported languages!
            `INIT_ROM(ROM_STR_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::StringDescriptorZeroHeader)
            `INIT_ROM(ROM_STR_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, usb_desc_pkg::StringDescriptorZeroBodyBytes, USB_DEV_EP_CONF.supportedLanguages)

            localparam FIXED_ROM_STR_OFFSET = ROM_STR_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES + usb_desc_pkg::StringDescriptorZeroBodyBytes;

            // Now traverse all given string descriptors
            for (strDescIdx = 0; strDescIdx < USB_DEV_EP_CONF.stringDescCount; strDescIdx++) begin
                localparam ROM_STR_DESC_OFFSET = FIXED_ROM_STR_OFFSET + calcRelativeStrDescOffset(USB_DEV_EP_CONF, strDescIdx);

                `INIT_ROM_IDX_LUT(ROM_STR_DESC_OFFSET, {24'b0, USB_DEV_EP_CONF.deviceDesc.bNumConfigurations} + 1 + strDescIdx)

                `INIT_ROM(ROM_STR_DESC_OFFSET, usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, USB_DEV_EP_CONF.stringDescs[strDescIdx])
                `INIT_ROM_STR(ROM_STR_DESC_OFFSET + usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, USB_DEV_EP_CONF.stringDescs[strDescIdx].bLength - usb_desc_pkg::DESCRIPTOR_HEADER_BYTES, USB_DEV_EP_CONF.stringDescs[strDescIdx], usb_desc_pkg::DESCRIPTOR_HEADER_BYTES)
            end
        end
    endgenerate

endmodule
