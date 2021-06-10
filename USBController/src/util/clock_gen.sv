`include "util_macros.sv"

module clock_gen #(
    parameter DIVIDE_LOG_2=0
) (
    input logic inCLK,
    output logic outCLK
);

    generate
        if (DIVIDE_LOG_2 == 0) begin
            assign outCLK = inCLK;
        end else begin
            logic div2CLK;

            simpleDFlipFlopCLK clockDiv2 (.CLK(inCLK), .outCLK(div2CLK));

            // Recursive instantiation!
            clock_gen #(.DIVIDE_LOG_2(DIVIDE_LOG_2 - 1)) rev_clk_gen (.inCLK(div2CLK), .outCLK(outCLK));
        end
    endgenerate

endmodule

`MUTE_LINT(DECLFILENAME)
module simpleDFlipFlopCLK(
    input logic CLK,
    output logic outCLK
);

    initial begin
        outCLK = 1'b0;
    end

    always_ff @(posedge CLK) begin
        outCLK <= ~outCLK;        
    end

endmodule
`UNMUTE_LINT(DECLFILENAME)
