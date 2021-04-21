module input_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 0,
    parameter LSb_FIRST = 1
)(
    input logic clk12,
    input logic EN,
    input logic RST,
    input logic IN,
    output logic [LENGTH-1:0] dataOut,
    output logic bufferFull
);

    localparam CNT_WID = $clog2(LENGTH + 1) - 1;
    logic [CNT_WID:0] validEntryCounter;

    initial begin
        dataOut = {LENGTH{INIT_BIT_VALUE[0]}};
        validEntryCounter = 0;
    end

    assign bufferFull = validEntryCounter == LENGTH;

    generate
        always_ff @(posedge clk12) begin

            //TODO we probaly need to reset the stored data too if RST is set -> else we might have false positive sync detections!
            if (RST || bufferFull) begin
                validEntryCounter <= {{CNT_WID{1'b0}}, EN};
            end else begin
                validEntryCounter <= validEntryCounter + {{CNT_WID{1'b0}}, EN};
            end

            if (EN) begin
                if (LSb_FIRST) begin
                    dataOut <= {IN, dataOut[LENGTH-1:1]};
                end else begin
                    dataOut <= {dataOut[LENGTH-2:0], IN};
                end
            end else begin
                dataOut <= dataOut;
            end
        end
    endgenerate

endmodule