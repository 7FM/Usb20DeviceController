module vector_mux#(
    parameter ELEMENTS,
    parameter DATA_WID,
    parameter IDX=0,
    localparam REMAINING_ELEMS = ELEMENTS - IDX,
    localparam ELEM_SEL_WID_MIN_1 = $clog2(ELEMENTS) - 1
)(
    input logic [ELEM_SEL_WID_MIN_1:0] dataSelect_i,
    input logic [(DATA_WID * REMAINING_ELEMS) - 1:0] dataVec_i,
    output logic [DATA_WID - 1:0] data_o
);

generate

    if (IDX < ELEMENTS - 1) begin
        logic [DATA_WID - 1:0] data_tmp;
        vector_mux #(
            .ELEMENTS(ELEMENTS),
            .DATA_WID(DATA_WID),
            .IDX(IDX + 1)
        ) nextVectorMux (
            .dataSelect_i(dataSelect_i),
            .dataVec_i(dataVec_i[(DATA_WID * REMAINING_ELEMS) - 1:DATA_WID]),
            .data_o(data_tmp)
        );

        assign data_o = data_tmp | ({DATA_WID{dataSelect_i == IDX[ELEM_SEL_WID_MIN_1:0]}} & dataVec_i[0 +: DATA_WID]);
    end else begin
        assign data_o = {DATA_WID{dataSelect_i == IDX[ELEM_SEL_WID_MIN_1:0]}} & dataVec_i[0 +: DATA_WID];
    end

endgenerate

endmodule

