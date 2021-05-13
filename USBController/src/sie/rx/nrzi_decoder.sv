module nrzi_decoder#(
    parameter INITIAL_VALUE = 1,
    parameter ZERO_AS_TRANSITION = 1
)(
    input logic clk12,
    input logic RST,
    input logic data,
    output logic OUT
);

    logic prevData;

    initial begin
        OUT = INITIAL_VALUE[0];
        prevData = INITIAL_VALUE[0];
    end

    generate
        always_ff @(posedge clk12) begin
            if (RST) begin
                OUT <= INITIAL_VALUE[0];
                prevData <= INITIAL_VALUE[0];
            end else begin
                prevData <= data;
                if (ZERO_AS_TRANSITION) begin
                    OUT <= prevData ~^ data;
                end else begin
                    OUT <= prevData ^ data;
                end
            end
        end
    endgenerate

endmodule
