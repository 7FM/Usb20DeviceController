// Module for handling CRCs of USB packets.
// It can either be used to calculate the CRC for a packet to be send or to check whether a packet was correctly received (aka CRC is correct)
module usb_crc(
    input logic clk12,
    input logic RST, // Required at every new packet, can be a wire
    input logic VALID, // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
    input logic rxUseCRC16, // Indicate which CRC should type should be calculated/checked, needs to be set when RST is set high
    input logic data,
    output logic validCRC,
    output logic [15:0] crc
);

    logic [15:0] crcBuf;
    logic useCRC16, crc5_in, crc16_in, crcX_in, crc5_valid, crc16_valid;

    assign crc5_in = crcBuf[4] ^ data;
    assign crc16_in = crcBuf[15] ^ data;
    assign crcX_in = useCRC16 ? crc16_in : crc5_in;

    //TODO wtf this is send in MSb and not LSb as all other fields!
    // When the last bit of the checked field is sent, the CRC in the generator is inverted and sent to the checker MSb first
    assign crc = ~crcBuf;

    // When the last bit of the CRC is received by the checker and no errors have occurred, the remainder will be equal to the polynomial residual.
    localparam crc16_residual = 16'b1000_0000_0000_1101;
    localparam crc5_residual = 5'b0_1100;
    assign crc16_valid = crcBuf[15:0] == crc16_residual;
    assign crc5_valid = crcBuf[4:0] == crc5_residual;
    assign validCRC = useCRC16 ? crc16_valid : crc5_valid;

    always_ff @(posedge clk12) begin
        // CRC calculation magic:

        // For CRC generation and checking, the shift registers in the generator and checker are seeded with an allones pattern. For each data bit sent or received, the high order bit of the current remainder is XORed with
        // the data bit and then the remainder is shifted left one bit and the low-order bit set to zero. If the result of
        // that XOR is one, then the remainder is XORed with the generator polynomial.
        if (RST) begin
            crcBuf <= {16{1'b1}};
            useCRC16 <= rxUseCRC16;
        end else if (VALID) begin
            // Shift and XOR with polynomial if crcX_in is 1 -> XOR with crcX_in
            // CRC5  polynomial: 0b0000_0000_0000_0101
            // CRC16 polynomial: 0b1000_0000_0000_0101
            // -> lower bits are identical
            // -> as we ignore the upper most bits for CRC5 we can always xor at the locations of CRC16 polynomial with an 1
            crcBuf[15:0] <= {
                crcBuf[14] ^ crcX_in,
                crcBuf[13:2],
                crcBuf[1] ^ crcX_in,
                crcBuf[0],
                crcX_in
            };
        end
    end

endmodule
