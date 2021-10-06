`include "util_macros.sv"

module FIFO #(
    parameter ADDR_WID = 9,
    parameter DATA_WID = 8,
    parameter ENTRIES = 0,
    parameter bit REDUCE_COMB_PATH = 1
)(
    input logic clk_i,

    // Backend Memory interface: typical dual port interface
    output logic wEn_o,
    output logic [ADDR_WID-1:0] wAddr_o,
    output logic [DATA_WID-1:0] wData_o,
    output logic [ADDR_WID-1:0] rAddr_o,
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
    output logic [DATA_WID-1:0] data_o
);

//TODO we might wanna use the trick from ASYNC_FIFO here too to avoid being able to only store ENTRIES-1 element at a time!

    logic [ADDR_WID-1:0] dataCounter, readCounter;
    logic [ADDR_WID-1:0] transDataCounter, transReadCounter, next_transDataCounter, next_transReadCounter;

    // the data available flag compares registers -> okish combinatorial path
    assign dataAvailable_o = transReadCounter != dataCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full_o && dataValid_i;
    assign readHandshake = dataAvailable_o && popData_i;

    // Attach signals to memory interface
    assign wEn_o = writeHandshake;
    assign wAddr_o = transDataCounter;
    assign wData_o = data_i;
    assign rAddr_o = transReadCounter;
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
        assign next_transDataCounter = transDataCounter == MAX_IDX[ADDR_WID-1:0] ? {ADDR_WID{1'b0}} : transDataCounter + 1;
        assign next_transReadCounter = transReadCounter == MAX_IDX[ADDR_WID-1:0] ? {ADDR_WID{1'b0}} : transReadCounter + 1;
    end

    // Reduce the combinatorial path by adding an additional counter that stores how many elements are left
    `MUTE_LINT(UNUSED)
    logic [ADDR_WID-1:0] prevReadCounter;
    `UNMUTE_LINT(UNUSED)
    if (REDUCE_COMB_PATH) begin
        // We can shorten the critical path by storing the prevReadCounter to compare the current transDataCounter with
        assign full_o = transDataCounter == prevReadCounter;
    end else begin
        // this flag has a rather long critial path as it has to perform an addition before comparing!
        assign full_o = next_transDataCounter == readCounter;
    end

    initial begin
        dataCounter = 0;
        transDataCounter = 0;
        readCounter = 0;
        transReadCounter = 0;
        if (REDUCE_COMB_PATH) begin
            prevReadCounter = MAX_IDX[ADDR_WID-1:0];
        end
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
                if (REDUCE_COMB_PATH) begin
                    if (ENTRIES <= 0 || ENTRIES == 2**ADDR_WID) begin
                        prevReadCounter <= transReadCounter - 1;
                    end else begin
                        prevReadCounter <= transReadCounter == 0 ? MAX_IDX : transReadCounter - 1;
                    end
                end
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
