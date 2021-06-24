`include "config_pkg.sv"
`include "usb_ep_pkg.sv"

module usb#(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk48_i,
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_o,
    output logic USB_DN_o,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP_o
);

    logic usbResetDetected;
    logic ackUsbResetDetect;

    logic isSendingPhase;
    logic txDoneSending;
    logic rxDPPLGotSignal;

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48_i!
    logic rxAcceptNewData;
    logic [7:0] rxData;
    logic rxIsLastByte;
    logic rxDataValid;
    logic keepPacket;

    // Data Transmit Interface: synced with clk48_i!
    logic txReqSendPacket;
    logic txDataValid;
    logic txIsLastByte;
    logic [7:0] txData;
    logic txAcceptNewData;

    //TODO add additional layers for USB protocol and proper interfaces, some might be very very timing & latency sensitive

    usb_sie #() serialInterfaceEngine (
        .clk48_i(clk48_i),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
`ifdef RUN_SIM
        .USB_DN_o(USB_DN_o),
        .USB_DP_o(USB_DP_o),
`endif
        .USB_PULLUP_o(USB_PULLUP_o),

        // Serial Engine Services:
        .usbResetDetected_o(usbResetDetected), // Indicate that a usb reset detect signal was retrieved!
        .ackUsbResetDetect_i(ackUsbResetDetect), // Acknowledge that usb reset was seen and handled!

        // State information
        .txDoneSending_o(txDoneSending),
        .rxDPPLGotSignal_o(rxDPPLGotSignal),
        .isSendingPhase_i(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk48_i!
        //TODO port for reset receive module, required to reset the receive clock to synchronize with incoming signals!
        .rxAcceptNewData_i(rxAcceptNewData), // Caller indicates to be able to retrieve the next data byte
        .rxData_o(rxData), // data to be retrieved
        .rxIsLastByte_o(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid_o(rxDataValid), // rxData contains valid & new data
        .keepPacket_o(keepPacket), // should be tested when rxIsLastByte set to check whether an retrival error occurred

        // Data Transmit Interface: synced with clk48_i!
        .txReqSendPacket_i(txReqSendPacket), // Caller requests sending a new packet
        .txDataValid_i(txDataValid), // Indicates that txData contains valid & new data
        .txIsLastByte_i(txIsLastByte), // Indicates that the applied txData is the last byte to send (is read during handshake: txDataValid && txAcceptNewData)
        .txData_i(txData), // Data to be send: First byte should be PID, followed by the user data bytes, CRC is calculated and send automagically
        .txAcceptNewData_o(txAcceptNewData) // indicates that the send buffer can be filled
    );

    //TODO export
    // Endpoint interfaces
    logic [ENDPOINTS-1:0] EP_IN_popData;
    logic [ENDPOINTS-1:0] EP_IN_popTransDone;
    logic [ENDPOINTS-1:0] EP_IN_popTransSuccess;
    logic [ENDPOINTS-1:0] EP_IN_dataAvailable;
    logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_IN_dataOut;

    logic [ENDPOINTS-1:0] EP_OUT_dataValid;
    logic [ENDPOINTS-1:0] EP_OUT_fillTransDone;
    logic [ENDPOINTS-1:0] EP_OUT_fillTransSuccess;
    logic [ENDPOINTS-1:0] EP_OUT_full;
    logic [EP_DATA_WID*ENDPOINTS - 1:0] EP_OUT_dataIn;

    usb_pe #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF),
        .EP_DATA_WID(EP_DATA_WID),
        .EP_ADDR_WID(EP_ADDR_WID)
    ) usbProtocolEngine(
        .clk48_i(clk48_i),

        // Serial Engine Services:
        .usbResetDetected_i(usbResetDetected),
        .ackUsbResetDetect_o(ackUsbResetDetect),

        // State information
        .txDoneSending_i(txDoneSending),
        .rxDPPLGotSignal_i(rxDPPLGotSignal),
        .isSendingPhase_o(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk48_i!
        .rxAcceptNewData_o(rxAcceptNewData),
        .rxData_i(rxData),
        .rxIsLastByte_i(rxIsLastByte),
        .rxDataValid_i(rxDataValid),
        .keepPacket_i(keepPacket),

        // Data Transmit Interface: synced with clk48_i!
        .txReqSendPacket_o(txReqSendPacket),
        .txDataValid_o(txDataValid),
        .txIsLastByte_o(txIsLastByte),
        .txData_o(txData),
        .txAcceptNewData_i(txAcceptNewData),

        // Endpoint interfaces
        .EP_IN_popData_i(EP_IN_popData),
        .EP_IN_popTransDone_i(EP_IN_popTransDone),
        .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess),
        .EP_IN_dataAvailable_o(EP_IN_dataAvailable),
        .EP_IN_data_o(EP_IN_dataOut),

        .EP_OUT_dataValid_i(EP_OUT_dataValid),
        .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone),
        .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess),
        .EP_OUT_full_o(EP_OUT_full),
        .EP_OUT_data_i(EP_OUT_dataIn)
    );
endmodule
