`include "config_pkg.sv"

module usb#(
    parameter ENDPOINTS = 1,
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic clk48,
`ifdef RUN_SIM
    input logic USB_DP,
    input logic USB_DN,
    output logic USB_DP_OUT,
    output logic USB_DN_OUT,
`else
    inout logic USB_DP,
    inout logic USB_DN,
`endif
    output logic USB_PULLUP
);

    logic usbResetDetected;
    logic ackUsbResetDetect;

    logic isSendingPhase;

    // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
    // Data Receive Interface: synced with clk48!
    logic rxAcceptNewData;
    logic [7:0] rxData;
    logic rxIsLastByte;
    logic rxDataValid;
    logic keepPacket;

    // Data Transmit Interface: synced with clk48!
    logic txReqSendPacket;
    logic txDataValid;
    logic txIsLastByte;
    logic [7:0] txData;
    logic txAcceptNewData;

    //TODO add additional layers for USB protocol and proper interfaces, some might be very very timing & latency sensitive

    usb_sie #() serialInterfaceEngine (
        .clk48(clk48),
        .USB_DN(USB_DN),
        .USB_DP(USB_DP),
`ifdef RUN_SIM
        .USB_DN_OUT(USB_DN_OUT),
        .USB_DP_OUT(USB_DP_OUT),
`endif
        .USB_PULLUP(USB_PULLUP),

        // Serial Engine Services:
        .usbResetDetected(usbResetDetected), // Indicate that a usb reset detect signal was retrieved!
        .ackUsbResetDetect(ackUsbResetDetect), // Acknowledge that usb reset was seen and handled!

        // State information
        .isSendingPhase(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk48!
        //TODO port for reset receive module, required to reset the receive clock to synchronize with incoming signals!
        .rxAcceptNewData(rxAcceptNewData), // Caller indicates to be able to retrieve the next data byte
        .rxData(rxData), // data to be retrieved
        .rxIsLastByte(rxIsLastByte), // indicates that the current byte at rxData is the last one
        .rxDataValid(rxDataValid), // rxData contains valid & new data
        .keepPacket(keepPacket), // should be tested when rxIsLastByte set to check whether an retrival error occurred

        // Data Transmit Interface: synced with clk48!
        .txReqSendPacket(txReqSendPacket), // Caller requests sending a new packet
        .txDataValid(txDataValid), // Indicates that txData contains valid & new data
        .txIsLastByte(txIsLastByte), // Indicates that the applied txData is the last byte to send (is read during handshake: txDataValid && txAcceptNewData)
        .txData(txData), // Data to be send: First byte should be PID, followed by the user data bytes, CRC is calculated and send automagically
        .txAcceptNewData(txAcceptNewData) // indicates that the send buffer can be filled
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
        .ENDPOINTS(ENDPOINTS),
        .EP_DATA_WID(EP_DATA_WID),
        .EP_ADDR_WID(EP_ADDR_WID)
    ) usbProtocolEngine(
        .clk48(clk48),

        // Serial Engine Services:
        .usbResetDetected(usbResetDetected),
        .ackUsbResetDetect(ackUsbResetDetect),

        // State information
        .isSendingPhase(isSendingPhase),

        // Data receive and data transmit interfaces may only be used mutually exclusive in time and atomic transactions: sending/receiving a packet!
        // Data Receive Interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData),
        .rxData(rxData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .keepPacket(keepPacket),

        // Data Transmit Interface: synced with clk48!
        .txReqSendPacket(txReqSendPacket),
        .txDataValid(txDataValid),
        .txIsLastByte(txIsLastByte),
        .txData(txData),
        .txAcceptNewData(txAcceptNewData),

        // Endpoint interfaces
        .EP_IN_popData(EP_IN_popData),
        .EP_IN_popTransDone(EP_IN_popTransDone),
        .EP_IN_popTransSuccess(EP_IN_popTransSuccess),
        .EP_IN_dataAvailable(EP_IN_dataAvailable),
        .EP_IN_dataOut(EP_IN_dataOut),

        .EP_OUT_dataValid(EP_OUT_dataValid),
        .EP_OUT_fillTransDone(EP_OUT_fillTransDone),
        .EP_OUT_fillTransSuccess(EP_OUT_fillTransSuccess),
        .EP_OUT_full(EP_OUT_full),
        .EP_OUT_dataIn(EP_OUT_dataIn)
    );
endmodule
