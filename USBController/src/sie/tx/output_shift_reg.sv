module output_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 1,
    parameter LSB_FIRST = 1
)(
    input logic clk12_i,
    input logic en_i,
    input logic dataValid_i,
    input logic [LENGTH-1:0] data_i,
    output logic dataBit_o,
    output logic bufferEmpty_o
);

    localparam CNT_WID = $clog2(LENGTH+1) - 1;
    logic [CNT_WID:0] bitsLeft;

    logic [LENGTH-1:0] dataBuf;

    initial begin
        dataBuf = {LENGTH{INIT_BIT_VALUE[0]}};
        bitsLeft = 0;
    end

    assign bufferEmpty_o = bitsLeft == 0;

    generate
        if (LSB_FIRST) begin
            assign dataBit_o = dataBuf[0];
        end else begin
            assign dataBit_o = dataBuf[LENGTH-1];
        end

        always_ff @(posedge clk12_i) begin
            if (dataValid_i) begin
                dataBuf <= data_i;
                bitsLeft <= en_i ? LENGTH-1 : LENGTH;
            end else if (en_i) begin
                bitsLeft <= bufferEmpty_o ? bitsLeft : bitsLeft - 1;
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
