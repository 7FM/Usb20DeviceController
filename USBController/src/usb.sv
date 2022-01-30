`include "config_pkg.sv"
`include "usb_ep_pkg.sv"

module usb#(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk48_i,
    input logic clk12_i,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    // Raw USB interface
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_o,
    output logic USB_DN_o,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP_o,

    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    input logic [ENDPOINTS-2:0] EP_IN_popTransDone_i,
    input logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_IN_popData_i,
    output logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o,
    output logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o, // Note the EP dependent timing conditions compared to the EP_IN_dataAvailable_o flag!

    input logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i,
    input logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_OUT_dataValid_i,
    input logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i,
    output logic [ENDPOINTS-2:0] EP_OUT_full_o
);

//====================================================================================
//============================USB Serial Interface Engine=============================
//====================================================================================

    logic usbResetDetected;
    logic ackUsbResetDetect;

    logic isSendingPhase;
    logic txDoneSending;
    logic rxDPPLGotSignal;

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk12_i!
    logic rxAcceptNewData;
    logic [7:0] rxData;
    logic rxIsLastByte;
    logic rxDataValid;
    logic keepPacket;

    // Data Transmit Interface: synced with clk12_i!
    logic txReqSendPacket;
    logic txDataValid;
    logic txIsLastByte;
    logic [7:0] txData;
    logic txAcceptNewData;

    usb_sie #() serialInterfaceEngine (
        .clk48_i(clk48_i),
        .clk12_i(clk12_i),

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
        .rxDPPLGotSignal_o(rxDPPLGotSignal), // clk48_i
        .isSendingPhase_i(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk12_i!
        .rxAcceptNewData_i(rxAcceptNewData), // Caller indicates to be able to retrieve the next data byte
        .rxData_o(rxData), // data to be retrieved
        .rxIsLastByte_o(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid_o(rxDataValid), // rxData contains valid & new data
        .keepPacket_o(keepPacket), // should be tested when rxIsLastByte set to check whether an retrival error occurred

        // Data Transmit Interface: synced with clk12_i!
        .txReqSendPacket_i(txReqSendPacket), // Caller requests sending a new packet
        .txDataValid_i(txDataValid), // Indicates that txData contains valid & new data
        .txIsLastByte_i(txIsLastByte), // Indicates that the applied txData is the last byte to send (is read during handshake: txDataValid && txAcceptNewData)
        .txData_i(txData), // Data to be send: First byte should be PID, followed by the user data bytes, CRC is calculated and send automagically
        .txAcceptNewData_o(txAcceptNewData) // indicates that the send buffer can be filled
    );


//====================================================================================
//================================USB Protocol Engine=================================
//====================================================================================

    logic readTimerRst;
    logic packetWaitTimeout;

    usb_pe #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) usbProtocolEngine(
        .clk12_i(clk12_i),

`ifdef DEBUG_LEDS
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`endif

        // Serial Engine Services:
        .usbResetDetected_i(usbResetDetected),
        .ackUsbResetDetect_o(ackUsbResetDetect),

        // USB Timeout Services:
        .readTimerRst_o(readTimerRst),
        .packetWaitTimeout_i(packetWaitTimeout),

        // State information
        .txDoneSending_i(txDoneSending),
        .isSendingPhase_o(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk12_i!
        .rxAcceptNewData_o(rxAcceptNewData),
        .rxData_i(rxData),
        .rxIsLastByte_i(rxIsLastByte),
        .rxDataValid_i(rxDataValid),
        .keepPacket_i(keepPacket),

        // Data Transmit Interface: synced with clk12_i!
        .txReqSendPacket_o(txReqSendPacket),
        .txDataValid_o(txDataValid),
        .txIsLastByte_o(txIsLastByte),
        .txData_o(txData),
        .txAcceptNewData_i(txAcceptNewData),

        // Endpoint interfaces
        .EP_IN_popData_i(EP_IN_popData_i),
        .EP_IN_popTransDone_i(EP_IN_popTransDone_i),
        .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i),
        .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o),
        .EP_IN_data_o(EP_IN_data_o),

        .EP_OUT_dataValid_i(EP_OUT_dataValid_i),
        .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i),
        .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .EP_OUT_full_o(EP_OUT_full_o),
        .EP_OUT_data_i(EP_OUT_data_i)
    );

//====================================================================================
//===============================USB timeout submodules===============================
//====================================================================================

    usb_timeout readTimer (
        .clk48_i(clk48_i),
        .clk12_i(clk12_i),
        .rst_i(readTimerRst),
        .rxGotSignal_i(rxDPPLGotSignal),
        .rxTimeout_o(packetWaitTimeout)
    );

endmodule
