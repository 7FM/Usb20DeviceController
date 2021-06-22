module vector_mux#(
    parameter ELEMENTS,
    parameter DATA_WID,
    parameter IDX=0
)(
    input logic [$clog2(ELEMENTS):0] dataSelect_i,
    input logic [(DATA_WID * ELEMENTS) - 1:0] dataVec_i,
    output logic [DATA_WID - 1:0] data_o
);

    localparam SEL_WID = $clog2(ELEMENTS);

generate

    if (IDX < ELEMENTS - 1) begin
        logic [DATA_WID - 1:0] data_tmp;
        vector_mux #(
            .ELEMENTS(ELEMENTS),
            .DATA_WID(DATA_WID),
            .IDX(IDX + 1)
        ) nextVectorMux (
            .dataSelect_i(dataSelect_i),
            .dataVec_i(dataVec_i),
            .data_o(data_tmp)
        );

        assign data_o = data_tmp | ({DATA_WID{dataSelect_i == IDX[SEL_WID:0]}} & dataVec_i[IDX*DATA_WID +: DATA_WID]);
    end else begin
        assign data_o = {DATA_WID{dataSelect_i == IDX[SEL_WID:0]}} & dataVec_i[IDX*DATA_WID +: DATA_WID];
    end

endgenerate

endmodule

