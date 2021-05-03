`include "../../../config.sv"
`include "../sie_common_defs.sv"

module usb_rx#()(
    input logic clk48,
    input logic dataInN,
    input logic dataInP,
    input logic outEN_reg,
    output logic usbResetDetect
`ifdef USE_DEBUG_LEDS
    ,output logic LED_R,
    output logic LED_G,
    output logic LED_B
`endif
);

    typedef enum logic[1:0] {
        RX_WAIT_FOR_SYNC = 0,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_DPLL
    } RxStates;

    // TODO errror handling
    // Error handling relevant signals
    logic receiveBitStuffingError;
    logic pidValid;
    logic isValidCRC;

    logic isValidDPSig;

    assign isValidDPSig = dataInN ^ dataInP;

    // State variables
    RxStates rxState;
    PID_Types rxPID;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!
    logic dropPacket; // Drop reason might be i.e. receive errors!

    // Current signals
    logic receiveCLK;
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    // Detections
    logic nonBitStuffedInput;
    logic eopDetected;
    logic syncDetect;

    // Reset signals
    logic rxInputShiftRegReset;

    logic rxEopDetectorReset; // Requires explicit RST to clear eop flag again
    logic rxBitUnstuffingReset;
    logic rxNRZiDecodeReset;
    logic receiveClkGenRST;


`ifdef USE_DEBUG_LEDS
    initial begin
        LED_R = 1'b0;
        LED_G = 1'b0;
        LED_B = 1'b0;
    end

    always_ff @(posedge clk48) begin
        // Do not reset values once target signal value was achieved
        LED_R <= LED_R || dropPacket;
        LED_B <= LED_B || usbResetDetect;
    end
`endif

    // TODO we could only reset on switch to receive mode!
    // -> this would allow us to reuse the clk signal for transmission too!
    // -> hence, we have the same CLK domain and can reuse CRC and bit (un-)stuffing modules!
    //TODO is an reset needed before starting receive?
    assign receiveClkGenRST = outEN_reg || rxState == RX_RST_DPLL;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitUnstuffingReset = 1'b0;


    //===================================================
    // Initialization
    //===================================================
    initial begin
        rxState = RX_WAIT_FOR_SYNC;
        dropPacket = 1'b0;
        lastByteValidCRC = 1'b1;
    end

    //===================================================
    // State transitions
    //===================================================
    RxStates next_rxState, rxStateAdd1;
    PID_Types next_rxPID;
    logic next_dropPacket, next_lastByteValidCRC;

    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxEopDetectorReset = 1'b1; // Per default reset EOP detection

        next_rxState = rxState;
        next_rxPID = rxPID;
        next_dropPacket = dropPacket;
        next_lastByteValidCRC = lastByteValidCRC;

        unique case (rxState)
            RX_WAIT_FOR_SYNC: begin
                if (syncDetect) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                    //TODO trigger required resets right before payload data arrives
                    // Input shift register needs valid counter reset to be aligned with the incoming packet content
                    rxInputShiftRegReset = 1'b1;
                end
            end
            RX_GET_PID: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Also there may not be invalid differential pair signals as we expect the PID to be send!
                // Sanity check: was PID correctly received?
                next_dropPacket = dropPacket || receiveBitStuffingError || !isValidDPSig || (inputBufFull && !pidValid);

                if (inputBufFull) begin
                    // Save the PID for further decisions
                    next_rxPID = inputBuf[3:0];
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end
            end
            RX_WAIT_FOR_EOP: begin
                //TODO would be nice to integrate some isValidDPSig checks, but this might break logic very very easily!

                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = dropPacket || receiveBitStuffingError || (eopDetected && !lastByteValidCRC);

                // We need the EOP detection -> clear RST flag
                rxEopDetectorReset = 1'b0;

                if (eopDetected) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end else if (inputBufFull) begin
                    next_lastByteValidCRC = isValidCRC;
                    //TODO further processing is required! i.e. give data to next stage for processing
                    //TODO we probably do not want to give the crc data to the next stage how can we do so? just assume that the backend will ignore it?
                end
            end
            RX_RST_DPLL: begin
                // TODO we should probably publish the final dropPacket value!

                // Trigger some resets
                // TODO is a RST needed for the NRZI decoder?
                rxNRZiDecodeReset = 1'b1;

                // reset drop state
                next_dropPacket = 1'b0;
                // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
                next_lastByteValidCRC = 1'b1;
            end
            default: begin
                // Use default values
            end
        endcase
    end
    always_ff @(posedge receiveCLK) begin
        rxState <= next_rxState;
        rxPID <= next_rxPID;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
    end

    eop_reset_detect eopAndResetDetect(
        .clk48(clk48),
        .RST(rxEopDetectorReset),
        .dataInP(dataInP),
        .dataInN(dataInN),
        .eop(eopDetected),
        .usb_reset(usbResetDetect)
    );

    DPPL #() asyncRxCLK (
        .clk48(clk48),
        .RST(receiveClkGenRST),
        .a(dataInP), //TODO
        .b(dataInN), //TODO
        .readCLK12(receiveCLK),
    );

    //TODO reuse
    nrzi_encoder nrziDecoder(
        .clk12(receiveCLK),
        .RST(rxNRZiDecodeReset),
        .data(dataInP),
        .OUT(nrziDecodedInput)
    );

    //TODO reuse
    usb_bit_unstuff receiveBitUnstuffing(
        .clk12(receiveCLK),
        .RST(rxBitUnstuffingReset),
        .data(nrziDecodedInput),
        .valid(nonBitStuffedInput),
        .error(receiveBitStuffingError)
    );

    logic _syncDetect;
    sync_detect #(
        .SYNC_VALUE(SYNC_VALUE)
    ) packetBeginDetector(
        .receivedData(inputBuf[7:4]),
        .SYNC(_syncDetect)
    );
    assign syncDetect = _syncDetect && rxState == RX_WAIT_FOR_SYNC;

    input_shift_reg #() inputDeserializer(
        .clk12(receiveCLK),
        .RST(rxInputShiftRegReset),
        .EN(nonBitStuffedInput),
        .IN(nrziDecodedInput),
        .dataOut(inputBuf),
        .bufferFull(inputBufFull)
    );

    pid_check #() pidChecker (
        // Order does not matter as the check is actually commutative
        .pidP(inputBuf[7:4]),
        .pidN(inputBuf[3:0]),
        .isValid(pidValid)
    );

    logic useCRC5;
    // Needs thight timing -> use input buffer directly
    // CRC5 is only used for token packets -> identified by 2 lsb bits
    assign useCRC5 = inputBuf[1:0] == 2'b01;

    //TODO reuse
    logic [15:0] _unused_crc16;
    usb_crc crcEngine (
        .clk12(receiveCLK),
        .RST(rxState == RX_GET_PID), // Required at every new packet, can be a wire
        //TODO we need to exclude undesired fields too: this might already work as PID fields are excluded by design of the RST signal being high during PID reception
        .VALID(nonBitStuffedInput), // Indicates if current data is valid(no bit stuffing) and used for the CRC. Can be a wire
        .crc5_or_16(useCRC5), // Indicate which CRC should type should be calculated/checked, needs to be set when RST is set high
        .data(nrziDecodedInput),
        .validCRC(isValidCRC),
        .crc(_unused_crc16) //TODO only needed for transmission also ensure that it will be send in revere order (MSb first)!
    );

endmodule