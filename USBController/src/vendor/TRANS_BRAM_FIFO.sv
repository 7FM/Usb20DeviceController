module TRANS_BRAM_FIFO #(
    parameter ADDR_WID = 9,
    parameter DATA_WID = 8,
    parameter ENTRIES = 0
)(
    input logic clk_i,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone_i,
    input logic fillTransSuccess_i,
    input logic dataValid_i,
    input logic [DATA_WID-1:0] data_i,
    output logic full_o,

    input logic popTransDone_i,
    input logic popTransSuccess_i,
    input logic popData_i,
    output logic dataAvailable_o,
    output logic isLast_o,
    output logic [DATA_WID-1:0] data_o
);

    logic wEn;
    logic rEn;
    logic [ADDR_WID-1:0] next_rAddr;
    logic [ADDR_WID-1:0] wAddr, rAddr;
    logic [DATA_WID-1:0] wData, rData;

    mem #(
        .DEPTH(ENTRIES == 0 ? 2**ADDR_WID : ENTRIES),
        .DATA_WID(DATA_WID)
    ) dualportMem (
        .clk_i(clk_i),
        .wEn_i(wEn),
        .wAddr_i(wAddr),
        .wData_i(wData),
        .rAddr_i(rEn ? next_rAddr : rAddr),
        .rData_o(rData)
    );

    TRANS_FIFO #(
        .ADDR_WID(ADDR_WID),
        .DATA_WID(DATA_WID),
        .ENTRIES(ENTRIES == 0 ? 2**ADDR_WID : ENTRIES)
    ) fifo (
        .clk_i(clk_i),
        .wEn_o(wEn),
        .wAddr_o(wAddr),
        .wData_o(wData),
        .rEn_o(rEn),
        .rAddr_o(rAddr),
        .next_rAddr_o(next_rAddr),
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
        .isLast_o(isLast_o),
        .data_o(data_o)
    );

endmodule
