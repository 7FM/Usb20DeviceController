`include "usb_ep_pkg.sv"
`include "usb_desc_pkg.sv"
`include "usb_dev_req_pkg.sv"
`include "usb_packet_pkg.sv"

// AKA control endpoint with address 0
module usb_endpoint_0 #(
    parameter USB_DEV_ADDR_WID = 7,
    parameter USB_DEV_CONF_WID = 8,
    parameter usb_ep_pkg::UsbDeviceEpConfig USB_DEV_EP_CONF,
    localparam usb_ep_pkg::ControlEndpointConfig EP_CONF = USB_DEV_EP_CONF.ep0Conf
)(
    input logic clk48_i,

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,
    output logic [USB_DEV_ADDR_WID-1:0] deviceAddr_o,
    output logic [USB_DEV_CONF_WID-1:0] deviceConf_o,

    input logic gotTransStartPacket_i,
    input logic [1:0] transStartTokenID_i,

    // Device IN interface
    input logic EP_IN_fillTransDone_i,
    input logic EP_IN_fillTransSuccess_i,
    input logic EP_IN_dataValid_i,
    input logic [7:0] EP_IN_data_i,
    output logic EP_IN_full_o,

    /*
    input logic EP_IN_popTransDone_i,
    input logic EP_IN_popTransSuccess_i,
    input logic EP_IN_popData_i,
    output logic EP_IN_dataAvailable_o,
    output logic [7:0] EP_IN_data_o,
    */

    // Device OUT interface
    /*
    input logic EP_OUT_fillTransDone_i,
    input logic EP_OUT_fillTransSuccess_i,
    input logic EP_OUT_dataValid_i,
    input logic [7:0] EP_OUT_data_i,
    output logic EP_OUT_full_o,
    */

    input logic EP_OUT_popTransDone_i,
    input logic EP_OUT_popTransSuccess_i,
    input logic EP_OUT_popData_i,
    output logic EP_OUT_dataAvailable_o,
    output logic EP_OUT_isLastPacketByte_o,
    output logic [7:0] EP_OUT_data_o,

    // Let usb_pe handle sending the PID, to save identical logic in each endpoint!
    // Also the usb_pe handle the maxPacketSize logic!
    // Signal that EP is ready to send a response
    output logic respValid_o,
    // Either data out phase or status out phase
    // Specify if the given pid ID should be interpret as DATA pid or handshake
    // If it is a handshake then no data will be popped and sent!
    // Else data will automatically be popped afterwards!
    output logic respHandshakePID_o,
    output logic [1:0] respPacketID_o
);

    usb_dev_req_pkg::SetupDataPacket setupDataPacket;

    //===============================================================================================================
    // Device State

    //logic suspended; // Currently not supported / considered
    typedef enum logic[1:0] {
        DEVICE_NOT_RESET = 0, // Ignore all transactions except reset signal
        DEVICE_RESET, // Responds to device and configuration descriptor requests & return information, uses default address
        DEVICE_ADDR_ASSIGNED, // responds to requests to default control pipe with default address as long as no address was assigned
        DEVICE_CONFIGURED // processed a SetConfiguration() request with non zero configuration value & endpoints data toggles are set to DATA0. Now the device functions may be used
    } DeviceState;

    DeviceState deviceState, nextDeviceState;

    logic [USB_DEV_ADDR_WID-1:0] nextDeviceAddr;
    logic [USB_DEV_CONF_WID-1:0] nextDeviceConf;

    initial begin
        deviceState = DEVICE_NOT_RESET;
        requestedBytesLeft = 16'b0;
    end

    logic gotAddrAssigned, gotDevConfig;

    // always ack usb resets if we are in the reset state
    assign ackUsbResetDetect_o = deviceState == DEVICE_RESET;

    always_comb begin
        nextDeviceState = deviceState;
        nextDeviceAddr = deviceAddr_o;
        nextDeviceConf = deviceConf_o;

        if (usbResetDetected_i) begin
            nextDeviceState = DEVICE_RESET;
            nextDeviceAddr = {USB_DEV_ADDR_WID{1'b0}};
            nextDeviceConf = {USB_DEV_CONF_WID{1'b0}};
        end else begin
            if (gotDevConfig) begin
                nextDeviceConf = setupDataPacket.wValue[USB_DEV_CONF_WID-1:0];

                // Update device state dependent on the configuration value!
                if (nextDeviceConf == 0) begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end else begin
                    nextDeviceState = DEVICE_CONFIGURED;
                end
            end else if (gotAddrAssigned) begin

                // Update device state dependent on the assigned address!
                nextDeviceAddr = setupDataPacket.wValue[USB_DEV_ADDR_WID-1:0];
                if (nextDeviceAddr == 0) begin
                    nextDeviceState = DEVICE_RESET;
                end else begin
                    nextDeviceState = DEVICE_ADDR_ASSIGNED;
                end
            end
        end
    end

    always_ff @(posedge clk48_i) begin
        deviceState <= nextDeviceState;
        deviceAddr_o <= nextDeviceAddr;
        deviceConf_o <= nextDeviceConf;
    end

    //===============================================================================================================
    // Device Request Handling

    localparam EP0_ROM_SIZE = usb_ep_pkg::requiredROMSize(USB_DEV_EP_CONF);
    localparam ROM_IDX_WID = $clog2(EP0_ROM_SIZE);
    localparam DESC_START_LUT_WID = usb_ep_pkg::requiredDescStartLUTSize(USB_DEV_EP_CONF);

    logic [DESC_START_LUT_WID - 1:0] descStartIdx;
    logic [7:0] romData;
    logic [ROM_IDX_WID-1:0] romTransReadIdx;

    ep0_rom #(
        .USB_DEV_EP_CONF(USB_DEV_EP_CONF)
    ) ep0rom (
        .readAddr_i(romTransReadIdx),
        .romData_o(romData),
        .descStartIdx_o(descStartIdx)
    );

    logic packetBufRst;
    assign packetBufRst = gotTransStartPacket_i; //TODO this is not always correct, see page 226
    logic packetBufFull;

    // Maximum packet size for EP0: only 8, 16, 32 or 64 bytes are valid!
    // MUST be 64 for high speed (EP0 only)!
    //localparam BUF_BYTE_COUNT = USB_DEV_EP_CONF.deviceDesc.bMaxPacketSize0;
    // BUT: with out simple implementation we only need to be able to store Setup Packets!
    localparam BUF_BYTE_COUNT = usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT;
    localparam BUF_WID = BUF_BYTE_COUNT * 8;
    logic [BUF_WID-1:0] packetBuf;

    logic byteIsData, nextByteIsData;

    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(BUF_BYTE_COUNT)
    ) packetBufWrapper (
        .clk_i(clk48_i),
        .rst_i(packetBufRst),

        .data_i(EP_IN_data_i),
        .dataValid_i(EP_IN_dataValid_i && byteIsData),

        .buffer_o(packetBuf),
        .isFull_o(packetBufFull)
    );

    assign setupDataPacket = usb_dev_req_pkg::SetupDataPacket'(packetBuf[usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT * 8 - 1 : 0]);

    typedef enum logic[1:0] {
        NEW_DEV_REQUEST,
        SEND_DESC,
        SEND_VAL,
        NO_OUTPUT_EXPECTED
    } EP0_State;

    EP0_State ep0State, nextEp0State;
    usb_dev_req_pkg::RequestCode deviceRequest;
    logic requestError, nextRequestError;
    //logic pidData1Expected, nextPidData1Expected;

    logic [ROM_IDX_WID-1:0] romReadIdx;
    logic [ROM_IDX_WID-1:0] nextRomReadIdx, nextRomTransReadIdx;
    logic [15:0] requestedBytesLeft, nextRequestedBytesLeft;
    logic epOutDataToggleState, nextEpOutDataToggleState;

    initial begin
        //pidData1Expected = 1'b0;
        epOutDataToggleState = 1'b0;
        ep0State = NO_OUTPUT_EXPECTED;
    end

    // Currently we only expect input for a new device request!
    assign EP_IN_full_o = packetBufFull || ep0State != NEW_DEV_REQUEST;

    logic epInHandshake;
    assign epInHandshake = EP_IN_dataValid_i && !EP_IN_full_o;
    logic epOutHandshake;
    assign epOutHandshake = EP_OUT_popData_i && EP_OUT_dataAvailable_o;

    // GET_STATUS & GET_INTERFACE are not supported -> return zero bytes
    assign EP_OUT_data_o = ep0State == SEND_DESC ? romData : (setupDataPacket.bRequest == usb_dev_req_pkg::GET_CONFIGURATION ? deviceConf_o : 8'b0);
    assign EP_OUT_isLastPacketByte_o = requestedBytesLeft == 1;
    // Only show data is available, when we are in a sending state!
    assign EP_OUT_dataAvailable_o = requestedBytesLeft != 0 && (ep0State == SEND_DESC || ep0State == SEND_VAL);

    //TODO If there is no Data stage, the Status stage is from the device to the host.
    //TODO we need to keep track of the global control transfer state (a control transaction contains multiple normal setup, IN / OUT transactions)
    //TODO A Status stage is delineated by a change in direction of data flow from the previous stage and always uses a DATA1 PID. 

    // 1'b1 signals that the PID is a handshake (host sent data or we have an request error)
    assign respHandshakePID_o = !setupDataPacket.bmRequestType.dataTransDevToHost || requestError;
    // This expects the usb_pe to check this flag only after the end of a corresponding phase
    // Also it is expected that if the device is supposed to send something and respValid_o == 1'b1 and EP_OUT_dataAvailable_o == 1'b0, then a zero length data packet should be send!
    // If a packet was incorrectly received then it is also expected that the usb_pe automatically issues a response timeout and ignores these signals!
    assign respValid_o = 1'b1;
    assign respPacketID_o = transStartTokenID_i == usb_packet_pkg::PID_IN_TOKEN[3:2] ? {epOutDataToggleState, 1'b0} : (requestError ? usb_packet_pkg::RES_STALL : usb_packet_pkg::RES_ACK);

generate
    always_comb begin
        nextEp0State = ep0State;
        gotAddrAssigned = 1'b0;
        gotDevConfig = 1'b0;
        nextEpOutDataToggleState = epOutDataToggleState;

        nextRomReadIdx = romReadIdx;
        nextRomTransReadIdx = romTransReadIdx;
        nextRequestedBytesLeft = requestedBytesLeft;
        nextRequestError = requestError;
        // Set this byte as soon as we have a handshake -> we skipped PID
        nextByteIsData = byteIsData;
        //nextPidData1Expected = pidData1Expected;

        // A new transaction started
        if (gotTransStartPacket_i) begin
            // Ignore the first byte which is the PID / ignore all data if it is not a device request, we do not expect any input!
            nextByteIsData = 1'b0;
            nextRequestError = 1'b0;
            if (transStartTokenID_i == usb_packet_pkg::PID_SETUP_TOKEN[3:2]) begin
                // it is an setup token -> go to new_dev_req state
                nextEp0State = NEW_DEV_REQUEST;
            end else begin
                //TODO check if token PID is valid, I guess we only allow Host IN tokens, otherwise it should be a setup TOKEN!

                //TODO test that for device requests with No Data Stage an empty Data Packet is returned upon request!

                //TODO check page 226

                // Handle SET_ADDRESS edge case: update is only done after the status stage: aka zero length data packet
                // Check if the previous setup transaction was set address & if the host wants to check the status & we had no error before
                if (!requestError && setupDataPacket.bRequest == usb_dev_req_pkg::SET_ADDRESS && transStartTokenID_i == usb_packet_pkg::PID_IN_TOKEN[3:2]) begin
                    // Now we are allowed to update our address!
                    gotAddrAssigned = 1'b1;
                end

                // Lets just ignore it
            end
        end else if (ep0State == NEW_DEV_REQUEST) begin
            if (!byteIsData && epInHandshake) begin
                /*
                // make PID checks (i.e. correct DATA toggle value)!
                if (EP_IN_data_i[0] != pidData1Expected) begin
                    // ignore this packet as we already received it
                    nextEp0State = NO_OUTPUT_EXPECTED;
                end else begin
                    // The pid has the correct toggle bit -> lets continue
                    // Once we have skipped the PID we have data bytes!
                    nextByteIsData = 1'b1;
                end
                */
                // For simplicity and as it should not matter for EP0, lets make no data toggle checks!
                // Once we have skipped the PID we have data bytes!
                nextByteIsData = 1'b1;
            end else if (EP_IN_fillTransDone_i) begin
                nextEp0State = NO_OUTPUT_EXPECTED;

                if (EP_IN_fillTransSuccess_i) begin
                    // The transaction was successful, lets toggle our expected data pid bit!
                    //nextPidData1Expected = !pidData1Expected;

                    nextRequestedBytesLeft = setupDataPacket.wLength;

                    // Only handle successful transfers
                    unique case (setupDataPacket.bRequest)
                        usb_dev_req_pkg::SET_ADDRESS: begin
                            if (`SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                /*
                                The spec says:
                                "
                                    Stages after the initial Setup packet assume the same device address as the Setup packet.
                                    The USB device does not change its device address until after the Status stage of this request is completed successfully.
                                    Note that this is a difference between this request and all other requests.
                                    For all other requests, the operation indicated must be completed before the Status stage.
                                "
                                The status stage is a different transaction -> we need to delay the address change!
                                */
                                //gotAddrAssigned = 1'b1;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::GET_DESCRIPTOR: begin
                            nextEp0State = SEND_DESC;
                            if (`GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState)) begin

                                case (setupDataPacket.wValue[15:8])
                                    usb_desc_pkg::DESC_DEVICE: begin
                                        // We only have a single device descriptor!
                                        nextRomReadIdx = {ROM_IDX_WID{1'b0}};
                                    end
                                    usb_desc_pkg::DESC_CONFIGURATION: begin
                                        // Depends on the descriptor index!
                                        if (setupDataPacket.wValue[7:0] < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations) begin
                                            // Index is valid
                                            nextRomReadIdx = descStartIdx[setupDataPacket.wValue[7:0] * ROM_IDX_WID +: ROM_IDX_WID];
                                        end else begin
                                            // Index is out of bounds!
                                            nextRequestError = 1'b1;
                                        end
                                    end
                                    usb_desc_pkg::DESC_STRING: begin
                                        // Depends on the descriptor index!
                                        if (USB_DEV_EP_CONF.stringDescCount > 0) begin
                                            if (setupDataPacket.wValue[7:0] < USB_DEV_EP_CONF.deviceDesc.bNumConfigurations) begin
                                                // Index is valid
                                                nextRomReadIdx = descStartIdx[(USB_DEV_EP_CONF.deviceDesc.bNumConfigurations + setupDataPacket.wValue[7:0]) * ROM_IDX_WID +: ROM_IDX_WID];
                                            end else begin
                                                // Index is out of bounds!
                                                nextRequestError = 1'b1;
                                            end
                                        end else begin
                                            // Index is out of bounds!
                                            nextRequestError = 1'b1;
                                        end
                                    end
                                    default: begin
                                        nextRequestError = 1'b1;
                                    end
                                endcase

                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::GET_CONFIGURATION: begin
                            if (`GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                nextEp0State = SEND_VAL;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::SET_CONFIGURATION: begin
                            if (`SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotDevConfig = 1'b1;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end

                        //===============================================================================================================================================
                        // NOTE: the following request are not really implemented!
                        // Requests that might not target the device:
                        //     SYNCH_FRAME: endpoint wIndex
                        //     CLEAR_FEATURE: device, interface or endpoint
                        //     SET_FEATURE: device, interface or endpoint
                        //     GET_STATUS: device, interface or endpoint

                        usb_dev_req_pkg::GET_INTERFACE: begin
                            if (`GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO This request returns the selected alternate setting for the specified interface
                                //TODO as we currently do not allow setting an alternate interface we can simply return 1 byte set to 0 which is the default interface!
                                nextEp0State = SEND_VAL;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::GET_STATUS: begin
                            if (`GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO This requests returns the status for the specified recipient
                                //TODO as we currently do not support features as remote wakeup or endpoint halting, we can always return 2 bytes set to 0
                                nextEp0State = SEND_VAL;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::SYNCH_FRAME: begin
                            if (`SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                // Is only used for isochronous data transfers using implicit pattern synchronization.
                                //TODO apply
                                //TODO this is required for isochronous endpoints
                                nextEp0State = SEND_VAL;
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        /*
                        usb_dev_req_pkg::SET_INTERFACE: begin
                            if (`SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO select an alternate setting for the specified interface
                                //TODO do we want to support alternate interfaces???
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        */
                        /*
                        usb_dev_req_pkg::SET_DESCRIPTOR: begin
                            // This request is optional to implement
                            nextRequestError = 1'b1;
                        end
                        */
                        /*
                        usb_dev_req_pkg::CLEAR_FEATURE: begin
                            if (`CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO do we want to support this?
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        usb_dev_req_pkg::SET_FEATURE: begin
                            if (`SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO do we want to support this?
                            end else begin
                                nextRequestError = 1'b1;
                            end
                        end
                        */
                        /*
                        usb_dev_req_pkg::RESERVED_2, usb_dev_req_pkg::RESERVED_4: begin
                            nextRequestError = 1'b1;
                        end
                        */
                        default: begin
                            //IMPL_SPECIFIC_13_255
                            // Else we have vendor/implementation specific requests -> delegate?
                            // For now lets just issue an request error
                            nextRequestError = 1'b1;
                        end
                    endcase
                end
            end
        end else begin
            if (epOutHandshake) begin
                if (ep0State == SEND_DESC) begin
                    nextRomTransReadIdx = romTransReadIdx + 1;
                end
                nextRequestedBytesLeft = requestedBytesLeft - 1;
            end else if (EP_OUT_popTransDone_i) begin
                if (EP_OUT_popTransSuccess_i) begin
                    // read was successful -> commit transaction counter
                    nextRomReadIdx = romTransReadIdx;
                    // Also toggle the data pid state
                    nextEpOutDataToggleState = !epOutDataToggleState;
                end else begin
                    // read failed -> reset transaction counter
                    nextRomTransReadIdx = romReadIdx;
                end
            end
        end
    end
endgenerate

    always_ff @(posedge clk48_i) begin
        ep0State <= nextEp0State;

        requestError <= nextRequestError;
        epOutDataToggleState <= nextEpOutDataToggleState;
        //TODO this needs to be reset to 0 on transition to certain device states too
        //pidData1Expected <= nextPidData1Expected;
        byteIsData <= nextByteIsData;

        requestedBytesLeft <= nextRequestedBytesLeft;
        romReadIdx <= nextRomReadIdx;
        romTransReadIdx <= nextRomTransReadIdx;
    end

endmodule
