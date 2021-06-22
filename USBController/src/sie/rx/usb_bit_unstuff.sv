module usb_bit_unstuff#()(
    input logic clk12_i,
    input logic rst_i,
    input logic data_i,
    output logic valid_o,
    output logic error_o
);

    logic [2:0] oneCounter;

    assign valid_o = oneCounter < 6;
    // We expect an stuffed 0 bit but got another 1 bit!
    assign error_o = !valid_o && data_i;

    always_ff @(posedge clk12_i) begin
        if (rst_i || !data_i) begin
            oneCounter <= 0;
        end else begin
            oneCounter <= oneCounter + 1;
        end
    end

endmodule
