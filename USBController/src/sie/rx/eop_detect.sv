// Detect end of packet
module eop_detect(
    input logic clk48,
    input logic RST,
    input logic dataInP,
    input logic dataInN,
    output logic eop // Requires explicit RST to clear flag again
);

    logic se0, j;
    assign se0 = !(dataInP || dataInN);
    assign j = dataInP && !dataInN;

    typedef enum {
        IDLE = 0,
        FIRST_SE0,
        SECOND_SE0,
        THIRD_SE0,
        LAST_CHANCE
    } EOP_FSMState;

    EOP_FSMState state, nextState;
    logic nextEOP;

    always_comb begin
        nextState = state + 1;
        nextEOP = eop;

        unique case (state)
            IDLE: begin
                unique if (!se0) begin
                    nextState = state;
                end else begin
                    // Default: go to next state
                end
            end
            FIRST_SE0, SECOND_SE0: begin
                unique if (!se0) begin
                    nextState = IDLE;
                end else begin
                    // Default: go to next state
                end
            end
            THIRD_SE0: begin
                nextEOP = j;
                unique if (se0) begin
                    nextState = state;
                end else if (j) begin
                    nextState = IDLE;
                end else begin
                    // Default: go to next state
                end
            end
            LAST_CHANCE: begin
                nextState = IDLE;
                nextEOP = j;
            end
        endcase        
    end

    initial begin
        state = IDLE;
        eop = 1'b0;
    end

    always_ff @(posedge clk48) begin
        if (RST) begin
            state <= IDLE;
            eop <= 1'b0;
        end else begin
            state <= nextState;
            eop <= nextEOP;
        end
    end

endmodule