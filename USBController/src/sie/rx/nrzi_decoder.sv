module nrzi_decoder#(
    parameter INITIAL_VALUE = 1,
    parameter ZERO_AS_TRANSITION = 1
)(
    input logic clk12,
    input logic RST,
    input logic data,
    output logic OUT
);

    /*
    Differential Signal:
                                 __   _     _   _     ____
                            D+ :   \_/ \___/ \_/ \___/
                                    _   ___   _           
                            D- : __/ \_/   \_/ \__________
    Differential decoding:          K J K K J K J 0 0 J J
                                                  ^------------ SM0/SE0 with D+=D-=LOW analogously exists SM1/SE1 with D+=D-=HIGH
    NRZI decoding:                  0 0 0 1 0 0 0 ? ? 0 1
    (Non-Return-to-Zero Inverted): logical 0 is transmitted as transition -> either from J to K or from K to J
                                   logical 1 is transmitted as NO transition -> stay at previous level
    */

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
