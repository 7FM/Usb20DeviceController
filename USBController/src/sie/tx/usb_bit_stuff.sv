module usb_bit_stuff#()(
    input logic clk12_i,
    input logic rst_i,
    input logic data_i,
    output logic ready_o,
    output logic data_o
);

    logic [2:0] oneCounter;

    assign ready_o = oneCounter < 6;

    assign data_o = ready_o ? data_i : 1'b0;

    always_ff @(posedge clk12_i) begin
        if (rst_i || !ready_o || !data_i) begin
            oneCounter <= 0;
        end else begin
            oneCounter <= oneCounter + 1;
        end
    end

endmodule
