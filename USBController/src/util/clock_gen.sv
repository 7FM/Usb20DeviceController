`include "util_macros.sv"

module clock_gen #(
    parameter DIVIDE_LOG_2=0
) (
    input logic clk_i,
    output logic clk_o
);

    generate
        if (DIVIDE_LOG_2 == 0) begin
            assign clk_o = clk_i;
        end else begin
            logic div2CLK;

            simpleDFlipFlopCLK clockDiv2 (.clk_i(clk_i), .clk_o(div2CLK));

            // Recursive instantiation!
            clock_gen #(.DIVIDE_LOG_2(DIVIDE_LOG_2 - 1)) rev_clk_gen (.clk_i(div2CLK), .clk_o(clk_o));
        end
    endgenerate

endmodule

`MUTE_LINT(DECLFILENAME)
module simpleDFlipFlopCLK(
    input logic clk_i,
    output logic clk_o
);

    initial begin
        clk_o = 1'b0;
    end

    always_ff @(posedge clk_i) begin
        clk_o <= ~clk_o;
    end

endmodule
`UNMUTE_LINT(DECLFILENAME)
