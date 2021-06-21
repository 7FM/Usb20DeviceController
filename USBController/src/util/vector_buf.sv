module vector_buf#(
    parameter DATA_WID = 8,
    parameter BUF_SIZE,
    parameter INITIALIZE_BUF_IDX = 0
)(
    input logic clk,
    input logic rst,

    input logic [DATA_WID-1:0] dataIn,
    input logic dataValid,

    output logic [DATA_WID*BUF_SIZE - 1:0] buffer,
    output logic isFull
);

    localparam IDX_WID = $clog2(BUF_SIZE + 1) + 1;

    logic [IDX_WID-1:0] bufIdx, nextBufIdx;

    generate
        if (INITIALIZE_BUF_IDX) begin
            initial begin
                bufIdx = {IDX_WID{1'b0}};
            end
        end
    endgenerate

    assign isFull = bufIdx == BUF_SIZE;
    assign nextBufIdx = isFull ? bufIdx : bufIdx + 1;

    logic handshake;
    assign handshake = !isFull && dataValid;

    always_ff @(posedge clk) begin
        if (rst) begin
            bufIdx <= {IDX_WID{1'b0}};
        end else if (handshake) begin
            bufIdx <= nextBufIdx;
            buffer[bufIdx * DATA_WID +: DATA_WID] <= dataIn;
        end
    end

endmodule
