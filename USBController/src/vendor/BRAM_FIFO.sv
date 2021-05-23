module BRAM_FIFO #(
    parameter EP_ADDR_WID = 9,
    parameter EP_DATA_WID = 8
)(
    input logic CLK,

    input logic dataValid,
    output logic full,
    input logic [EP_DATA_WID-1:0] dataIn,

    input logic popData,
    output logic dataAvailable,
    output logic [EP_DATA_WID-1:0] dataOut
);

    logic [EP_ADDR_WID-1:0] dataCounter, readCounter, next_dataCounter;

    assign dataAvailable = readCounter != dataCounter;
    assign next_dataCounter = dataCounter + 1;
    assign full = next_dataCounter == readCounter;

    logic writeHandshake, readHandshake;
    assign writeHandshake = !full && dataValid;
    assign readHandshake = dataAvailable && popData;

    bram4k bram(
        .CLK(clk48),
        .WEN(writeHandshake),
        .waddr(dataCounter),
        .wdata(dataIn),

        .raddr(readCounter),
        .rdata(dataOut),
    );

    initial begin
        dataCounter = 0;
        readCounter = 0;
    end

    always_ff @(posedge CLK) begin
        if (readHandshake) begin
            readCounter <= readCounter + 1;
        end
        if (writeHandshake) begin
            dataCounter <= next_dataCounter;
        end
    end

endmodule
