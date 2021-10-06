// https://zipcpu.com/blog/2020/10/03/tfrvalue.html
module cdc_2phase_sync #(
    parameter DATA_WID
)(
    input logic clk1,
    input logic valid_i,
    output logic ready_o,
    input logic [DATA_WID-1:0] data_i,

    input logic clk2,
    input logic ready_i,
    output logic valid_o,
    output logic [DATA_WID-1:0] data_o
);
    logic req; // clk1
    logic[DATA_WID-1:0] cdcData; // clk1

    logic meta_req, req_sync, last_req_sync; // clk2
    //TODO reset logic
    initial begin
        meta_req = 1'b0;
        req_sync = 1'b0;
        last_req_sync = 1'b0;
        valid_o = 1'b0;
    end

    always_ff @(posedge clk2) begin
        {meta_req, req_sync} <= {req, meta_req};

        if (valid_o && !ready_i) begin
            // Do not propergate the ready ack signal if clk2 domain is not yet ready!
            last_req_sync <= last_req_sync;
        end else begin
            last_req_sync <= req_sync;
        end
    end
    logic newData_o;
    assign newData_o = req_sync != last_req_sync;

    always_ff @(posedge clk2) begin
        // newData_o should work as condition too, this stricter condition avoids multiple copies of the same data
        data_o <= newData_o && (!valid_o || ready_i) ? cdcData : data_o;
        // Accept new data if we have none stored yet, or currently stored data may be read anyways
        valid_o <= !valid_o || ready_i ? newData_o : valid_o;
    end

    logic meta_ack, ack_sync; // clk1
    //TODO reset logic
    initial begin
        meta_ack = 1'b0;
        ack_sync = 1'b0;
    end

    always_ff @(posedge clk1) begin
        {meta_ack, ack_sync} <= {last_req_sync, meta_ack};
    end
    assign ready_o = ack_sync == req;

    logic clk1_handshake;
    assign clk1_handshake = valid_i && ready_o;
    always_ff @(posedge clk1) begin
        req <= clk1_handshake ? !req : req;
        cdcData <= clk1_handshake ? data_i : cdcData;
    end

endmodule
