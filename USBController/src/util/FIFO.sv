module FIFO #(
    parameter ADDR_WID = 9,
    parameter DATA_WID = 8,
    parameter ENTRIES = -1
)(
    input logic CLK,

    // Backend Memory interface: typical dual port interface
    output logic WEN,
    output logic [ADDR_WID-1:0] waddr,
    output logic [DATA_WID-1:0] wdata,
    output logic [ADDR_WID-1:0] raddr,
    input logic [DATA_WID-1:0] rdata,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone,
    input logic fillTransSuccess,
    input logic dataValid,
    input logic [DATA_WID-1:0] dataIn,
    output logic full,

    input logic popTransDone,
    input logic popTransSuccess,
    input logic popData,
    output logic dataAvailable,
    output logic [DATA_WID-1:0] dataOut
);

    logic [ADDR_WID-1:0] dataCounter, readCounter;
    logic [ADDR_WID-1:0] transDataCounter, transReadCounter, next_transDataCounter, next_transReadCounter;

    assign dataAvailable = transReadCounter != dataCounter;

generate
    if (ENTRIES == -1 || ENTRIES == 2**ADDR_WID) begin
        // if entries == -1 is set then we assume that the entire address space is memory backed
        // Else if entries is set we can manually test this assumption and optimize if possible!
        assign next_transDataCounter = transDataCounter + 1; // Abuses overflows to avoid wrap around logic
        assign next_transReadCounter = transReadCounter + 1; // Abuses overflows to avoid wrap around logic
    end else begin
        // Otherwise not the entire address space is memory backed -> we need to make bounds checks to avoid invalid states & memory requests
        assign next_transDataCounter = transDataCounter == ENTRIES - 1 ? {ADDR_WID{1'b0}} : transDataCounter + 1;
        assign next_transReadCounter = transReadCounter == ENTRIES - 1 ? {ADDR_WID{1'b0}} : transReadCounter + 1;
    end
endgenerate

    assign full = next_transDataCounter == readCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full && dataValid;
    assign readHandshake = dataAvailable && popData;

    // Attach signals to memory interface
    assign WEN = writeHandshake;
    assign waddr = transDataCounter;
    assign wdata = dataIn;
    assign raddr = transReadCounter;
    assign dataOut = rdata;

    initial begin
        dataCounter = 0;
        transDataCounter = 0;
        readCounter = 0;
        transReadCounter = 0;
    end

    always_ff @(posedge CLK) begin
        // Write actions
        if (fillTransDone) begin
            // Write transaction is done
            if (fillTransSuccess) begin
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
        if (popTransDone) begin
            // Read transaction is done
            if (popTransSuccess) begin
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

endmodule
