module seq_generator (
  input   logic        clk,
  input   logic        reset,

  output  logic [31:0] seq_o
);
  
  logic [31:0] seq_r0, seq_r1, seq_sum;

  always_ff @(posedge clk, posedge reset) begin
    if (reset) begin
      seq_o  <= 32'd0;
      seq_r0 <= 32'd0;
      seq_r1 <= 32'd0;
    end else if (seq_o == 32'd0) begin
      seq_o  <= 32'd1;
    end else if (seq_r0 == 32'd0) begin
      seq_o <= 32'd1;
      seq_r0 <= seq_o;
    end else if (seq_r1 == 32'd0) begin
      seq_o <= 32'd1;
      seq_r0 <= seq_o;
      seq_r1 <= seq_r0;
    end else begin
      seq_o <= seq_r0 + seq_r1;
      seq_r0 <= seq_o;
      seq_r1 <= seq_r0;
    end
  end

endmodule
