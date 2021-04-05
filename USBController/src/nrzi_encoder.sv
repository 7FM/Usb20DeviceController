module nrzi_encoder#(
    parameter INITIAL_VALUE = 1,
    parameter ZERO_AS_TRANSITION = 1
)(
    input logic CLK,
    input logic RST,
    input logic data,
    output logic OUT
);

    logic outBuf;

    assign OUT = outBuf;

    initial begin
        outBuf = INITIAL_VALUE[0];    
    end

    generate
        always_ff @(posedge CLK) begin
            if (RST) begin
                outBuf <= INITIAL_VALUE[0];
            end else begin
                if (ZERO_AS_TRANSITION) begin
                    outBuf <= outBuf ~^ data;
                end else begin
                    outBuf <= outBuf ^ data;
                end
            end
        end
    endgenerate

endmodule