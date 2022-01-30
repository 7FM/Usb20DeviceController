`include "util_macros.sv"

module FIFO #(
    parameter ADDR_WID = 9,
    parameter DATA_WID = 8,
    parameter ENTRIES = 0
)(
    input logic clk_i,

    // Backend Memory interface: typical dual port interface
    output logic wEn_o,
    output logic [ADDR_WID-1:0] wAddr_o,
    output logic [DATA_WID-1:0] wData_o,
    output logic [ADDR_WID-1:0] rAddr_o,
    input logic [DATA_WID-1:0] rData_i,

    input logic dataValid_i,
    input logic [DATA_WID-1:0] data_i,
    output logic full_o,

    input logic popData_i,
    output logic dataAvailable_o,
    output logic isLast_o,
    output logic [DATA_WID-1:0] data_o //NOTE: data_o will be delayed by one cycle compared to the rAddr_o signal! (if BRAM is used as memory backend)
);

    logic [ADDR_WID:0] dataCounter, readCounter, next_dataCounter, next_readCounter;

    // the data available flag compares registers -> okish combinatorial path
    assign dataAvailable_o = readCounter != dataCounter;
    assign isLast_o = next_readCounter == dataCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full_o && dataValid_i;
    assign readHandshake = dataAvailable_o && popData_i;

    // Attach signals to memory interface
    assign wEn_o = writeHandshake;
    assign wAddr_o = dataCounter[ADDR_WID-1:0];
    assign wData_o = data_i;
    assign rAddr_o = readCounter[ADDR_WID-1:0];
    assign data_o = rData_i;

    localparam MAX_IDX = ENTRIES - 1;

generate
    if (ENTRIES <= 0 || ENTRIES == 2**ADDR_WID) begin
        // if entries == -1 is set then we assume that the entire address space is memory backed
        // Else if entries is set we can manually test this assumption and optimize if possible!
        assign next_dataCounter = dataCounter + 1; // Abuses overflows to avoid wrap around logic
        assign next_readCounter = readCounter + 1; // Abuses overflows to avoid wrap around logic
    end else begin
        // Otherwise not the entire address space is memory backed -> we need to make bounds checks to avoid invalid states & memory requests
        assign next_dataCounter = dataCounter[ADDR_WID-1:0] == MAX_IDX[ADDR_WID-1:0] ? {!dataCounter[ADDR_WID], {ADDR_WID{1'b0}}} : dataCounter + 1;
        assign next_readCounter = readCounter[ADDR_WID-1:0] == MAX_IDX[ADDR_WID-1:0] ? {!readCounter[ADDR_WID], {ADDR_WID{1'b0}}} : readCounter + 1;
    end

    assign full_o = !popData_i && (dataCounter[ADDR_WID] != readCounter[ADDR_WID]
                               && dataCounter[ADDR_WID-1:0] == readCounter[ADDR_WID-1:0]);

    initial begin
        dataCounter = 0;
        readCounter = 0;
    end

    always_ff @(posedge clk_i) begin
        // Write actions
        if (writeHandshake) begin
            dataCounter <= next_dataCounter;
        end

        // Read actions
        if (readHandshake) begin
            readCounter <= next_readCounter;
        end
    end
endgenerate

endmodule
