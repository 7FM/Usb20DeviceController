`include "config_pkg.sv"
`include "util_macros.sv"

`ifdef RUN_SIM
module sim_top #(
    localparam usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF = usb_ep_pkg::DefaultUsbDeviceEpConfig,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic CLK,
    input logic rxCLK12,
    input logic txCLK12,
    `MUTE_LINT(UNUSED)
    input logic dummyPin,
    `UNMUTE_LINT(UNUSED)
    input logic rxRST,

    // Data send interface: synced with txCLK12!
    input logic txReqSendPacket,
    output logic txAcceptNewData,
    input logic txIsLastByte,
    input logic txDataValid,
    input logic [7:0] txData,

    output logic sending,

    // Data receive interface: synced with rxCLK12!
    input logic rxAcceptNewData, // Backend indicates that it is able to retrieve the next data byte
    output logic rxIsLastByte, // indicates that the current byte at rxData is the last one
    output logic rxDataValid, // rxData contains valid & new data
    output logic [7:0] rxData, // data to be retrieved

    output logic keepPacket,

    // Timeout interface
    input logic resetTimeout,
    output logic gotTimeout,

    // Endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    output logic EP_CLK12,
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

    logic USB_DP;
    logic USB_DP_OUT;
    logic USB_DN;
    logic USB_DN_OUT;

    top uut(
        .CLK(CLK),
        .USB_DP(USB_DP),
        .USB_DP_OUT(USB_DP_OUT),
        .USB_DN(USB_DN),
        .USB_DN_OUT(USB_DN_OUT),
        `MUTE_PIN_CONNECT_EMPTY(USB_PULLUP),

        // Endpoint interfaces
        .clk12_o(EP_CLK12),
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

    sim_usb_tx_connection hostTxImitator(
        .txClk12(txCLK12),
        .USB_DP(USB_DP),
        .USB_DN(USB_DN),

        // Data send interface: synced with clk48!
        .txReqSendPacket(txReqSendPacket),
        .txAcceptNewData(txAcceptNewData),
        .txIsLastByte(txIsLastByte),
        .txDataValid(txDataValid),
        .txData(txData),

        .sending(sending)
    );

    sim_usb_rx_connection hostRxImitator(
        .CLK(CLK),
        .CLK12(rxCLK12),
        .USB_DP(USB_DP_OUT),
        .USB_DN(USB_DN_OUT),
        .rxRST(rxRST),

        // Data output interface: synced with clk48!
        .rxAcceptNewData(rxAcceptNewData),
        .rxIsLastByte(rxIsLastByte),
        .rxDataValid(rxDataValid),
        .rxData(rxData),
        .keepPacket(keepPacket),

        .resetTimeout(resetTimeout),
        .gotTimeout(gotTimeout)
    );


endmodule
`endif
