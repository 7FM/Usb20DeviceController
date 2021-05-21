`include "config_pkg.sv"

module usb#()(
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

    logic usbResetDetect;
    logic ackUsbResetDetect;

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

        .usbResetDetect(usbResetDetect), // Indicate that a usb reset detect signal was retrieved!
        .ackUsbResetDetect(ackUsbResetDetect), // Acknowledge that usb reset was seen and handled!

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

    usb_pe #() usbProtocolEngine(
        .clk48(clk48),

        .usbResetDetect,
        .ackUsbResetDetect,

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
        .txAcceptNewData(txAcceptNewData)
    );

endmodule
