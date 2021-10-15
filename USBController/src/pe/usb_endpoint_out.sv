`include "usb_ep_pkg.sv"

`include "util_macros.sv"

module usb_endpoint_out #(
    parameter usb_ep_pkg::EndpointConfig EP_CONF,
    localparam USB_DEV_CONF_WID = 8
)(
    input logic clk12_i,

    input logic gotTransStartPacket_i,
`MUTE_LINT(UNUSED)
    input logic [1:0] transStartTokenID_i, // unused, should always be an IN token! TODO add sanity checks?
    input logic [USB_DEV_CONF_WID-1:0] deviceConf_i, // unused
`UNMUTE_LINT(UNUSED)
    input logic resetDataToggle_i,

    // Device OUT interface
    input logic EP_OUT_fillTransDone_i,
    input logic EP_OUT_fillTransSuccess_i,
    input logic EP_OUT_dataValid_i,
    input logic [7:0] EP_OUT_data_i,
    output logic EP_OUT_full_o,

    input logic EP_OUT_popTransDone_i,
    input logic EP_OUT_popTransSuccess_i,
    input logic EP_OUT_popData_i,
    output logic EP_OUT_dataAvailable_o,
    output logic EP_OUT_isLastPacketByte_o,
    output logic [7:0] EP_OUT_data_o,

    output logic respValid_o,
    output logic respHandshakePID_o,
    output logic [1:0] respPacketID_o
);

    logic dataToggleState;
generate
    if (!EP_CONF.isControlEP && EP_CONF.conf.nonControlEp.epTypeDevIn == usb_ep_pkg::ISOCHRONOUS) begin
        // For isochronous endpoints the data toggle bits are dont cares -> always set to 0
        assign dataToggleState = 1'b0;
    end else begin
        // Else for bulk/interrupt endpoint’s toggle sequence is initialized to DATA0
        // when the endpoint experiences any configuration event (configuration events are explained in Sections 9.1.1.5 and 9.4.5)
        // And updated at every successfull transaction!
        always_ff @(posedge clk12_i) begin
            dataToggleState <= resetDataToggle_i ? 1'b0 : ((EP_OUT_popTransDone_i && EP_OUT_fillTransSuccess_i) ^ dataToggleState);
        end
    end
endgenerate

    logic dataAvailable;
    logic epOutHandshake;
    assign epOutHandshake = EP_OUT_dataAvailable_o && EP_OUT_popData_i;

    logic awaitBRAMData;
    always_ff @(posedge clk12_i) begin
        // wait for bram data after each handshake
        // also set awaitBRAMData if no data is available -> once data is available, it must be loaded first too!
        //TODO this is critical if we read the last byte!
        awaitBRAMData <= (awaitBRAMData ? 1'b0 : epOutHandshake) || !dataAvailable;
    end

    localparam EP_ADDR_WID = 9;
    localparam EP_DATA_WID = 8;

    //TODO configure size?
    BRAM_FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) fifoXOut(
        .clk_i(clk12_i),

        .fillTransDone_i(EP_OUT_fillTransDone_i),
        .fillTransSuccess_i(EP_OUT_fillTransSuccess_i),
        .dataValid_i(EP_OUT_dataValid_i),
        .data_i(EP_OUT_data_i),
        .full_o(EP_OUT_full_o),

        .popTransDone_i(EP_OUT_popTransDone_i),
        .popTransSuccess_i(EP_OUT_popTransSuccess_i),
        .popData_i(EP_OUT_popData_i && !awaitBRAMData), //TODO avoid multiple pops when waiting for BRAM! Effectively half the read speed!
        .dataAvailable_o(dataAvailable),
        .data_o(EP_OUT_data_o)
    );

    // If this is polled, then receiving was successfull & and a handshake is expected
    logic noDataAvailable;
    always_ff @(posedge clk12_i) begin
        noDataAvailable <= gotTransStartPacket_i ? dataAvailable : noDataAvailable;
    end

    assign respValid_o = noDataAvailable || !awaitBRAMData;
    //TODO test if this approach works!
    //TODO we get this information too late!
    // assign EP_OUT_dataAvailable_o = !awaitBRAMData && dataAvailable;
    always_ff @(posedge clk12_i) begin
        EP_OUT_dataAvailable_o <= !awaitBRAMData && dataAvailable;
    end
    // -> dely dataAvailable by one cycle & use the current value of dataAvailable as isLastPacketByte
    // data_o should not change with this extra cycle as the BRAM has an latency of 1 cycle 
    assign EP_OUT_isLastPacketByte_o = !dataAvailable;
    // anwser with NAK in case we have no data yet! (noDataAvailable is true)
    // Otherwise this is a DATAx PID
    assign respHandshakePID_o = noDataAvailable;
    // NAK is 2'b10 -> we can merge the DATAx and NAK cases
    assign respPacketID_o = {noDataAvailable || dataToggleState, 1'b0};

endmodule
