module usb_timeout #(
    // Might require fine tuning due to internal delays of bus activity detections
    parameter TIMEOUT_TICKS = 16,
    /* TIMEOUT REQUIREMENTS:
    The device expecting the response will not time out
    before 16 bit times but will timeout before 18 bit times (measured at the data pins of the device from the SE0-toJ transition at the end of the EOP).
    The host will wait at least 18 bit times for a response to start before it will start a new transaction

    A high-speed host or device expecting a response to a transmission must not timeout the transaction if the interpacket delay is less than 736 bit times,
    and it must timeout the transaction if no signaling is seen within 816 bit times.
    */
    localparam TIMEOUT_CNT_WID = $clog2(TIMEOUT_TICKS);
)(
    input logic clk48_i,
    input logic clk12_i, // Note that this clock has to run all the time, no matter the internal state of the DPPL
    input logic rst_i,
    input logic rxGotSignal_i,
    output logic rxTimeout_o
);

    logic [TIMEOUT_CNT_WID-1:0] timeoutCnt, timeoutCntAdd1;

    assign timeoutCntAdd1 = timeoutCnt + 1;

generate
    if (TIMEOUT_TICKS == 2**TIMEOUT_CNT_WID) begin
        assign rxTimeout_o = &timeoutCnt;
    end else begin
        assign rxTimeout_o = timeoutCnt == TIMEOUT_TICKS - 1;
    end
endgenerate

    logic gotSignalSync;

    initial begin
        gotSignalSync = 1'b0;
        timeoutCnt = {TIMEOUT_CNT_WID{1'b0}};
    end

    always_ff @(posedge clk48_i) begin
        //gotSignalSync <= rst_i ? 1'b0 : |timeoutCnt && (gotSignalSync || rxGotSignal_i);
        // Might be very bad if we miss this signal!
        gotSignalSync <= rst_i ? 1'b0 : (gotSignalSync || rxGotSignal_i);
    end

    always_ff @(posedge clk12_i) begin
        if (rst_i || gotSignalSync) begin
            timeoutCnt <= {TIMEOUT_CNT_WID{1'b0}};
        end else begin
            timeoutCnt <= rxTimeout_o ? timeoutCnt : timeoutCntAdd1;
        end
    end

endmodule
