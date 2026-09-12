// Client-independent ownership boundary between SDRAM initialization and the
// normal atomic-operation runtime.
module sdram_initialized_runtime
    #(parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
      parameter integer CAS_LATENCY = 3, POWERUP_US = 200,
                        INIT_REFRESH_COUNT = 8,
      parameter integer DQ_TURNAROUND_CYCLES = 1, READ_CAPTURE_CYCLES = 4,
      parameter integer MAX_REFRESH_SERVICE_CYCLES = 64,
      parameter longint unsigned REFRESH_PHASE_CYCLES = 0)
    (input logic clk, reset,
     output logic init_done,
     input logic op_valid,
     output logic op_ready,
     input logic op_write, op_chip,
     input logic [1 : 0] op_bank,
     input logic [12 : 0] op_row,
     input logic [9 : 0] op_column,
     input logic [127 : 0] op_write_data,
     input logic [15 : 0] op_write_byte_enable,
     output logic [127 : 0] op_read_data,
     output logic op_read_data_valid, completion_valid,
     input logic completion_ready,
     output logic [12 : 0] sdram_a,
     output logic [1 : 0] sdram_ba,
     output logic sdram_cke, sdram_ncs, sdram_nras, sdram_ncas, sdram_nwe,
                  sdram_dqml, sdram_dqmh,
     input logic [15 : 0] sdram_dq_in,
     output logic [15 : 0] sdram_dq_out,
     output logic sdram_dq_oe,
     output logic late_refresh0, late_refresh1, refresh_pending,
                  timing_violation,
     output logic turnaround_blocked, row_hit, phy_busy);
  localparam logic [2 : 0] INIT_PRE = 3'd1, INIT_REF = 3'd2, INIT_MRS = 3'd3;
  logic init_cke, init_dqm_hold, init_command_valid, init_command_chip;
  logic [2 : 0] init_command;
  logic [12 : 0] init_command_address;
  logic unused_init_refresh0, unused_init_refresh1, unused_init_late0,
        unused_init_late1;
  logic runtime_reset, runtime_op_ready;
  logic [12 : 0] runtime_a;
  logic [1 : 0] runtime_ba;
  logic runtime_cke, runtime_ncs, runtime_nras, runtime_ncas, runtime_nwe;
  logic runtime_dqml, runtime_dqmh;
  logic [15 : 0] runtime_dq_out;
  logic runtime_dq_oe;

  // Resetting the runtime until init_done defines cycle zero for its refresh
  // age counters and guarantees that it has no stale bank state at handoff.
  assign runtime_reset = reset || !init_done;
  assign op_ready = init_done && runtime_op_ready;

  // This instance stops permanently in its RUN state. Runtime refresh is
  // deliberately owned by sdram_runtime_core below, not by both sequencers.
  sdram_init_refresh #(.SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
                       .CAS_LATENCY(CAS_LATENCY),
                       .POWERUP_US(POWERUP_US),
                       .REFRESH_COUNT(INIT_REFRESH_COUNT),
                       .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES),
                       .INIT_ONLY(1'b1))
      initialization(.clk,
                     .reset,
                     .chip0_all_banks_idle(1'b1),
                     .chip1_all_banks_idle(1'b1),
                     .command_accept(init_command_valid),
                     .init_done,
                     .cke(init_cke),
                     .dqm_hold(init_dqm_hold),
                     .command_valid(init_command_valid),
                     .command_chip(init_command_chip),
                     .command(init_command),
                     .command_address(init_command_address),
                     .refresh0_block(unused_init_refresh0),
                     .refresh1_block(unused_init_refresh1),
                     .late_refresh0(unused_init_late0),
                     .late_refresh1(unused_init_late1));
  sdram_runtime_core #(.SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
                       .DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES),
                       .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
                       .MAX_REFRESH_SERVICE_CYCLES(MAX_REFRESH_SERVICE_CYCLES),
                       .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES))
      runtime(.clk,
              .reset(runtime_reset),
              .runtime_enable(init_done),
              .op_valid(op_valid && init_done),
              .op_ready(runtime_op_ready),
              .op_write,
              .op_chip,
              .op_bank,
              .op_row,
              .op_column,
              .op_write_data,
              .op_write_byte_enable,
              .op_read_data,
              .op_read_data_valid,
              .completion_valid,
              .completion_ready,
              .sdram_a(runtime_a),
              .sdram_ba(runtime_ba),
              .sdram_cke(runtime_cke),
              .sdram_ncs(runtime_ncs),
              .sdram_nras(runtime_nras),
              .sdram_ncas(runtime_ncas),
              .sdram_nwe(runtime_nwe),
              .sdram_dqml(runtime_dqml),
              .sdram_dqmh(runtime_dqmh),
              .sdram_dq_in,
              .sdram_dq_out(runtime_dq_out),
              .sdram_dq_oe(runtime_dq_oe),
              .late_refresh0,
              .late_refresh1,
              .refresh_pending,
              .timing_violation,
              .turnaround_blocked,
              .row_hit,
              .phy_busy);
  // Exactly one producer owns the pins: initialization before init_done and
  // the runtime core afterwards. The mux is the future board-PHY boundary.
  always_comb begin
    sdram_a = runtime_a;
    sdram_ba = runtime_ba;
    sdram_cke = runtime_cke;
    sdram_ncs = runtime_ncs;
    sdram_nras = runtime_nras;
    sdram_ncas = runtime_ncas;
    sdram_nwe = runtime_nwe;
    sdram_dqml = runtime_dqml;
    sdram_dqmh = runtime_dqmh;
    sdram_dq_out = runtime_dq_out;
    sdram_dq_oe = runtime_dq_oe;
    if (!init_done) begin
      sdram_a = init_command_address;
      sdram_ba = '0;
      sdram_cke = init_cke;
      sdram_ncs = init_command_chip;
      sdram_nras = 1;
      sdram_ncas = 1;
      sdram_nwe = 1;
      sdram_dqml = init_dqm_hold;
      sdram_dqmh = init_dqm_hold;
      sdram_dq_out = '0;
      sdram_dq_oe = 0;
      if (init_command_valid)
        case (init_command)
          INIT_PRE: begin
            sdram_nras = 0;
            sdram_nwe = 0;
          end
          INIT_REF: begin
            sdram_nras = 0;
            sdram_ncas = 0;
          end
          INIT_MRS: begin
            sdram_nras = 0;
            sdram_ncas = 0;
            sdram_nwe = 0;
          end
          default:
            ;
        endcase
    end
  end
`ifdef FORMAL
  always_ff @(posedge clk)
    if (!reset && !init_done) begin
      assert (!op_ready);
      assert (!sdram_dq_oe);
    end
`endif
endmodule
