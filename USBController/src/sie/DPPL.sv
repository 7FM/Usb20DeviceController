module DPPL(
    input logic clk48,
    input logic RST,
    //TODO how are a and b defined?
    // a’ and ‘b’ are the differential receiver output synchronized by a stage of the 48Mhz 
    // (also a’ is synchronized on the rising edge and ‘b’ is synchronized on the falling edge.
    input logic a,
    input logic b,
    output logic readCLK12,
    // TODO is this always true or better read input? also which data would this be? J/K or already decoded NRZI???
    output logic data
);

    typedef enum {
        // Init states
        STATE_C = 4'b1100,
        STATE_D = 4'b1101,
        // Transition states
        STATE_B = 4'b1011,
        STATE_F = 4'b1111,
        // Right loop
        STATE_5 = 4'b0101,
        STATE_7 = 4'b0111,
        STATE_6 = 4'b0110,
        STATE_4 = 4'b0100,
        // Left loop
        STATE_1 = 4'b0001,
        STATE_3 = 4'b0011,
        STATE_2 = 4'b0010,
        STATE_0 = 4'b0000
        // Note: states 1, 5, B, F are replaced by freezeFSM state
    } DPPL_FSM;

    logic [3:0] fsmState, nextFsmState, fsmStateNextGrayCode;

    assign readCLK12 = fsmState[1];
    assign data = fsmState[2];

    initial begin
        fsmState = STATE_C;
    end

    always_ff @(posedge clk48) begin
        if (RST) begin
            fsmState <= STATE_C;
        end else begin
            fsmState <= nextFsmState;
        end
    end

    assign fsmStateNextGrayCode = {fsmState[3:2], fsmState[0], fsmState[1] ^ 1'b1};

    always_comb begin
        nextFsmState = fsmStateNextGrayCode;

        unique casez (fsmState)
            // Init states
            STATE_C: begin 
                if (fsmState[0] ^ b) begin
                    nextFsmState = fsmState;
                end
            end
            STATE_D: begin 
                if (fsmState[0] ^ b) begin
                    nextFsmState = fsmState;
                else begin
                    nextFsmState = {1'b0, fsmState[2:0]};
                end
            end
            // Swap side transitions
            STATE_F, STATE_B: begin 
                // Keep changes of the grayCode but clear the MSB bit
                nextFsmState[3] = 1'b0;
            end

            STATE_7, STATE_3: begin
                if (a ^ fsmState[2]) begin
                    // if in state 7: Get to state B
                    // if in state 3: Get to state F
                    // both lower bits are 1 -> order does not matter but maybe the synthesis can use this to combine paths for STATE 7,3 & 6,2
                    nextFsmState = {~fsmState[3], ~fsmState[2], fsmState[0], fsmState[1]};
                end
            end
            STATE_6, STATE_2: begin
                if (b ^ fsmState[2]) begin
                    // if in state 6: Get to state 1
                    // if in state 2: Get to state 5
                    nextFsmState = {fsmState[3], ~fsmState[3], fsmState[0], fsmState[1]};
                end
            end
            STATE_4, STATE_0: begin
                if (b ^ fsmState[2]) begin
                    // if in state 4: Get to state 1
                    // if in state 0: Get to state 5
                    nextFsmState[2] = ~fsmState[2];
                end
            end

            default: begin
                // Empty default case to ensure that default values are applied for other cases
            end
        endcase
    end

endmodule