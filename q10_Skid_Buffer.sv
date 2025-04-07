module skid_buffer (
  input   logic        clk,
  input   logic        reset,

  input   logic        i_valid_i,
  input   logic [7:0]  i_data_i,
  output  logic        i_ready_o,

  input   logic        e_ready_i,
  output  logic        e_valid_o,
  output  logic [7:0]  e_data_o
);

  logic       e_ready_q;

  logic [7:0] buf_data;
  logic       buf_valid;

  always_ff @(posedge clk, posedge reset) begin
    if (reset) begin
      buf_data  <= 0;
      buf_valid <= 0;
    end
    else if (~e_ready_i & i_valid_i & i_ready_o) begin
      buf_data  <= i_data_i;
      buf_valid <= 1;
    end
    else if (e_ready_i) begin
      buf_data  <= buf_data;
      buf_valid <= 0;
    end
  end

  always_ff @(posedge clk, posedge reset) begin
    if (reset) begin
      e_ready_q <= 0;
    end
    else begin
      e_ready_q <= e_ready_i;
    end
  end

  assign i_ready_o = ~buf_valid | e_ready_q;
  assign e_valid_o = buf_valid  | i_valid_i; 
  assign e_data_o  = buf_valid ? buf_data : i_data_i; 

endmodule
