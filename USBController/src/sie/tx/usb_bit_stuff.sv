module usb_bit_stuff#()(
    input logic clk12,
    input logic RST,
    input logic data,
    output logic ready,
    output logic outData
);

    logic [2:0] oneCounter;

    assign ready = oneCounter < 6;

    assign outData = ready ? data : 1'b0;

    always_ff @(posedge clk12) begin
        if (RST || !ready || !data) begin
            oneCounter <= 0;
        end else begin
            oneCounter <= oneCounter + 1;
        end
    end

endmodule
