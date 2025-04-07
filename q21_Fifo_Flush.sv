module fifo_flush (
  input   logic         clk,
  input   logic         reset,

  input   logic         fifo_wr_valid_i,
  input   logic [3:0]   fifo_wr_data_i,

  output  logic         fifo_data_avail_o,
  input   logic         fifo_rd_valid_i,
  output  logic [31:0]  fifo_rd_data_o,

  input   logic         fifo_flush_i,
  output  logic         fifo_flush_done_o,

  output  logic         fifo_empty_o,
  output  logic         fifo_full_o
);

  // how to size the fifo?
  // option 1: each entry = size of write data
  //    reading data would require reading 4 entries:
  //        have 1 rd_ptr and read rd_ptr, rd_ptr+1, rd_ptr+2, rd_ptr+3. Not good for timing
  //        have 4 rd_ptr to simultaneously read 4 entries. Not good for area
  // option 2: each entry = size of read data (preferred soln)
  //    writing data would be more complex
  //    1 wr_ptr for col, 1 wr_ptr for row, 1 rd_ptr for row
  // option 3: just 1D vector [127:0] (my initial implementation)
  //    suppose scenario: flush is issued before a whole word is written. read is not asserted. buffer is "filled up"
  //    the buffer isn't truly "full" since the ptr skips the rest of the word
  //    this option technically should solve this issue that option 2 presents
  //    however, implementation seems far more challenging
  //
  // take homes:
  // need to use generates since indexing cannot be variable
  // +: part-select indexing syntax: base_expr +: width
  // add extra bit to differentiate empty and full. eliminate need for cntr


  logic  [2:0] wr_ptr_col, rd_ptr_col;
  logic  [2:0] wr_ptr_row, rd_ptr_row; // msb for diff empty & full
  logic        fifo_flush_q, fifo_flush_edge;

  logic [31:0] mem [3:0];

  always_ff @(posedge clk, posedge reset) fifo_flush_q <= reset ? 0 : fifo_flush_i;
  assign fifo_flush_edge = fifo_flush_i & ~fifo_flush_q;
  
  for (genvar ii = 0; ii < 8; ii++) begin : write_data
    always_ff @(posedge clk, posedge reset) begin
      if (reset) begin
        mem[0] <= 0;
        mem[1] <= 0;
        mem[2] <= 0;
        mem[3] <= 0;
      end
      else if (wr_ptr_col == ii[2:0] && fifo_wr_valid_i) begin
        mem[wr_ptr_row[1:0]][ii[2:0]*4 +: 4] <= fifo_wr_data_i;
      end
    end
  end

  always_ff @(posedge clk, posedge reset) begin : write_pointer_column
    if (reset) begin
      wr_ptr_col <= 0;
    end
    else if (fifo_flush_edge) begin
      wr_ptr_col <= 3'h0;
    end
    else if (fifo_wr_valid_i) begin
      wr_ptr_col <= wr_ptr_col + 3'h1;
    end
  end

  always_ff @(posedge clk, posedge reset) begin : read_pointer_column
    if (reset) begin
      rd_ptr_col <= 0;
    end
    else begin
      casez ({rd_ptr_row == wr_ptr_row, fifo_flush_i, fifo_rd_valid_i, fifo_wr_valid_i})
        4'b00??:  rd_ptr_col <= rd_ptr_col;
        4'b010?:  rd_ptr_col <= rd_ptr_col;
        4'b0110:  rd_ptr_col <= wr_ptr_col;
        4'b0111:  rd_ptr_col <= wr_ptr_col + 3'h1;

        4'b10?0:  rd_ptr_col <= rd_ptr_col;
        4'b10?1:  rd_ptr_col <= wr_ptr_col + 3'h1;
        4'b1100:  rd_ptr_col <= rd_ptr_col;
        4'b1101:  rd_ptr_col <= rd_ptr_col + 3'h1;
        4'b1110:  rd_ptr_col <= 3'h0;
        4'b1111:  rd_ptr_col <= wr_ptr_col + 3'h1;
      endcase
    end
  end

  always_ff @(posedge clk, posedge reset) begin : write_pointer_row
    if (reset) begin
      wr_ptr_row <= 0;
    end
    else if ((fifo_wr_valid_i && &wr_ptr_col ) || (fifo_flush_edge && |wr_ptr_col)) begin
      wr_ptr_row <= wr_ptr_row + 3'h1;
    end
  end

  always_ff @(posedge clk, posedge reset) begin : read_pointer_row
    if (reset) begin
      rd_ptr_row <= 0;
    end
    else if (fifo_rd_valid_i) begin
      rd_ptr_row <= rd_ptr_row + 3'h1;
    end
  end

  for (genvar ii = 0; ii < 8; ii++) begin : read_data
    assign fifo_rd_data_o[ii[2:0]*4 +: 4] = ~|rd_ptr_col && (fifo_full_o || fifo_data_avail_o) ?
                                            mem[rd_ptr_row[1:0]][ii[2:0]*4 +: 4] : 
                                            rd_ptr_col <= ii ? 
                                            4'hC : mem[rd_ptr_row[1:0]][ii[2:0]*4 +: 4];
  end

  assign fifo_full_o       = rd_ptr_row[2] != wr_ptr_row[2];
  assign fifo_empty_o      = rd_ptr_row == wr_ptr_row & ~|rd_ptr_col ;
  assign fifo_data_avail_o = ~fifo_empty_o;
  assign fifo_flush_done_o = fifo_flush_i & fifo_rd_valid_i & (wr_ptr_row-3'h1 == rd_ptr_row || wr_ptr_row == rd_ptr_row);

endmodule
