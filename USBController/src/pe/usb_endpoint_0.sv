`include "usb_ep_pkg.sv"
`include "usb_desc_pkg.sv"
`include "usb_dev_req_pkg.sv"
`include "usb_packet_pkg.sv"

// AKA control endpoint with address 0
module usb_endpoint_0 #(
    parameter USB_DEV_ADDR_WID = 7,
    parameter USB_DEV_CONF_WID = 8,
    parameter usb_ep_pkg::ControlEndpointConfig EP_CONF
)(
    input logic clk48_i,

    input logic usbResetDetected_i,
    output logic ackUsbResetDetect_o,
    output logic [USB_DEV_ADDR_WID-1:0] deviceAddr_o,
    output logic [USB_DEV_CONF_WID-1:0] deviceConf_o,

    input logic gotTransStartPacket_i,
    input usb_packet_pkg::PID_Types transStartPID_i,

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
    output logic EP_OUT_isLastPacketByte_o, //TODO
    output logic [7:0] EP_OUT_data_o
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
        //TODO does deviceAddr_o/deviceConf_o require an explicit initial Reset? or is relying on usb DEVICE RESET enough?
    end

    logic gotAddrAssigned, gotDevConfig;

    always_comb begin
        nextDeviceState = deviceState;
        nextDeviceAddr = deviceAddr_o;
        nextDeviceConf = deviceConf_o;

        // always ack usb resets if we are in the reset state 
        ackUsbResetDetect_o = deviceState == DEVICE_RESET;

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

    //TODO adjust data width
    typedef enum logic[1:0] {
        //TODO
        NEW_DEV_REQUEST,
        HANDLE_REQUEST
    } EP0_State;

    localparam BUF_BYTE_COUNT = 64;
    logic packetBufRst;
    logic packetBufFull;
    
    localparam BUF_WID = BUF_BYTE_COUNT * 8;

    logic [BUF_WID-1:0] packetBuf;

    vector_buf #(
        .DATA_WID(8),
        .BUF_SIZE(BUF_BYTE_COUNT)
    ) packetBufWrapper (
        .clk_i(clk48_i),
        .rst_i(packetBufRst),

        .data_i(EP_IN_data_i),
        .dataValid_i(EP_IN_dataValid_i),

        .buffer_o(packetBuf),
        .isFull_o(packetBufFull)
    );

    EP0_State ep0State, nextEp0State;
    usb_dev_req_pkg::RequestCode deviceRequest;

    assign setupDataPacket = usb_dev_req_pkg::SetupDataPacket'(packetBuf[usb_dev_req_pkg::SETUP_DATA_PACKET_BYTE_COUNT * 8 - 1 : 0]);

    initial begin
        ep0State = NEW_DEV_REQUEST;
    end

    assign EP_IN_full_o = packetBufFull || (ep0State == NEW_DEV_REQUEST ? 1'b0 //TODO
        : setupDataPacket.bmRequestType.dataTransDevToHost /*Error if we expect to send data!*/);

    always_comb begin
        nextEp0State = ep0State;
        gotAddrAssigned = 1'b0;
        gotDevConfig = 1'b0;
        packetBufRst = EP_IN_fillTransDone_i || gotTransStartPacket_i;

        // A new transaction started
        if (gotTransStartPacket_i) begin
            if (transStartPID_i[3:2] == usb_packet_pkg::PID_SETUP_TOKEN[3:2]) begin
                // it is an setup token -> go to new_dev_req state
                nextEp0State = NEW_DEV_REQUEST;
            end else begin
                //TODO check if PID is valid (i.e. correct DATA toggle value)!
            end
        end else if (ep0State == NEW_DEV_REQUEST) begin
            if (EP_IN_fillTransDone_i) begin
                nextEp0State = HANDLE_REQUEST;

                if (EP_IN_fillTransSuccess_i) begin
                    // Only handle successful transfers
                    unique case (setupDataPacket.bRequest)                    
                        usb_dev_req_pkg::GET_STATUS: begin
                            if (`GET_STATUS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::CLEAR_FEATURE: begin
                            if (`CLEAR_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_FEATURE: begin
                            if (`SET_FEATURE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_ADDRESS: begin
                            if (`SET_ADDRESS_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotAddrAssigned = 1'b1;
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::GET_DESCRIPTOR: begin
                            if (`GET_DESCRIPTOR_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_DESCRIPTOR: begin
                            // This request is optional to implement
                            //TODO request error!
                        end
                        usb_dev_req_pkg::GET_CONFIGURATION: begin
                            if (`GET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_CONFIGURATION: begin
                            if (`SET_CONFIGURATION_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                gotDevConfig = 1'b1;
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::GET_INTERFACE: begin
                            if (`GET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SET_INTERFACE: begin
                            if (`SET_INTERFACE_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::SYNCH_FRAME: begin
                            if (`SYNCH_FRAME_SANITY_CHECKS(setupDataPacket, deviceState)) begin
                                // Is only used for isochronous data transfers using implicit pattern synchronization.
                                //TODO apply
                            end else begin
                                //TODO request error!
                            end
                        end
                        usb_dev_req_pkg::RESERVED_2, usb_dev_req_pkg::RESERVED_4: begin
                            //TODO request error!
                        end
                        default: begin
                            //IMPL_SPECIFIC_13_255
                            // Else we have vendor/implementation specific requests -> delegate?
                            // For now lets just issue an request error
                            //TODO request error!
                        end
                    endcase
                end
            end
        end
    end

    always_ff @(posedge clk48_i) begin
        ep0State <= nextEp0State;
    end

endmodule
