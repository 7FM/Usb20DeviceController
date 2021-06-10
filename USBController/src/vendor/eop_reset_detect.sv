// Detect end of packet and reset signals
module eop_reset_detect(
    input logic clk48,
    input logic ACK_EOP,
    input logic dataInP,
    input logic dataInN,
    input logic ACK_USB_RST,
    output logic eop, // Requires explicit RST to clear flag again
    output logic usb_reset // Requires explicit ACK to clear flag again
);

    logic se0, j;
    assign se0 = !(dataInP || dataInN);
    assign j = dataInP && !dataInN;

    typedef enum logic[2:0] {
        IDLE = 0,
        FIRST_SE0,
        SECOND_SE0,
        THIRD_SE0,
        LAST_CHANCE
    } EOP_FSMState;

    EOP_FSMState state, nextState;
    logic nextEOP, nextUsbReset;

    // To count as reset signal, SE0 must be received for at least 2.5 µs
    // Hence, for at least 48 MHz * 2.5 µs = 120 cycles
    localparam RESET_REQUIRED_SE0_CYCLES = 120;
    localparam SE0_COUNTER_WID = $clog2(RESET_REQUIRED_SE0_CYCLES+1);
    logic [SE0_COUNTER_WID-1:0] se0_counter, next_se0_counter;

    assign next_se0_counter = se0 ? se0_counter + 1 : {SE0_COUNTER_WID{1'b0}};
    assign nextUsbReset = usb_reset || se0_counter >= RESET_REQUIRED_SE0_CYCLES;

    always_comb begin
        nextState = state + 1;
        nextEOP = eop;

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
                nextEOP = j;
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
                nextEOP = j;
            end
        endcase        
    end

    initial begin
        state = IDLE;
        eop = 1'b0;
        usb_reset = 1'b0;
        se0_counter = {SE0_COUNTER_WID{1'b0}};
    end

    always_ff @(posedge clk48) begin

        if (ACK_USB_RST) begin
            usb_reset <= 1'b0;
            se0_counter <= {SE0_COUNTER_WID{1'b0}};
        end else begin
            se0_counter <= next_se0_counter;
            usb_reset <= nextUsbReset;
        end

        if (ACK_EOP) begin
            state <= IDLE;
            eop <= 1'b0;
        end else begin
            state <= nextState;
            eop <= nextEOP;
        end
    end

endmodule
