`include "usb_ep_pkg.sv"
`include "usb_packet_pkg.sv"

`include "util_macros.sv"

module usb_endpoint_in #(
    parameter usb_ep_pkg::EndpointConfig EP_CONF,
    localparam USB_DEV_CONF_WID = 8
)(
    input logic clk12_i,
`MUTE_LINT(UNUSED)
    input logic gotTransStartPacket_i,
    input logic [1:0] transStartTokenID_i,
    input logic [USB_DEV_CONF_WID-1:0] deviceConf_i, // unused
`UNMUTE_LINT(UNUSED)
    // Status bit that indicated whether the next byte is the PID or actual data
    // This information can be simply obtained by watching gotTransStartPacket_i
    // but as this is likely needed for IN endpoints, the logic was centralized
    // to safe resources!
    input logic byteIsData_i,
    input logic resetDataToggle_i,

    // Device IN interface
    input logic EP_IN_fillTransDone_i,
    input logic EP_IN_fillTransSuccess_i,
    input logic EP_IN_dataValid_i,
    input logic [7:0] EP_IN_data_i,
    output logic EP_IN_full_o,

    input logic EP_IN_popTransDone_i,
    input logic EP_IN_popTransSuccess_i,
    input logic EP_IN_popData_i,
    output logic EP_IN_dataAvailable_o,
    output logic [7:0] EP_IN_data_o,

    output logic respValid_o,
    output logic respHandshakePID_o,
    output logic [1:0] respPacketID_o
);

generate
if (!EP_CONF.isControlEP && EP_CONF.conf.nonControlEp.epTypeDevIn != usb_ep_pkg::NONE) begin

    logic ignorePacket;

    if (!EP_CONF.isControlEP && EP_CONF.conf.nonControlEp.epTypeDevIn == usb_ep_pkg::ISOCHRONOUS) begin
        // For isochronous endpoints the data toggle bits are dont cares -> never ignore the packet due to DATA0 or DATA1 PID!
        assign ignorePacket = 1'b0;
    end else begin
        // Else for bulk/interrupt endpoint’s toggle sequence is initialized to DATA0
        // when the endpoint experiences any configuration event (configuration events are explained in Sections 9.1.1.5 and 9.4.5)
        // And updated at every successfull transaction!
        logic expectedDataToggleBit;

        always_ff @(posedge clk12_i) begin
            // Ignore the packet if we expect a different data toggle bit -> packet is repeated
            ignorePacket <= byteIsData_i ? ignorePacket : EP_IN_data_i[usb_packet_pkg::DATA_0_1_TOGGLE_OFFSET] != expectedDataToggleBit;

            // Update the data toggle bit upon successful transaction that was not ignored
            expectedDataToggleBit <= resetDataToggle_i ? 1'b0 : ((EP_IN_fillTransDone_i && EP_IN_fillTransSuccess_i) ^ expectedDataToggleBit);
        end
    end

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    //TODO configure size?
    TRANS_BRAM_FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) fifoXIn(
        .clk_i(clk12_i),

        .fillTransDone_i(EP_IN_fillTransDone_i),
        .fillTransSuccess_i(EP_IN_fillTransSuccess_i),
        .dataValid_i(EP_IN_dataValid_i && !ignorePacket && byteIsData_i),
        .data_i(EP_IN_data_i),
        .full_o(EP_IN_full_o),

        .popTransDone_i(EP_IN_popTransDone_i),
        .popTransSuccess_i(EP_IN_popTransSuccess_i),
        .popData_i(EP_IN_popData_i),
        .dataAvailable_o(EP_IN_dataAvailable_o),
        `MUTE_PIN_CONNECT_EMPTY(isLast_o),
        .data_o(EP_IN_data_o)
    );

    assign respPacketID_o = usb_packet_pkg::RES_ACK;

end else begin
    // Control EP or NONE type -> react with a STALL
    assign respPacketID_o = usb_packet_pkg::RES_STALL;

    // Dummy signals
    assign EP_IN_data_o = 8'b0; 
    assign EP_IN_dataAvailable_o = 1'b0; 
    assign EP_IN_full_o = 1'b1; 
end
endgenerate

    // If this is polled, then receiving was successfull & and a handshake is expected
    assign respValid_o = 1'b1;
    assign respHandshakePID_o = 1'b1;

endmodule
