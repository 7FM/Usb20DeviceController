module output_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 0,
    parameter LSB_FIRST = 1
)(
    input logic CLK,
    input logic EN,
    input logic NEW_IN,
    input logic [LENGTH-1:0] dataIn,
    input logic OUT,
);

    //TODO implement bit stuffing!

    logic [LENGTH-1:0] dataBuf;

    initial begin
        dataBuf = {LENGTH{INIT_BIT_VALUE[0]}};
    end

    generate
        if (LSB_FIRST) begin
            assign OUT = dataBuf[0];
        end else begin
            assign OUT = dataBuf[LENGTH-1];
        end

        always_ff @(posedge CLK) begin
            if (EN) begin
                if (NEW_IN) begin
                    dataBuf <= dataIn;
                end else begin
                    if (LSB_FIRST) begin
                        dataBuf <= {INIT_BIT_VALUE[0], dataBuf[LENGTH-1:1]};
                    end else begin
                        dataBuf <= {dataBuf[LENGTH-2:0], INIT_BIT_VALUE[0]};
                    end
                end
            end else begin
                dataBuf <= dataBuf;
            end
        end
    endgenerate

endmodule