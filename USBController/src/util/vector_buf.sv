module vector_buf#(
    parameter DATA_WID = 8,
    parameter BUF_SIZE,
    parameter INITIALIZE_BUF_IDX = 0
)(
    input logic clk_i,
    input logic rst_i,

    input logic [DATA_WID-1:0] data_i,
    input logic dataValid_i,

    output logic [DATA_WID*BUF_SIZE - 1:0] buffer_o,
    output logic isFull_o
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

    assign isFull_o = bufIdx == BUF_SIZE;
    assign nextBufIdx = isFull_o ? bufIdx : bufIdx + 1;

    logic handshake;
    assign handshake = !isFull_o && dataValid_i;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            bufIdx <= {IDX_WID{1'b0}};
        end else if (handshake) begin
            bufIdx <= nextBufIdx;
            buffer_o[bufIdx * DATA_WID +: DATA_WID] <= data_i;
        end
    end

endmodule
