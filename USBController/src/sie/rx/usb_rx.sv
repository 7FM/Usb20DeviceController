`include "config_pkg.sv"
`include "sie_defs_pkg.sv"
`include "usb_packet_pkg.sv"

`include "util_macros.sv"

module usb_rx#()(
    input logic clk12_i,
    input logic rxClk12_i,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    // CRC interface: rxClk12_i
    output logic rxCRCReset_o,
    output logic rxUseCRC16_o,
    output logic rxCRCInput_o,
    output logic rxCRCInputValid_o,
    input logic isValidCRC_i,

    // Bit stuffing interface: rxClk12_i
    output logic rxBitStuffRst_o,
    output logic rxBitStuffData_o,
    input logic expectNonBitStuffedInput_i,
    input logic rxBitStuffError_i,

    // Serial frontend input:
    input logic dataInP_i, // clk48_i
    input logic isValidDPSignal_i, // clk48_i
    input logic eopDetected_i, // clk48_i
    output logic ackEOP_o, // clk12_i

    // Data output interface: synced with clk12_i!
    input logic rxAcceptNewData_i, // Backend indicates that it is able to retrieve the next data byte
    output logic rxDone_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic [7:0] rxData_o, // data to be retrieved
    output logic keepPacket_o // should be tested when rxDone_o set to check whether an retrival error occurred
);

    logic emptyFifo;
    logic dataP_cdc, validSignal_cdc;

    logic eopDetectedRxCDC;
    logic eopDetectedCDC;
    cdc_sync eopDetectSync(
        .clk(rxClk12_i),
        .in(eopDetected_i),
        .out(eopDetectedRxCDC)
    );

    ASYNC_FIFO #(
        .ADDR_WID(3),
        .DATA_WID(3),
        .USE_DRAM(1) // Use normal regs as we do not need much data!
    ) bitSyncer(
        .w_clk_i(rxClk12_i),
        .dataValid_i(1'b1),
        .data_i({dataInP_i, isValidDPSignal_i, eopDetectedRxCDC}),
        `MUTE_PIN_CONNECT_EMPTY(full_o),

        .r_clk_i(clk12_i),
        .popData_i(1'b1),
        .empty_o(emptyFifo),
        .data_o({dataP_cdc, validSignal_cdc, eopDetectedCDC})
    );

    logic dataP, validSignal, eopDetectedSync;
    // when the fifo is empty then we clear the validSignal flag to ensure a error is detected in case that valid data was expected
    assign dataP = emptyFifo ? 1'b1 : dataP_cdc;
    assign validSignal = emptyFifo ? 1'b0 : validSignal_cdc;
    assign eopDetectedSync = emptyFifo ? 1'b0 : eopDetectedCDC;

    logic [7:0] inputBuf;
    logic rxGotNewInput;
    logic gotEopDetect;
    logic dropPacket;
    logic needCRC16Handling;

    usb_rx_interface rx_iface (
        .clk12_i(clk12_i),

`ifdef DEBUG_LEDS
`ifdef DEBUG_USB_RX_IFACE
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`else
        `MUTE_PIN_CONNECT_EMPTY(LED_R),
        `MUTE_PIN_CONNECT_EMPTY(LED_G),
        `MUTE_PIN_CONNECT_EMPTY(LED_B),
`endif
`endif

        .rxAcceptNewData_i(rxAcceptNewData_i),
        .rxDone_o(rxDone_o),
        .rxDataValid_o(rxDataValid_o),
        .rxData_o(rxData_o),
        .keepPacket_o(keepPacket_o),

        // clk12_i signals
        .inputBuf(inputBuf),
        .rxGotNewInput(rxGotNewInput),
        .gotEopDetect(gotEopDetect),
        .dropPacket_i(dropPacket),
        .needCRC16Handling(needCRC16Handling)
    );

    usb_rx_internal rx_internal (
        .clk12_i(clk12_i),

`ifdef DEBUG_LEDS
`ifdef DEBUG_USB_RX_INTERNAL
        .LED_R(LED_R),
        .LED_G(LED_G),
        .LED_B(LED_B),
`else
        `MUTE_PIN_CONNECT_EMPTY(LED_R),
        `MUTE_PIN_CONNECT_EMPTY(LED_G),
        `MUTE_PIN_CONNECT_EMPTY(LED_B),
`endif
`endif

        // CRC interface: clk12_i
        .rxCRCReset_o(rxCRCReset_o),
        .rxUseCRC16_o(rxUseCRC16_o),
        .rxCRCInput_o(rxCRCInput_o),
        .rxCRCInputValid_o(rxCRCInputValid_o),
        .isValidCRC_i(isValidCRC_i),

        // Bit stuffing interface: clk12_i
        .rxBitStuffRst_o(rxBitStuffRst_o),
        .rxBitStuffData_o(rxBitStuffData_o),
        .expectNonBitStuffedInput_i(expectNonBitStuffedInput_i),
        .rxBitStuffError_i(rxBitStuffError_i),

        // Serial frontend input: clk12_i
        .dataInP_i(dataP),
        .isValidDPSignal_i(validSignal),
        .eopDetected_i(eopDetectedSync),
        .ackEOP_o(ackEOP_o),

        // Rx interface signals
        .inputBuf_o(inputBuf),
        .rxGotNewInput_o(rxGotNewInput),
        .gotEopDetect(gotEopDetect),
        .dropPacket(dropPacket),
        .needCRC16Handling(needCRC16Handling)
    );

endmodule

module usb_rx_interface(
    input logic clk12_i,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    // Data output interface:
    input logic rxAcceptNewData_i, // Backend indicates that it is able to retrieve the next data byte
    output logic rxDone_o, // indicates that the current byte at rxData_o is the last one
    output logic rxDataValid_o, // rxData_o contains valid & new data
    output logic [7:0] rxData_o, // data to be retrieved
    output logic keepPacket_o, // should be tested when rxDone_o set to check whether an retrival error occurred

    // Rx interface signals:
    input logic [7:0] inputBuf,
    input logic rxGotNewInput,
    input logic gotEopDetect,
    input logic dropPacket_i,
    input logic needCRC16Handling
);

    logic fifoDataAvailable;
    logic fifoFull;
    logic fifoAcceptInput;

    logic allowFifoPop;
    logic flushFifo;

    REG_FIFO #(
        .DATA_WID(8),
        .ADDR_WID(1),
        .ENTRIES(2)
    ) rxDataFifo (
        .clk_i(clk12_i),
        .rst_i(flushFifo),

        .dataValid_i(rxGotNewInput),
        .data_i(inputBuf),
        .full_o(fifoFull),
        .acceptInput_o(fifoAcceptInput),

        .popData_i(allowFifoPop && rxAcceptNewData_i),
        .dataAvailable_o(fifoDataAvailable),
        `MUTE_PIN_CONNECT_EMPTY(isLast_o),
        .data_o(rxData_o)
    );

    logic byteWasNotReceived, next_byteWasNotReceived;
    assign rxDataValid_o = allowFifoPop && fifoDataAvailable;
    assign keepPacket_o = ~(dropPacket_i || byteWasNotReceived);

    typedef enum logic [0:0] {
        KEEP_FILLED,
        WAIT_UNTIL_EMPTY
    } RxIfaceStates;

    localparam FLUSH_TIMEOUT_CYCLES = 3;
    logic [1:0] flushFifoTimeout, nextFlushFifoTimeout;
    RxIfaceStates rxIfaceState, nextRxIfaceState;

    // For CRC5 packets all bytes contain data -> we do not need to hold any data back!
    // Else if we are waiting until the FIFO is empty
    assign allowFifoPop = (rxGotNewInput && fifoFull) || !needCRC16Handling;
    // for CRC16 packets flush the entire fifo as the last 2 bytes are the CRC!
    // we can drop keep flushing the fifo if we do not want to keep the packet anyway!
    assign flushFifo = gotEopDetect && needCRC16Handling || !keepPacket_o;

    always_comb begin
        rxDone_o = 1'b0;
        nextRxIfaceState = rxIfaceState;
        next_byteWasNotReceived = byteWasNotReceived;
        nextFlushFifoTimeout = flushFifoTimeout - 1;

        if (!fifoAcceptInput && rxGotNewInput) begin
            // The fifo does not accept our new input -> this byte will be dropped!
            next_byteWasNotReceived = 1'b1;
        end

        unique case (rxIfaceState)
            KEEP_FILLED: begin
                nextFlushFifoTimeout = FLUSH_TIMEOUT_CYCLES;
                if (gotEopDetect) begin
                    nextRxIfaceState = WAIT_UNTIL_EMPTY;
                end
            end
            WAIT_UNTIL_EMPTY: begin
                if (flushFifoTimeout == 0) begin
                    // Timeout, set error bit! To prevent a deadlock.
                    next_byteWasNotReceived = 1'b1;
                end else if (!fifoDataAvailable) begin
                    // Signal that all bytes of this packet were received!
                    rxDone_o = 1'b1;
                    // We are done for this packet -> clear the error flag
                    next_byteWasNotReceived = 1'b0;
                    nextRxIfaceState = KEEP_FILLED;
                end
            end
        endcase
    end

    initial begin
        rxIfaceState = KEEP_FILLED;
        byteWasNotReceived = 1'b0;
    end

    always_ff @(posedge clk12_i) begin
        flushFifoTimeout <= nextFlushFifoTimeout;
        byteWasNotReceived <= next_byteWasNotReceived;
        rxIfaceState <= nextRxIfaceState;
    end

`ifdef DEBUG_LEDS
    logic inv_LED_R;
    logic inv_LED_G;
    logic inv_LED_B;
    initial begin
        inv_LED_R = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_G = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_B = 1'b0; // a value of 1 turns the LEDs off!
    end
    always_ff @(posedge clk12_i) begin
        inv_LED_R <= inv_LED_R || byteWasNotReceived; // This condition gets true, which is a bad sign and should under normal circumstances never happen!
        // inv_LED_G <= inv_LED_G || dropPacket_i;
        inv_LED_B <= inv_LED_B || (rxIfaceState == WAIT_UNTIL_EMPTY && flushFifoTimeout == 0);
    end

    assign LED_R = !inv_LED_R;
    assign LED_G = !inv_LED_G;
    assign LED_B = !inv_LED_B;
`endif

endmodule

module usb_rx_internal(
    input logic clk12_i,

`ifdef DEBUG_LEDS
    output logic LED_R,
    output logic LED_G,
    output logic LED_B,
`endif

    // CRC interface:
    output logic rxCRCReset_o,
    output logic rxUseCRC16_o,
    output logic rxCRCInput_o,
    output logic rxCRCInputValid_o,
    input logic isValidCRC_i,

    // Bit stuffing interface:
    output logic rxBitStuffRst_o,
    output logic rxBitStuffData_o,
    input logic expectNonBitStuffedInput_i,
    input logic rxBitStuffError_i,

    // Serial frontend input:
    input logic dataInP_i,
    input logic isValidDPSignal_i,
    input logic eopDetected_i,
    output logic ackEOP_o,

    // Rx interface signals:
    output logic [7:0] inputBuf_o,
    output logic rxGotNewInput_o,
    output logic gotEopDetect,
    output logic dropPacket, // Drop reason might be i.e. receive errors!
    output logic needCRC16Handling
);

    typedef enum logic [1:0] {
        RX_WAIT_FOR_SYNC = 0,
        RX_GET_PID,
        RX_WAIT_FOR_EOP,
        RX_RST_PHASE
    } RxStates;

    // Error handling relevant signals
    logic pidValid;

    // State variables
    RxStates rxState;
    logic lastByteValidCRC; // Save current valid CRC flag after each received byte to ensure no difficulties with EOP detection!

    logic nextNeedCRC16Handling;

    // Current signals
    logic nrziDecodedInput;
    logic [7:0] inputBuf;
    logic inputBufFull;

    assign rxBitStuffData_o = nrziDecodedInput;
    //TODO is a RST even needed? sync signal should automagically cause the required resets
    assign rxBitStuffRst_o = 1'b0;

    logic isByteData;
    logic isRxWaitForEop;
    logic awaitsPID;
    assign awaitsPID = rxState == RX_GET_PID;
    assign isRxWaitForEop = rxState == RX_WAIT_FOR_EOP;
    assign isByteData = awaitsPID || isRxWaitForEop;

    // Propagate the pipeline when inputBufFull is set
    assign rxGotNewInput_o = (isByteData && inputBufFull);
    assign inputBuf_o = inputBuf;

    // Requires explicit RST to clear eop flag again
    // If waiting for EOP -> we need the detection -> clear RST flag
    assign ackEOP_o = isRxWaitForEop && eopDetected_i;

    assign gotEopDetect = eopDetected_i && isRxWaitForEop;

    // Detections
    logic syncDetect;
    logic gotInvalidDPSignal;

    // Reset signals
    logic rxInputShiftRegReset;
    logic rxInputShiftRegClear;
    logic rxNRZiDecodeReset;

    logic byteGotSignalError;

    //===================================================
    // Initialization
    //===================================================
    initial begin
        rxState = RX_WAIT_FOR_SYNC;
        dropPacket = 1'b0;
        byteGotSignalError = 1'b0;
        lastByteValidCRC = 1'b1;
    end

    //===================================================
    // State transitions
    //===================================================
    RxStates next_rxState, rxStateAdd1;
    logic next_dropPacket, next_lastByteValidCRC, next_byteGotSignalError;

    logic signalError;
    assign signalError = gotInvalidDPSignal || rxBitStuffError_i;
    logic defaultNextByteGotSignalError;
    assign defaultNextByteGotSignalError = byteGotSignalError || signalError;

    logic defaultNextDropPacket;
    // Variant which CAN detect missing bit stuffing after CRC edge case: even if this was the last byte, the following bit still needs to statisfy the bit stuffing condition
    assign defaultNextDropPacket = dropPacket || (inputBufFull && (byteGotSignalError || rxBitStuffError_i));
    // Variant which can NOT detect missing bit stuffing after CRC edge case
    //assign defaultNextDropPacket = dropPacket || (inputBufFull && byteGotSignalError);
    assign rxStateAdd1 = rxState + 1;

    always_comb begin
        rxInputShiftRegReset = 1'b0;
        rxInputShiftRegClear = 1'b0;
        rxNRZiDecodeReset = 1'b0;
        rxCRCReset_o = 1'b0;

        next_rxState = rxState;
        nextNeedCRC16Handling = needCRC16Handling;

        // Ensure that the previous dropPacket wont be changed by default!
        next_dropPacket = dropPacket;
        next_byteGotSignalError = defaultNextByteGotSignalError;
        next_lastByteValidCRC = lastByteValidCRC;

        unique case (rxState)
            RX_WAIT_FOR_SYNC: begin
                if (syncDetect) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                    //TODO trigger required resets right before payload data arrives
                    // Input shift register needs valid counter reset to be aligned with the incoming packet content
                    rxInputShiftRegReset = 1'b1;

                    // reset drop state
                    next_dropPacket = 1'b0;
                    next_byteGotSignalError = 1'b0;
                end
            end
            RX_GET_PID: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Also there may not be invalid differential pair signals as we expect the PID to be send!
                // Sanity check: was PID correctly received?
                next_dropPacket = defaultNextDropPacket || (inputBufFull && !pidValid);

                if (inputBufFull) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end else begin
                    // If inputBufFull is set, we already receive the first data bit -> hence crc needs to receive this bit -> but CRC reset low
                    rxCRCReset_o = 1'b1;
                    // As during CRC reset the rxUseCRC16_o flag is evaluated we can use it for our purposes too
                    nextNeedCRC16Handling = rxUseCRC16_o;
                end
            end
            RX_WAIT_FOR_EOP: begin
                // After Sync was detected, we always need valid bit stuffing!
                // Sanity check: does the CRC match?
                next_dropPacket = defaultNextDropPacket || (eopDetected_i && !lastByteValidCRC);

                if (eopDetected_i) begin
                    // Go to next state
                    next_rxState = rxStateAdd1;
                end else if (inputBufFull) begin
                    // Update is valid crc flag after each byte such that when we receive EOP we can check if the crc was correct for the last byte -> the entire packet!
                    next_lastByteValidCRC = isValidCRC_i;
                end
            end
            RX_RST_PHASE: begin
                // Go back to the initial state
                next_rxState = RX_WAIT_FOR_SYNC;

                // Trigger some resets
                // TODO is a RST needed for the NRZI decoder?
                rxNRZiDecodeReset = 1'b1;

                // We need to clear the content to ensure that the currently stored data won't be detected as sync
                rxInputShiftRegClear = 1'b1;

                // ensure that CRC flag is set to valid again to allow for simple HANDSHAKE packets without payload -> no CRC is used
                next_lastByteValidCRC = 1'b1;
            end
        endcase
    end

    // State updates
    always_ff @(posedge clk12_i) begin
        rxState <= next_rxState;
        needCRC16Handling <= nextNeedCRC16Handling;
        dropPacket <= next_dropPacket;
        lastByteValidCRC <= next_lastByteValidCRC;
        // After each received byte reset the byte signal error state
        byteGotSignalError <= inputBufFull ? signalError : next_byteGotSignalError;
        // We need to delay isValidDPSignal_i because our nrzi decoder introduces a delay to the decoded signal too
        gotInvalidDPSignal <= !isValidDPSignal_i;
    end

    // Stage 0
    nrzi_decoder nrziDecoder(
        .clk12_i(clk12_i),
        .rst_i(rxNRZiDecodeReset),
        .data_i(dataInP_i),
        .data_o(nrziDecodedInput)
    );

    // Stage 1
    logic _syncDetect;
    sync_detect #(
        .SYNC_VALUE(sie_defs_pkg::SYNC_VALUE)
    ) packetBeginDetector(
        .receivedData_i(inputBuf[7:4]),
        .syncDetect_o(_syncDetect)
    );
    assign syncDetect = _syncDetect /*&& rxState == RX_WAIT_FOR_SYNC*/;

    input_shift_reg #() inputDeserializer(
        .clk12_i(clk12_i),
        .rst_i(rxInputShiftRegReset),
        .clear_i(rxInputShiftRegClear),
        .en_i(expectNonBitStuffedInput_i),
        .dataBit_i(nrziDecodedInput),
        .data_o(inputBuf),
        .bufferFull_o(inputBufFull)
    );

    pid_check #() pidChecker (
        // Order does not matter as the check is actually commutative
        .pidP_i(inputBuf[7:4]),
        .pidN_i(inputBuf[3:0]),
        .isValid_o(pidValid)
    );

    // Needs thight timing -> use input buffer directly
    // Only Data Packets use CRC16!
    // Packet types are identifyable by 2 lsb bits, which are at this stage not yet at the lsb location
    assign rxUseCRC16_o = inputBuf[2:1] == usb_packet_pkg::DATA_PACKET_MASK_VAL;
    assign rxCRCInputValid_o = expectNonBitStuffedInput_i;
    assign rxCRCInput_o = nrziDecodedInput;

`ifdef DEBUG_LEDS
    logic inv_LED_R;
    logic inv_LED_G;
    logic inv_LED_B;
    initial begin
        inv_LED_R = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_G = 1'b0; // a value of 1 turns the LEDs off!
        inv_LED_B = 1'b0; // a value of 1 turns the LEDs off!
    end
    always_ff @(posedge clk12_i) begin
        inv_LED_R <= inv_LED_R || (rxState == RX_WAIT_FOR_EOP && eopDetected_i && !lastByteValidCRC);
        inv_LED_G <= inv_LED_G || (rxState == RX_GET_PID && inputBufFull && !pidValid);
        inv_LED_B <= inv_LED_B || ((rxState == RX_GET_PID || rxState == RX_WAIT_FOR_EOP) && defaultNextDropPacket);
    end

    assign LED_R = !inv_LED_R;
    assign LED_G = !inv_LED_G;
    assign LED_B = !inv_LED_B;
`endif

endmodule
