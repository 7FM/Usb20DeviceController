`include "config_pkg.sv"
`include "usb_ep_pkg.sv"
`include "usb_packet_pkg.sv"
`include "usb_dev_req_pkg.sv"

module usb_endpoint_arbiter#(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1,
    localparam EP_SELECT_WID = $clog2(ENDPOINTS)
)(
    input logic clk12_i,

`ifdef DEBUG_LEDS
`ifdef DEBUG_USB_PE
`ifdef DEBUG_USB_EP0
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`else
`ifdef DEBUG_USB_EP_ARBITER
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif
`endif
`endif
`endif

    // Serial interface
    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,

    // Index used to select the endpoint
    input logic [EP_SELECT_WID-1:0] epSelect,
    input logic [1:0] upperTransStartPID,
    input logic gotTransStartPacket,
    input logic isHostIn,

    // Used for received data
    input logic fillTransDone,
    input logic fillTransSuccess,
    input logic EP_WRITE_EN,
    input logic [8-1:0] wData,
    output logic writeFifoFull,

    // Used for data to be output
    input logic popTransDone,
    input logic popTransSuccess,
    input logic EP_READ_EN,
    output logic readDataAvailable,
    output logic readIsLastPacketByte,
    output logic [8-1:0] rData,
    output logic epResponseValid,
    output logic epResponseIsHandshakePID,
    output logic [1:0] epResponsePacketID,

    // Device state output
    output logic [usb_packet_pkg::USB_DEV_ADDR_WID-1:0] deviceAddr,
    output logic [10:0] maxPacketSize,
    output logic isEpIsochronous,

    // External endpoint interfaces: Note that contrary to the USB spec, the names here are from the device centric!
    // Also note that there is no access to EP00 -> index 0 is for EP01, index 1 for EP02 and so on
    input logic [ENDPOINTS-2:0] EP_IN_popTransDone_i,
    input logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_IN_popData_i,
    output logic [ENDPOINTS-2:0] EP_IN_dataAvailable_o,
    output logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_o,

    input logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_i,
    input logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_i,
    input logic [ENDPOINTS-2:0] EP_OUT_dataValid_i,
    input logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_i,
    output logic [ENDPOINTS-2:0] EP_OUT_full_o
);

    // Status bit that indicated whether the next byte is the PID or actual data
    // This information can be simply obtained by watching gotTransStartPacket_i
    // but as this is likely needed for IN endpoints, the logic was centralized
    // to safe resources!
    logic byteIsData, nextByteIsData;
    logic resetDataToggle;

    logic [ENDPOINTS-1:0] EP_IN_full;

    logic [ENDPOINTS-1:0] EP_OUT_dataAvailable;
    logic [ENDPOINTS-1:0] EP_OUT_isLastPacketByte;
    logic [8*ENDPOINTS - 1:0] EP_OUT_dataOut;

    logic [ENDPOINTS-1:0] EP_respValid;
    // If epRespHandshakePID == 1'b1 then epRespPacketID is expected to be for a handshake, otherwise a DATA pid is expected
    logic [ENDPOINTS-1:0] EP_respHandshakePID;
    logic [2*ENDPOINTS - 1:0] EP_respPacketID;

    always_comb begin
        // Set this bit as soon as we have a handshake -> we skipped PID
        nextByteIsData = byteIsData;

        // A new transaction started
        if (gotTransStartPacket) begin
            // Ignore the first byte which is the PID / ignore all data if it is not a device request, we do not expect any input!
            nextByteIsData = 1'b0;
        end else if (!byteIsData && EP_WRITE_EN) begin
            // TODO EP_WRITE_EN is basically the signal for an handshake... but might change in the future!
            // Once we have skipped the PID we have data bytes!
            nextByteIsData = 1'b1;
        end
    end
    always_ff @(posedge clk12_i) begin
        byteIsData <= nextByteIsData;
    end

    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(8)) rDataMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_dataOut),
        .data_o(rData)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) fifoFullMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_IN_full),
        .data_o(writeFifoFull)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) readDataAvailableMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_dataAvailable),
        .data_o(readDataAvailable)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) readIsLastPacketByteMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_OUT_isLastPacketByte),
        .data_o(readIsLastPacketByte)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) responseValidMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respValid),
        .data_o(epResponseValid)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(1)) responseIsHandshakePIDMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respHandshakePID),
        .data_o(epResponseIsHandshakePID)
    );
    vector_mux#(.ELEMENTS(ENDPOINTS), .DATA_WID(2)) responsePacketIDMux (
        .dataSelect_i(epSelect),
        .dataVec_i(EP_respPacketID),
        .data_o(epResponsePacketID)
    );

    `define CREATE_EP_CASE(x)                                               \
        x: `EP_``x``_MODULE(epConfig) epX (                                 \
            .clk12_i(clk12_i),                                              \
            .gotTransStartPacket_i(gotTransStartPacket && isEpSelected),    \
            .isHostIn_i(isHostIn),                                          \
            .transStartTokenID_i(upperTransStartPID),                       \
            .byteIsData_i(byteIsData),                                      \
            .deviceConf_i(deviceConf),                                      \
            .resetDataToggle_i(resetDataToggle),                            \
                                                                            \
            /* Device IN interface */                                       \
            .EP_IN_fillTransDone_i(fillTransDone),                          \
            .EP_IN_fillTransSuccess_i(fillTransSuccess),                    \
            .EP_IN_dataValid_i(EP_WRITE_EN && isEpSelected),                \
            .EP_IN_data_i(wData),                                           \
            .EP_IN_full_o(EP_IN_full[x]),                                   \
                                                                            \
            .EP_IN_popTransDone_i(EP_IN_popTransDone_i[x-1]),               \
            .EP_IN_popTransSuccess_i(EP_IN_popTransSuccess_i[x-1]),         \
            .EP_IN_popData_i(EP_IN_popData_i[x-1]),                         \
            .EP_IN_dataAvailable_o(EP_IN_dataAvailable_o[x-1]),             \
            .EP_IN_data_o(EP_IN_data_o[(x-1) * 8 +: 8]),                    \
                                                                            \
            /* Device OUT interface */                                      \
            .EP_OUT_fillTransDone_i(EP_OUT_fillTransDone_i[x-1]),           \
            .EP_OUT_fillTransSuccess_i(EP_OUT_fillTransSuccess_i[x-1]),     \
            .EP_OUT_dataValid_i(EP_OUT_dataValid_i[x-1]),                   \
            .EP_OUT_data_i(EP_OUT_data_i[(x-1) * 8 +: 8]),                  \
            .EP_OUT_full_o(EP_OUT_full_o[x-1]),                             \
                                                                            \
            .EP_OUT_popTransDone_i(popTransDone),                           \
            .EP_OUT_popTransSuccess_i(popTransSuccess),                     \
            .EP_OUT_popData_i(EP_READ_EN && isEpSelected),                  \
            .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[x]),               \
            .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[x]),         \
            .EP_OUT_data_o(EP_OUT_dataOut[x * 8 +: 8]),                     \
                                                                            \
            .respValid_o(EP_respValid[x]),                                  \
            .respHandshakePID_o(EP_respHandshakePID[x]),                    \
            .respPacketID_o(EP_respPacketID[x * 2 +: 2])                    \
        )

    logic [usb_dev_req_pkg::USB_DEV_CONF_WID-1:0] deviceConf;

    // Endpoint 0 has its own implementation as it has to handle some unique requests!
    logic isEp0Selected;
    assign isEp0Selected = epSelect == 0;
    `EP_0_MODULE(USB_DEV_EP_CONF) ep0 (
        .clk12_i(clk12_i),

`ifdef DEBUG_LEDS
`ifdef DEBUG_USB_PE
`ifdef DEBUG_USB_EP0
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`endif
`endif
`endif

        // Endpoint 0 handles the decice state!
        .usbResetDetected_i(usbResetDetected_i),
        .ackUsbResetDetect_o(ackUsbResetDetect_o),
        .deviceAddr_o(deviceAddr),
        .deviceConf_o(deviceConf),
        .resetDataToggle_o(resetDataToggle),

        .transStartTokenID_i(upperTransStartPID),
        .gotTransStartPacket_i(gotTransStartPacket && isEp0Selected),
        .byteIsData_i(byteIsData),

        // Device IN interface
        .EP_IN_fillTransDone_i(fillTransDone),
        .EP_IN_fillTransSuccess_i(fillTransSuccess),
        .EP_IN_dataValid_i(EP_WRITE_EN && isEp0Selected),
        .EP_IN_data_i(wData),
        .EP_IN_full_o(EP_IN_full[0]),

        // Device OUT interface
        .EP_OUT_popTransDone_i(popTransDone),
        .EP_OUT_popTransSuccess_i(popTransSuccess),
        .EP_OUT_popData_i(EP_READ_EN && isEp0Selected),
        .EP_OUT_dataAvailable_o(EP_OUT_dataAvailable[0]),
        .EP_OUT_isLastPacketByte_o(EP_OUT_isLastPacketByte[0]),
        .EP_OUT_data_o(EP_OUT_dataOut[0 * 8 +: 8]),
        .respValid_o(EP_respValid[0]),
        .respHandshakePID_o(EP_respHandshakePID[0]),
        .respPacketID_o(EP_respPacketID[0 +: 2])
    );

    generate
        genvar i;
        for (i = 1; i < ENDPOINTS; i = i + 1) begin

            localparam usb_ep_pkg::EndpointConfig epConfig = USB_DEV_EP_CONF.epConfs[i-1];

            if (!epConfig.isControlEP && epConfig.conf.nonControlEp.epTypeDevIn == usb_ep_pkg::NONE && epConfig.conf.nonControlEp.epTypeDevOut == usb_ep_pkg::NONE) begin
                $fatal("Wrong number of endpoints specified! Got endpoint type NONE for ep%i", i);
            end

            logic isEpSelected;
            assign isEpSelected = i == epSelect;

            case (i)
                `CREATE_EP_CASE(1);
                `CREATE_EP_CASE(2);
                `CREATE_EP_CASE(3);
                `CREATE_EP_CASE(4);
                `CREATE_EP_CASE(5);
                `CREATE_EP_CASE(6);
                `CREATE_EP_CASE(7);
                `CREATE_EP_CASE(8);
                `CREATE_EP_CASE(9);
                `CREATE_EP_CASE(10);
                `CREATE_EP_CASE(11);
                `CREATE_EP_CASE(12);
                `CREATE_EP_CASE(13);
                `CREATE_EP_CASE(14);
                `CREATE_EP_CASE(15);
                default:
                    $fatal("Invalid Endpoint count!");
            endcase
        end
    endgenerate

//====================================================================================
//===================================Helper modules===================================
//====================================================================================

    usb_pe_rom #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) epConstants(
        .epSelect(epSelect),
        .isHostIn(isHostIn),

        .maxPacketSize(maxPacketSize),
        .isEpIsochronous(isEpIsochronous)
    );

`ifdef DEBUG_LEDS
`ifdef DEBUG_USB_PE
`ifdef DEBUG_USB_EP_ARBITER
    logic inv_LED_R;
    logic inv_LED_G;
    logic inv_LED_B;
    initial begin
        inv_LED_R = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_G = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_B = 1'b0; // a value of 1 turns the LEDs off!
    end
    always_ff @(posedge clk12_i) begin
        inv_LED_G <= EP_IN_full[1];
        inv_LED_R <= epSelect == 1;
        inv_LED_B <= EP_WRITE_EN/* && epSelect == 1*/;
    end

    assign LED_R = !inv_LED_R;
    assign LED_G = !inv_LED_G;
    assign LED_B = !inv_LED_G;
`endif
`endif
`endif

endmodule
