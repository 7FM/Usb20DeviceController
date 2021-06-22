module input_shift_reg#(
    parameter LENGTH = 8,
    parameter INIT_BIT_VALUE = 1,
    parameter LSb_FIRST = 1
)(
    input logic clk12_i,
    input logic en_i,
    input logic rst_i,
    input logic dataBit_i,
    output logic [LENGTH-1:0] data_o,
    output logic bufferFull_o
);

    localparam CNT_WID = $clog2(LENGTH + 1) - 1;
    logic [CNT_WID:0] validEntryCounter;

    initial begin
        data_o = {LENGTH{INIT_BIT_VALUE[0]}};
        validEntryCounter = 0;
    end

    assign bufferFull_o = validEntryCounter == LENGTH;

    generate
        always_ff @(posedge clk12_i) begin

            //TODO we probaly need to reset the stored data too if rst_i is set -> else we might have false positive sync detections!
            if (rst_i || bufferFull_o) begin
                validEntryCounter <= {{CNT_WID{1'b0}}, en_i};
            end else begin
                validEntryCounter <= validEntryCounter + {{CNT_WID{1'b0}}, en_i};
            end

            if (en_i) begin
                if (LSb_FIRST) begin
                    data_o <= {dataBit_i, data_o[LENGTH-1:1]};
                end else begin
                    data_o <= {data_o[LENGTH-2:0], dataBit_i};
                end
            end else begin
                data_o <= data_o;
            end
        end
    endgenerate

endmodule
