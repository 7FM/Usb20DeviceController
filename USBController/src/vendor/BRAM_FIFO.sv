module BRAM_FIFO #(
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic clk_i,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone_i,
    input logic fillTransSuccess_i,
    input logic dataValid_i,
    input logic [EP_DATA_WID-1:0] data_i,
    output logic full_o,

    input logic popTransDone_i,
    input logic popTransSuccess_i,
    input logic popData_i,
    output logic dataAvailable_o,
    output logic [EP_DATA_WID-1:0] data_o
);

    logic wEn;
    logic [EP_ADDR_WID-1:0] wAddr, rAddr;
    logic [EP_DATA_WID-1:0] wData, rData;

    mem #(
        .DEPTH(2**EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) dualportMem (
        .clk_i(clk_i),
        .wEn_i(wEn),
        .wAddr_i(wAddr),
        .wData_i(wData),
        .rAddr_i(rAddr),
        .rData_o(rData)
    );

    FIFO #(
        .ADDR_WID(EP_ADDR_WID),
        .DATA_WID(EP_DATA_WID)
    ) fifo (
        .clk_i(clk_i),
        .wEn_o(wEn),
        .wAddr_o(wAddr),
        .wData_o(wData),
        .rAddr_o(rAddr),
        .rData_i(rData),
        .fillTransDone_i(fillTransDone_i),
        .fillTransSuccess_i(fillTransSuccess_i),
        .dataValid_i(dataValid_i),
        .full_o(full_o),
        .data_i(data_i),
        .popTransDone_i(popTransDone_i),
        .popTransSuccess_i(popTransSuccess_i),
        .popData_i(popData_i),
        .dataAvailable_o(dataAvailable_o),
        .data_o(data_o)
    );

endmodule
