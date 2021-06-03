module vector_mux#(
    parameter ELEMENTS,
    parameter DATA_WID,
    parameter IDX=0
)(
    input logic [$clog2(ELEMENTS):0] dataSelect,
    input logic [(DATA_WID * ELEMENTS) - 1:0] dataVec,
    output logic [DATA_WID - 1:0] data
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
        .dataSelect(dataSelect),
        .dataVec(dataVec),
        .data(data_tmp)
    );

    assign data = data_tmp | ({DATA_WID{dataSelect == IDX[SEL_WID:0]}} & dataVec[(IDX+1)*DATA_WID-1:IDX*DATA_WID]);
end else begin
    assign data = {DATA_WID{dataSelect == IDX[SEL_WID:0]}} & dataVec[(IDX+1)*DATA_WID-1:IDX*DATA_WID];
end

endgenerate

endmodule

