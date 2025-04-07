`timescale 1ns / 1ps

module lru #(
  parameter NUM_WAYS = 4
)(
  input   logic                         clk,
  input   logic                         reset,

  input   logic                         ls_valid_i,
  input   logic [1:0]                   ls_op_i,
  input   logic [$clog2(NUM_WAYS)-1:0]  ls_way_i,

  output  logic                         lru_valid_o,
  output  logic [NUM_WAYS-1:0]          lru_way_o
);

  // Design a Least Recently Used module for a N-way set associative cache. The number of ways for the cache are parameterized but will always be a power of 2. 
  //
  // ls_valid_i indicates valid operation
  // store op:
  //    ignores ls_way_i
  //    stores in priority
  //        first empty (not valid) cache index
  //        lru 
  //    outputs lru_valid_o if store is valid
  //    outputs lru_way_o which cache way it's stored in, IN SAME CYCLE
  // invalid op:
  //    invalidates cache in ls_way_i (empties it)
  // load op:
  //    essentially updates order of recently used since no data involved in this module
  //
  // take homes:
  // typdef enum for clarity
  // use temp var in for loop to avoid latch inference
  // careful of nested gen loops
  //
  // implementation:
  // age matrix to track age of cache instead of counter or fifo. 
  // simplifies logic. updating matrix is just changing way row to all 0s
  //    e.g.     age matrix: row older than col? 1 : 0
  //     lru          way0 way1 way2 way3   
  //    way2 =>  way0    1    1    0    0  =>   0     1
  //    way3 =>  way1    0    1    0    0  =>   0     1
  //    way0 =>  way2    1    1    1    1  =>   1     1 => lru (the row are all 1s, ignore diagonal)
  //    way1 =>  way3    1    1    0    1  =>   0     1
  //     mru                                  age valid  
  // values are negated across the diagonal => only ((NUM_WAYS * NUM_WAYS - NUM_WAYS)/2) # of flops needed
  //    e.g.
  //    way0    
  //    way1    0    
  //    way2    1    1   
  //    way3    1    1    0   
  // mapping for detecting which way is lru: (col,row)
  //    (0,1) = 0; (0,2) = 0; (0,3) = 0; -> way0 lru
  //        way0   (1)  (1)  (1)  (1)
  //        way1    0    
  //        way2    0    x   
  //        way3    0    x    x   
  //    (0,1) = 1; (1,2) = 0; (1,3) = 0; -> way1 lru
  //        way0    
  //        way1    1   (1)  (1)  (1)
  //        way2    x    0   
  //        way3    x    0    x   
  //    (0,2) = 1; (1,2) = 1; (2,3) = 0; -> way2 lru
  //        way0    
  //        way1    x    
  //        way2    1    1   (1)  (1)
  //        way3    x    x    0   
  //    (0,3) = 1; (1,3) = 1; (2,3) = 1; -> way3 lru
  //        way0    
  //        way1    x    
  //        way2    x    x   
  //        way3    1    1    1   (1)
  // formula for mapping 2D lower/upper triangle excl diag to flat 1D index:
  //    for each col c < i: N-1-c entries => (c, c+1), (c,c+2), ... ,(c,N-1)
  //    entries before col i: 
  //        sum from c=0 to (i-1) of (N-1-c)
  //        => i*N - (i*(i+1))/2
  //    entries offset in col: (valid row values are col+1 to N-1)
  //        => row - col - 1
  //    (col, row) = (col * NUM_WAYS - (col * (col + 1)) / 2) + (row - col - 1); // can be (row, col) for upper triangle
  //
  // why not just memory?
  // just memory itself isn't realistic
  //    not just a simple fifo. need to deal with loading
  //    need to find index from cache way that needs to be loaded (updated)
  //    delete content from that index, shift all preceding contents by 1 to maintain order, add way into memory
  //    cannot be same cycle
  // hash map + doubly linked list?
  //    not simple in hardware. 2 memories to do hashing and track order?
  //    cannot be same cycle
  //    also lots of combinational logic: 
  //        modulo, chain comparison O(N) linear probing, extra registers to store key and value (data, in this case ignored)
  // 
  // age matrix always returns lru immediately. automatically maintains order. updating/loading is simple
  // 6 + 4 flops needed for N=4 ways. N*(N+1)/2 flops in general

  typedef enum logic [1:0] {
    LD  = 2'b01,
    STR = 2'b10,
    INV = 2'b11
  } ls_op_t;
  
  localparam NUM_BITS     = (NUM_WAYS * NUM_WAYS - NUM_WAYS)/2; // triangular matrix
  localparam NUM_WAYS_LG2 = $clog2(NUM_WAYS);

  logic                load_valid, str_valid, inv_valid;
  logic [NUM_WAYS-1:0] ls_update, ls_store, ls_invalidate;
  logic [NUM_WAYS-1:0] mem_valid;
  logic [NUM_WAYS-1:0] ls_lru;
  logic [NUM_WAYS-1:0] ls_way;
  logic [NUM_BITS-1:0] tm_wire;
  logic [NUM_BITS-1:0] tm_reg;
  logic [NUM_WAYS_LG2-1:0] idx;

  assign load_valid = ls_valid_i & ls_op_i == LD;
  assign str_valid  = ls_valid_i & ls_op_i == STR;
  assign inv_valid  = ls_valid_i & ls_op_i == INV;

  // load operation
  for (genvar i=0; i < NUM_WAYS; i++) begin : g_one_hot_load // ;)
    assign ls_update[i] = load_valid & ls_way_i == i[NUM_WAYS_LG2-1:0];
  end

  // store operation
  assign ls_store = {NUM_WAYS{str_valid}} & lru_way_o;

  // invalidate operation
  for (genvar i=0; i < NUM_WAYS; i++) begin : g_one_hot_invalidate
    assign ls_invalidate[i] = inv_valid & ls_way_i == i[NUM_WAYS_LG2-1:0];
  end

  // memory tag valid
  always_ff @(posedge clk, posedge reset) begin
    if (reset)
      mem_valid <= 0;
    else
      mem_valid <= mem_valid & ~ls_invalidate | ls_store;
  end

  // triangular age matrix
  always_ff @(posedge clk, posedge reset) begin
    if (reset) begin
      tm_reg <= 0;
    end
    else begin
      tm_reg <= tm_wire;
    end
  end

  // update triangular age matrix
  for (genvar col=0; col < NUM_WAYS; col++) begin
    for (genvar row=col+1; row < NUM_WAYS; row++) begin : g_wr_tri
      localparam int IDX = (col * NUM_WAYS - (col * (col + 1)) / 2) + (row - col - 1); // pair2idx

      always_comb begin
        if ((load_valid & ls_update[col]) | (str_valid & lru_way_o[col]))
          tm_wire[IDX] = 1;
        else if ((load_valid & ls_update[row]) | (str_valid & lru_way_o[row]))
          tm_wire[IDX] = 0;
        else
          tm_wire[IDX] = tm_reg[IDX];
      end
    end
  end

  // find lru 
  for (genvar way=0; way < NUM_WAYS; way++) begin : g_lru_check
    logic [NUM_WAYS-2:0] lru_check; // NUM_WAYS-1 elements to check

    for (genvar col=0; col < NUM_WAYS; col++) begin
      for (genvar row=col+1; row < NUM_WAYS; row++) begin : g_rd_tri
        localparam int IDX = (col * NUM_WAYS - (col * (col + 1)) / 2) + (row - col - 1); // pair2idx

        if (col == way) begin
          assign lru_check[row-1] = tm_reg[IDX] == 0;
        end
        else if (row == way) begin // excl. diag.
          assign lru_check[col] = tm_reg[IDX] == 1;
        end
      end
    end

    assign ls_lru[way] = &lru_check;
  end

  // find first invalid tag
  logic [NUM_WAYS_LG2-1:0] idx_next;
  always_comb begin : priority_encoder
    idx_next = 0;
    for (int way=NUM_WAYS-1; way >= 0; way--) begin
      if (mem_valid[way] == 1'b0)
        idx_next = way[NUM_WAYS_LG2-1:0];
    end
  end
  assign idx = idx_next;

  // one-hot invalid tag index
  always_comb begin : one_hot_valid_tag
    ls_way = '0;
    if (str_valid)
      ls_way[idx] = 1'b1;
  end

  // outputs
  assign lru_way_o   = &mem_valid ? ls_lru : ls_way;
  assign lru_valid_o = str_valid;

endmodule