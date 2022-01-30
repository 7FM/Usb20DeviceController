module vector_buf#(
    parameter DATA_WID = 8,
    parameter BUF_SIZE,
    parameter INITIALIZE_BUF_IDX = 0,
    parameter USE_INVERTED_INDEXING_SCHEME = 0
)(
    input logic clk_i,
    input logic rst_i,

    input logic [DATA_WID-1:0] data_i,
    input logic dataValid_i,

    output logic [DATA_WID*BUF_SIZE - 1:0] buffer_o,
    output logic isFull_o
);

    localparam IDX_WID = $clog2(BUF_SIZE + 1);

    logic [IDX_WID-1:0] bufIdx, nextBufIdx;

    generate
        if (INITIALIZE_BUF_IDX) begin
            initial begin
                if (USE_INVERTED_INDEXING_SCHEME) begin
                    bufIdx = BUF_SIZE[IDX_WID-1:0];                
                end else begin
                    bufIdx = {IDX_WID{1'b0}};
                end
            end
        end

        if (USE_INVERTED_INDEXING_SCHEME) begin
            assign isFull_o = bufIdx == 0;
            assign nextBufIdx = isFull_o ? bufIdx : bufIdx - 1;
        end else begin
            assign isFull_o = bufIdx == BUF_SIZE[IDX_WID-1:0];
            assign nextBufIdx = isFull_o ? bufIdx : bufIdx + 1;
        end
    endgenerate

    logic handshake;
    assign handshake = !isFull_o && dataValid_i;

    generate
        genvar i;

        if (USE_INVERTED_INDEXING_SCHEME) begin
            logic [DATA_WID*BUF_SIZE - 1:0] buffer_reversed;
            for (i = 0; i < BUF_SIZE; i++) begin
                assign buffer_o[i * DATA_WID +: DATA_WID] = buffer_reversed[(BUF_SIZE - 1 - i) * DATA_WID - 1 -: DATA_WID];
            end

            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    bufIdx <= BUF_SIZE[IDX_WID-1:0];
                end else if (handshake) begin
                    bufIdx <= nextBufIdx;
                    buffer_reversed[nextBufIdx * DATA_WID - 1 -: DATA_WID] <= data_i;
                end
            end
        end else begin
            always_ff @(posedge clk_i) begin
                if (rst_i) begin
                    bufIdx <= {IDX_WID{1'b0}};
                end else if (handshake) begin
                    bufIdx <= nextBufIdx;
                    buffer_o[bufIdx * DATA_WID +: DATA_WID] <= data_i;
                end
            end
        end
    endgenerate

endmodule
