// Credits go to:
// http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf and https://zipcpu.com/blog/2017/07/29/fifo.html

module ASYNC_FIFO #(
    parameter ADDR_WID = 2, // Minimal required address width
    parameter DATA_WID = 8
)(
    input logic w_clk_i,
    input logic dataValid_i,
    input logic [DATA_WID-1:0] data_i,
    output logic full_o,

    input logic r_clk_i,
    input logic popData_i,
    output logic empty_o,
    output logic [DATA_WID-1:0] data_o
);

    //TODO initialization & reset logic!

    logic [DATA_WID-1:0] mem [0:(2**ADDR_WID)-1]

    // Use one bit more than required, to be able to use the entire mem buffer (2^ADDR_WID many elemets)
    // Else the full state is represented when wAddr + 1 == rAddr -> mem[wAddr] is unused!
    // With the additional bit it will be encoded if an index already wrapped around
    // -> all slots can be used and the full state is represented by the condition:
    // rAddr[ADDR_WID] != wAddr[ADDR_WID] && rAddr[ADDR_WID-1:0] == wAddr[ADDR_WID-1:0]
    // Meaning that the write pointer already wrapped around & wrote the indizes after rAddr
    // and that both address point to the same memory address -> all slots before rAddr are filled too -> FIFO is full!
    logic [ADDR_WID:0] rAddr, wAddr;
    // The advantage of gray codes is that they only change a single bit at a time
    // -> double flopping will always results in an correct value (either a new updated one or the previous old value)
    // This enables effiction CDC of the multibit value with double flopping too!
    logic [ADDR_WID:0] rAddrGrayCode, wAddrGrayCode;

    gray_code_encoder #(
        .WID(ADDR_WID)
    ) readAddressGrayCodeEncoder(
        .in(rAddr),
        .out(rAddrGrayCode)
    );
    gray_code_encoder #(
        .WID(ADDR_WID)
    ) writeAddressGrayCodeEncoder(
        .in(wAddr),
        .out(wAddrGrayCode)
    );

    // gray code encoded address synced to the other clock domain
    logic [ADDR_WID:0] rAddrGrayCode_synced, wAddrGrayCode_synced;

    cdc_sync #(
        .WID(ADDR_WID)
    ) readAddressGrayCodeSyncer (
        .clk(w_clk_i),
        .in(rAddrGrayCode),
        .out(rAddrGrayCode_synced)
    );
    cdc_sync #(
        .WID(ADDR_WID)
    ) writeAddressGrayCodeSyncer (
        .clk(r_clk_i),
        .in(wAddrGrayCode),
        .out(wAddrGrayCode_synced)
    );

    //=======================================================================
    //==========================Write clock domain===========================
    //=======================================================================

    // Checking whether the queue is full with gray codes is not trivial, yet easier than expected.
    // Due to some magic properties (see linked references), no extra back conversion to an normal binary encoding is required.
    // Normal condition: rAddr[ADDR_WID] != wAddr[ADDR_WID] && rAddr[ADDR_WID-1:0] == wAddr[ADDR_WID-1:0]
    // Gray code condition:
    assign full_o = wAddrGrayCode[ADDR_WID:ADDR_WID-1] == ~rAddrGrayCode_synced[ADDR_WID:ADDR_WID-1]
                    // Note that this -----------------^^^^^ can NOT be replaced with an != or == !rAddrGrayCode_synced
                    && wAddrGrayCode[ADDR_WID-2:0] == rAddrGrayCode_synced[ADDR_WID-2:0];

    logic writeHandshake;
    assign writeHandshake = dataValid_i && !full_o;

    always_ff @(posedge w_clk_i) begin
        wAddr <= wAddr + writeHandshake;

        if (writeHandshake) begin
            mem[wAddr[ADDR_WID-1:0]] <= data_i;
        end
    end

    //=======================================================================
    //===========================Read clock domain===========================
    //=======================================================================

    assign data_o = mem[rAddr[ADDR_WID-1:0]];
    // The empty condition does still work with an simple comparison as each gray code is unique
    // -> equality still means that the address pointers point to the same element -> the fifo is empty
    assign empty_o = rAddrGrayCode == wAddrGrayCode_synced;

    logic readHandshake;
    assign readHandshake = popData_i && !empty_o;

    always_ff @(posedge r_clk_i) begin
        rAddr <= rAddr + readHandshake;
    end

endmodule
