module events_to_apb (
  input   logic         clk,
  input   logic         reset,

  input   logic         event_a_i,
  input   logic         event_b_i,
  input   logic         event_c_i,

  output  logic         apb_psel_o,
  output  logic         apb_penable_o,
  output  logic [31:0]  apb_paddr_o,
  output  logic         apb_pwrite_o,
  output  logic [31:0]  apb_pwdata_o,
  input   logic         apb_pready_i

);

  typedef enum logic  [1:0] {A, B, C} event_sel_t;
  typedef enum logic  [1:0] {ST_IDLE, ST_SETUP, ST_ACCESS} apb_state_t;
  typedef enum logic [31:0] {
    EVENT_A_ADDR = 32'hABBA_0000,
    EVENT_B_ADDR = 32'hBAFF_0000,
    EVENT_C_ADDR = 32'hCAFE_0000} apb_addr_t;

  apb_state_t  state_apb, next_apb;
  event_sel_t  event_sel, event_sel_r;
  logic [31:0] event_a_cnt, event_b_cnt, event_c_cnt;
  logic        done, event_arrived;

  assign event_arrived = |{event_a_cnt, event_b_cnt, event_c_cnt, 
                           event_a_i,   event_b_i,   event_c_i};
  assign done          = apb_penable_o && apb_pready_i;

  always_ff @(posedge clk, posedge reset) begin : event_counter
    if (reset) begin
      event_a_cnt  <= 0;
      event_b_cnt  <= 0;
      event_c_cnt  <= 0;
    end else begin
      event_a_cnt  <= event_sel == A && done ? 
                      event_a_cnt - apb_pwdata_o + {31'h0, event_a_i} :
                      event_a_cnt + {31'h0, event_a_i};
      event_b_cnt  <= event_sel == B && done ? 
                      event_b_cnt - apb_pwdata_o + {31'h0, event_b_i} :
                      event_b_cnt + {31'h0, event_b_i};
      event_c_cnt  <= event_sel == C && done ? 
                      event_c_cnt - apb_pwdata_o + {31'h0, event_c_i} :
                      event_c_cnt + {31'h0, event_c_i};
    end
  end

  always_comb begin : apb_fsm
    event_sel = event_sel_r;
    unique case (state_apb)
      ST_IDLE: begin
        if (event_arrived) begin
          next_apb  = ST_SETUP;
          if (|event_a_cnt || event_a_i)
            event_sel = A;
          else if (|event_b_cnt || event_b_i)
            event_sel = B;
          else
            event_sel = C;
        end else begin
          next_apb  = ST_IDLE;
        end
      end
      ST_SETUP: begin
        next_apb = ST_ACCESS;
      end
      ST_ACCESS: begin
        if (apb_pready_i)
          next_apb = ST_IDLE;
        else
          next_apb = ST_ACCESS;
      end
      default: next_apb = ST_IDLE;
    endcase
  end

  always_ff @(posedge clk, posedge reset)
    state_apb <= reset ? ST_IDLE : next_apb;

  always_ff @(posedge clk, posedge reset)
    event_sel_r <= reset ? A : event_sel;

  always_comb begin
    unique case (event_sel)
      A:       apb_paddr_o = EVENT_A_ADDR;
      B:       apb_paddr_o = EVENT_B_ADDR;
      C:       apb_paddr_o = EVENT_C_ADDR;
      default: apb_paddr_o = 0;
    endcase
  end

  always_ff @(posedge clk, posedge reset) begin
    if (reset)
      apb_pwdata_o <= 0;
    else if (state_apb == ST_IDLE)
      unique case (event_sel)
        A:       apb_pwdata_o <= event_a_cnt + {31'h0, event_a_i};
        B:       apb_pwdata_o <= event_b_cnt + {31'h0, event_b_i};
        C:       apb_pwdata_o <= event_c_cnt + {31'h0, event_c_i};
        default: apb_pwdata_o <= 0;
      endcase
  end
  
  assign apb_psel_o    = state_apb != ST_IDLE;
  assign apb_penable_o = state_apb == ST_ACCESS;
  assign apb_pwrite_o  = 1;  

endmodule
