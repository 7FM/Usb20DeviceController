module output_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 0,
    parameter LSB_FIRST = 1
)(
    input logic clk12,
    input logic EN,
    input logic NEW_IN,
    input logic [LENGTH-1:0] dataIn,
    output logic OUT,
    output logic bufferEmpty
);

    localparam CNT_WID = $clog2(LENGTH+1) - 1;
    logic [CNT_WID:0] bitsLeft;

    logic [LENGTH-1:0] dataBuf;

    initial begin
        dataBuf = {LENGTH{INIT_BIT_VALUE[0]}};
        bitsLeft = 0;
    end

    assign bufferEmpty = bitsLeft == 0;

    generate
        if (LSB_FIRST) begin
            assign OUT = dataBuf[0];
        end else begin
            assign OUT = dataBuf[LENGTH-1];
        end

        always_ff @(posedge clk12) begin
            if (NEW_IN) begin
                dataBuf <= dataIn;
                bitsLeft <= EN? LENGTH-1 : LENGTH;
            end else if (EN) begin
                bitsLeft <= bufferEmpty ? bitsLeft : bitsLeft - 1;
                if (LSB_FIRST) begin
                    dataBuf <= {INIT_BIT_VALUE[0], dataBuf[LENGTH-1:1]};
                end else begin
                    dataBuf <= {dataBuf[LENGTH-2:0], INIT_BIT_VALUE[0]};
                end
            end else begin
                dataBuf <= dataBuf;
                bitsLeft <= bitsLeft;
            end
        end
    endgenerate

endmodule
