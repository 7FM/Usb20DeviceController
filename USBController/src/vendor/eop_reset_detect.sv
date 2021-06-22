// Detect end of packet and reset signals
module eop_reset_detect(
    input logic clk48_i,
    input logic ackEOP_i,
    input logic dataInP_i,
    input logic dataInN_i,
    input logic ackUsbRst_i,
    output logic eopDetect_o, // Requires explicit RST to clear flag again
    output logic usbRst_o // Requires explicit ACK to clear flag again
);

    logic se0, j;
    assign se0 = !(dataInP_i || dataInN_i);
    assign j = dataInP_i && !dataInN_i;

    typedef enum logic[2:0] {
        IDLE = 0,
        FIRST_SE0,
        SECOND_SE0,
        THIRD_SE0,
        LAST_CHANCE
    } EOP_FSMState;

    EOP_FSMState state, nextState;
    logic nextEopDetect, nextUsbReset;

    // To count as reset signal, SE0 must be received for at least 2.5 µs
    // Hence, for at least 48 MHz * 2.5 µs = 120 cycles
    localparam RESET_REQUIRED_SE0_CYCLES = 120;
    localparam SE0_COUNTER_WID = $clog2(RESET_REQUIRED_SE0_CYCLES+1);
    logic [SE0_COUNTER_WID-1:0] se0_counter, next_se0_counter;

    assign next_se0_counter = se0 ? se0_counter + 1 : {SE0_COUNTER_WID{1'b0}};
    assign nextUsbReset = usbRst_o || se0_counter >= RESET_REQUIRED_SE0_CYCLES;

    always_comb begin
        nextState = state + 1;
        nextEopDetect = eopDetect_o;

        unique case (state)
            IDLE: begin
                /*unique*/ if (!se0) begin
                    nextState = state;
                end else begin
                    // Default: go to next state
                end
            end
            FIRST_SE0, SECOND_SE0: begin
                /*unique*/ if (!se0) begin
                    nextState = IDLE;
                end else begin
                    // Default: go to next state
                end
            end
            THIRD_SE0: begin
                nextEopDetect = j;
                /*unique*/ if (se0) begin
                    nextState = state;
                end else if (j) begin
                    nextState = IDLE;
                end else begin
                    // Default: go to next state
                end
            end
            LAST_CHANCE: begin
                nextState = IDLE;
                nextEopDetect = j;
            end
        endcase        
    end

    initial begin
        state = IDLE;
        eopDetect_o = 1'b0;
        usbRst_o = 1'b0;
        se0_counter = {SE0_COUNTER_WID{1'b0}};
    end

    always_ff @(posedge clk48_i) begin

        if (ackUsbRst_i) begin
            usbRst_o <= 1'b0;
            se0_counter <= {SE0_COUNTER_WID{1'b0}};
        end else begin
            se0_counter <= next_se0_counter;
            usbRst_o <= nextUsbReset;
        end

        if (ackEOP_i) begin
            state <= IDLE;
            eopDetect_o <= 1'b0;
        end else begin
            state <= nextState;
            eopDetect_o <= nextEopDetect;
        end
    end

endmodule
