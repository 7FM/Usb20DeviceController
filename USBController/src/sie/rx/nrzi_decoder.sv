module nrzi_decoder#(
    parameter INITIAL_VALUE = 1,
    parameter ZERO_AS_TRANSITION = 1
)(
    input logic clk12_i,
    input logic rst_i,
    input logic data_i,
    output logic data_o
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
        data_o = INITIAL_VALUE[0];
        prevData = INITIAL_VALUE[0];
    end

    generate
        always_ff @(posedge clk12_i) begin
            if (rst_i) begin
                data_o <= INITIAL_VALUE[0];
                prevData <= INITIAL_VALUE[0];
            end else begin
                prevData <= data_i;
                if (ZERO_AS_TRANSITION) begin
                    data_o <= prevData ~^ data_i;
                end else begin
                    data_o <= prevData ^ data_i;
                end
            end
        end
    endgenerate

endmodule
