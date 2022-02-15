module echo_endpoints #(
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam ENDPOINTS = USB_DEV_EP_CONF.endpointCount + 1
)(
    input logic clk12_i,

    output logic [ENDPOINTS-2:0] EP_IN_popTransDone_o,
    output logic [ENDPOINTS-2:0] EP_IN_popTransSuccess_o,
    output logic [ENDPOINTS-2:0] EP_IN_popData_o,
    input logic [ENDPOINTS-2:0] EP_IN_dataAvailable_i,
    input logic [8*(ENDPOINTS-1) - 1:0] EP_IN_data_i,

    output logic [ENDPOINTS-2:0] EP_OUT_fillTransDone_o,
    output logic [ENDPOINTS-2:0] EP_OUT_fillTransSuccess_o,
    output logic [ENDPOINTS-2:0] EP_OUT_dataValid_o,
    output logic [8*(ENDPOINTS-1) - 1:0] EP_OUT_data_o,
    input logic [ENDPOINTS-2:0] EP_OUT_full_i
);

    //TODO simulate, test & fix!
generate
    genvar i;
    for (i = 0; i < ENDPOINTS - 1; i += 1) begin
        assign EP_IN_popData_o[i] = !EP_OUT_full_i[i];
        assign EP_IN_popTransSuccess_o[i] = 1'b1;
        logic transferDone;
        assign transferDone = !EP_IN_dataAvailable_i[i] || EP_OUT_full_i[i];
        assign EP_IN_popTransDone_o[i] = transferDone;

        assign EP_OUT_dataValid_o[i] = EP_IN_dataAvailable_i[i];
        assign EP_OUT_data_o[i * 8 +: 8] = EP_IN_data_i[i * 8 +: 8];

        assign EP_OUT_fillTransSuccess_o[i] = 1'b1;
        assign EP_OUT_fillTransDone_o[i] = transferDone;
    end
endgenerate

endmodule
