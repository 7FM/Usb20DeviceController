module output_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 1,
    parameter LSB_FIRST = 1
)(
    input logic clk12_i,
    input logic en_i,
    input logic dataValid_i,
    input logic crc5Patch_i,
    input logic [LENGTH-1:0] data_i,
    output logic dataBit_o,
    output logic bufferEmpty_o,
    output logic crc5PatchNow_o
);

    localparam CNT_WID = $clog2(LENGTH) - 1;
    logic [CNT_WID:0] bitsLeft;

    logic [LENGTH-1:0] dataBuf;

    initial begin
        dataBuf = {LENGTH{INIT_BIT_VALUE[0]}};
        bitsLeft = 0;
    end

    assign bufferEmpty_o = bitsLeft == 0;
    // Signal when crc5 patching should happen, this has to consider bitstuffing (en_i)
    assign crc5PatchNow_o = bitsLeft == 5 && en_i;

    generate
        if (LSB_FIRST) begin
            assign dataBit_o = dataBuf[0];
        end else begin
            assign dataBit_o = dataBuf[LENGTH-1];
        end

        always_ff @(posedge clk12_i) begin
            if (dataValid_i) begin
                dataBuf <= data_i;
                //TODO construct edge case where crc5Patch_i & !en_i is true!
                bitsLeft <= (crc5Patch_i ? bitsLeft - {{CNT_WID-1{1'b0}}, en_i} : (LENGTH[CNT_WID:0] - 1));
            end else begin
                bitsLeft <= bitsLeft - {{CNT_WID-1{1'b0}}, (!bufferEmpty_o && en_i)};

                if (en_i) begin
                    if (LSB_FIRST) begin
                        dataBuf <= {INIT_BIT_VALUE[0], dataBuf[LENGTH-1:1]};
                    end else begin
                        dataBuf <= {dataBuf[LENGTH-2:0], INIT_BIT_VALUE[0]};
                    end
                end else begin
                    dataBuf <= dataBuf;
                end
            end
        end
    endgenerate

endmodule
