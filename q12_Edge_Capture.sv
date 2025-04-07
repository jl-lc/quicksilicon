module edge_capture (
  input   logic        clk,
  input   logic        reset,

  input   logic [31:0] data_i,

  output  logic [31:0] edge_o

);

  logic [31:0] data_q;
  logic [31:0] edge_q;

  always_ff @(posedge clk, posedge reset) begin
    if (reset)
      data_q <= 0;
    else
      data_q <= data_i;
  end

  always_ff @(posedge clk, posedge reset) begin
    if (reset)
      edge_q <= 0;
    else
      edge_q <= edge_o;
  end

  for (genvar i=0; i < 32; i++) begin
    assign edge_o[i] = ~data_i[i] & data_q[i] | edge_q[i];
  end

endmodule
