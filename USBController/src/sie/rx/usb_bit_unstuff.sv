module usb_bit_unstuff#()(
    input logic clk12,
    input logic RST,
    input logic data,
    output logic valid,
    output logic error
);

    logic [2:0] oneCounter;

    assign valid = oneCounter < 6;
    assign error = oneCounter == 7;

    always_ff @(posedge clk12) begin
        if (RST || !data) begin
            oneCounter <= 0;
        end else begin
            oneCounter <= oneCounter + 1;
        end
    end

endmodule
