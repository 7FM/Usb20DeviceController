module BRAM_FIFO #(
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic CLK,

    // Provide transactional read & write behaviour to allow reseting the values on failures without overwriting/loosing i.e. not yet send data or discarding corrupt packets
    // The signals to end an transactions: xTransDone & xTransSuccess may NOT be used concurrently with the read/write handshake signals!
    input logic fillTransDone,
    input logic fillTransSuccess,
    input logic dataValid,
    output logic full,
    input logic [EP_DATA_WID-1:0] dataIn,

    input logic popTransDone,
    input logic popTransSuccess,
    input logic popData,
    output logic dataAvailable,
    output logic [EP_DATA_WID-1:0] dataOut
);

    logic [EP_ADDR_WID-1:0] dataCounter, readCounter;
    logic [EP_ADDR_WID-1:0] transDataCounter, transReadCounter, next_transDataCounter;

    assign dataAvailable = transReadCounter != dataCounter;
    assign next_transDataCounter = transDataCounter + 1; // Abuses overflows to avoid wrap around logic
    assign full = next_transDataCounter == readCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full && dataValid;
    assign readHandshake = dataAvailable && popData;

    bram4k bram(
        .CLK(CLK),
        .WEN(writeHandshake),
        .waddr(transDataCounter),
        .wdata(dataIn),

        .raddr(transReadCounter),
        .rdata(dataOut)
    );

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
            transReadCounter <= transReadCounter + 1; // Abuses overflows to avoid wrap around logic
        end
    end

endmodule
