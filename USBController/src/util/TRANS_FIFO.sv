`include "util_macros.sv"

// transaction based FIFO
module TRANS_FIFO #(
    parameter ADDR_WID = 9,
    parameter DATA_WID = 8,
    parameter ENTRIES = 0
)(
    input logic clk_i,

    // Backend Memory interface: typical dual port interface
    output logic wEn_o,
    output logic [ADDR_WID-1:0] wAddr_o,
    output logic [DATA_WID-1:0] wData_o,
    output logic rEn_o,
    output logic [ADDR_WID-1:0] rAddr_o,
    output logic [ADDR_WID-1:0] next_rAddr_o,
    input logic [DATA_WID-1:0] rData_i,

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

    logic [ADDR_WID:0] dataCounter, readCounter;
    logic [ADDR_WID:0] transDataCounter, transReadCounter, next_transDataCounter, next_transReadCounter;

    // the data available flag compares registers -> okish combinatorial path
    assign dataAvailable_o = transReadCounter != dataCounter;
    assign isLast_o = next_transReadCounter == dataCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full_o && dataValid_i;
    assign readHandshake = dataAvailable_o && popData_i;

    // Attach signals to memory interface
    assign wEn_o = writeHandshake;
    assign wAddr_o = transDataCounter[ADDR_WID-1:0];
    assign wData_o = data_i;
    assign rEn_o = readHandshake;
    assign rAddr_o = transReadCounter[ADDR_WID-1:0];
    assign next_rAddr_o = next_transReadCounter[ADDR_WID-1:0];
    assign data_o = rData_i;

    localparam MAX_IDX = ENTRIES - 1;

generate
    if (ENTRIES <= 0 || ENTRIES == 2**ADDR_WID) begin
        // if entries == -1 is set then we assume that the entire address space is memory backed
        // Else if entries is set we can manually test this assumption and optimize if possible!
        assign next_transDataCounter = transDataCounter + 1; // Abuses overflows to avoid wrap around logic
        assign next_transReadCounter = transReadCounter + 1; // Abuses overflows to avoid wrap around logic
    end else begin
        // Otherwise not the entire address space is memory backed -> we need to make bounds checks to avoid invalid states & memory requests
        assign next_transDataCounter = transDataCounter[ADDR_WID-1:0] == MAX_IDX[ADDR_WID-1:0] ? {!transDataCounter[ADDR_WID], {ADDR_WID{1'b0}}} : transDataCounter + 1;
        assign next_transReadCounter = transReadCounter[ADDR_WID-1:0] == MAX_IDX[ADDR_WID-1:0] ? {!transReadCounter[ADDR_WID], {ADDR_WID{1'b0}}} : transReadCounter + 1;
    end

    assign full_o = transDataCounter[ADDR_WID] != readCounter[ADDR_WID]
                 && transDataCounter[ADDR_WID-1:0] == readCounter[ADDR_WID-1:0];

    initial begin
        dataCounter = 0;
        transDataCounter = 0;
        readCounter = 0;
        transReadCounter = 0;
    end

    always_ff @(posedge clk_i) begin
        // Write actions
        if (fillTransDone_i) begin
            // Write transaction is done
            if (fillTransSuccess_i) begin
                // if it was successful we want to update our permanent data counter
                dataCounter <= transDataCounter;
            end else begin
                // if it was unsuccessful we need to reset out transaction data counter
                transDataCounter <= dataCounter;
            end
        end else if (writeHandshake) begin
            // Else on normal handshake update the current transaction index
            transDataCounter <= next_transDataCounter;
        end

        // Read actions
        if (popTransDone_i) begin
            // Read transaction is done
            if (popTransSuccess_i) begin
                // if it was successful we want to update our permanent read counter
                readCounter <= transReadCounter;
            end else begin
                // if it was unsuccessful we need to reset out transaction read counter
                transReadCounter <= readCounter;
            end
        end else if (readHandshake) begin
            // Else on normal handshake update the current transaction index
            transReadCounter <= next_transReadCounter;
        end
    end
endgenerate

endmodule
