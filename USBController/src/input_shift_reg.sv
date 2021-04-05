module input_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 0,
    parameter LSB_FIRST = 1
)(
    input logic CLK,
    input logic EN,
    input logic IN,
    output logic [LENGTH-1:0] dataOut
);

    //TODO implement bit stuffing!

    initial begin
        dataOut = {LENGTH{INIT_BIT_VALUE[0]}};
    end

    generate
        always_ff @(posedge CLK) begin
            if (EN) begin
                if (LSB_FIRST) begin
                    dataOut <= {IN, dataOut[LENGTH-2:0]};
                end else begin
                    dataOut <= {dataOut[LENGTH-2:0], IN};
                end
            end else begin
                dataOut <= dataOut;
            end
        end
    endgenerate

endmodule