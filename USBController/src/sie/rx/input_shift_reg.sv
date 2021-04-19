module input_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 0,
    parameter LSb_FIRST = 1
)(
    input logic clk12,
    input logic EN,
    input logic IN,
    output logic [LENGTH-1:0] dataOut
);

    initial begin
        dataOut = {LENGTH{INIT_BIT_VALUE[0]}};
    end

    generate
        always_ff @(posedge clk12) begin
            if (EN) begin
                if (LSb_FIRST) begin
                    dataOut <= {IN, dataOut[LENGTH-1:1]};
                end else begin
                    dataOut <= {dataOut[LENGTH-2:0], IN};
                end
            end else begin
                dataOut <= dataOut;
            end
        end
    endgenerate

endmodule