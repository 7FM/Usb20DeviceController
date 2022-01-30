`include "usb_ep_pkg.sv"

module usb_pe_rom #(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1,
    localparam EP_SELECT_WID = $clog2(ENDPOINTS),
    localparam MAX_PACKET_SIZE_WID = 11
)(
    input logic [EP_SELECT_WID-1:0] epSelect,
    input logic isHostIn,

    output logic [MAX_PACKET_SIZE_WID-1:0] maxPacketSize,
    output logic isEpIsochronous
);

genvar epIdx;
generate
    logic [MAX_PACKET_SIZE_WID*ENDPOINTS - 1:0] maxPacketSizeOutLut;

    assign maxPacketSizeOutLut[0 * MAX_PACKET_SIZE_WID +: MAX_PACKET_SIZE_WID] = {3'b0, USB_DEV_EP_CONF.deviceDesc.bMaxPacketSize0};

    for (epIdx = 0; epIdx < USB_DEV_EP_CONF.endpointCount; epIdx++) begin
        if (USB_DEV_EP_CONF.epConfs[epIdx].isControlEP) begin
            assign maxPacketSizeOutLut[(epIdx + 1) * MAX_PACKET_SIZE_WID +: MAX_PACKET_SIZE_WID] = {3'b0, USB_DEV_EP_CONF.epConfs[epIdx].conf.controlEpConf.maxPacketSize};
        end else begin
            assign maxPacketSizeOutLut[(epIdx + 1) * MAX_PACKET_SIZE_WID +: MAX_PACKET_SIZE_WID] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.maxPacketSize;
        end
    end

    assign maxPacketSize = maxPacketSizeOutLut[epSelect * MAX_PACKET_SIZE_WID +: MAX_PACKET_SIZE_WID];
endgenerate

generate
    if (USB_DEV_EP_CONF.endpointCount > 0) begin
        logic [USB_DEV_EP_CONF.endpointCount-1:0] isEpInIsochronousLUT;
        logic [USB_DEV_EP_CONF.endpointCount-1:0] isEpOutIsochronousLUT;

        for (epIdx = 0; epIdx < USB_DEV_EP_CONF.endpointCount; epIdx++) begin
            if (USB_DEV_EP_CONF.epConfs[epIdx].isControlEP) begin
                assign isEpInIsochronousLUT[epIdx] = 1'b0;
                assign isEpOutIsochronousLUT[epIdx] = 1'b0;
            end else begin
                assign isEpInIsochronousLUT[epIdx] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.epTypeDevIn == usb_ep_pkg::ISOCHRONOUS;
                assign isEpOutIsochronousLUT[epIdx] = USB_DEV_EP_CONF.epConfs[epIdx].conf.nonControlEp.epTypeDevOut == usb_ep_pkg::ISOCHRONOUS;
            end
        end

        // assign isEpIsochronous = {(isHostIn ? isEpOutIsochronousLUT : isEpInIsochronousLUT), 1'b0}[epSelect];
        assign isEpIsochronous = (|epSelect) && (isHostIn ? isEpOutIsochronousLUT[epSelect-1] : isEpInIsochronousLUT[epSelect-1]);
    end else begin
        assign isEpIsochronous = 1'b0;
    end
endgenerate

endmodule
