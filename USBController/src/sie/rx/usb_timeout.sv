module usb_timeout(
    input logic clk48,
    input logic clk12, // Note that this clock has to run all the time, no matter the internal state of the DPPL
    input logic RST,
    input logic rxGotSignal,
    output logic rxTimeout
);

    /* TIMEOUT REQUIREMENTS:
    The device expecting the response will not time out
    before 16 bit times but will timeout before 18 bit times (measured at the data pins of the device from the SE0-toJ transition at the end of the EOP).
    The host will wait at least 18 bit times for a response to start before it will start a new transaction

    A high-speed host or device expecting a response to a transmission must not timeout the transaction if the interpacket delay is less than 736 bit times,
    and it must timeout the transaction if no signaling is seen within 816 bit times.
    */
    localparam TIMEOUT_TICKS = 16;
    localparam TIMEOUT_CNT_WID = $clog2(TIMEOUT_TICKS) + 1;

    logic [TIMEOUT_CNT_WID-1:0] timeoutCnt, timeoutCntAdd1;

    assign timeoutCntAdd1 = timeoutCnt + 1;

generate
    if (TIMEOUT_TICKS == 2**TIMEOUT_CNT_WID) begin
        assign rxTimeout = &timeoutCnt;
    end else begin
        assign rxTimeout = timeoutCnt == TIMEOUT_TICKS - 1;
    end
endgenerate

    logic gotSignalSync;

    initial begin
        gotSignalSync = 1'b0;
        timeoutCnt = {TIMEOUT_CNT_WID{1'b0}};
    end

    always_ff @(posedge clk48) begin
        //gotSignalSync <= RST ? 1'b0 : |timeoutCnt && (gotSignalSync || rxGotSignal);
        // Might be very bad if we miss this signal!
        gotSignalSync <= RST ? 1'b0 : (gotSignalSync || rxGotSignal);
    end

    always_ff @(posedge clk12) begin
        if (RST || gotSignalSync) begin
            timeoutCnt <= {TIMEOUT_CNT_WID{1'b0}};
        end else begin
            timeoutCnt <= rxTimeout ? timeoutCnt : timeoutCntAdd1;
        end
    end

endmodule
