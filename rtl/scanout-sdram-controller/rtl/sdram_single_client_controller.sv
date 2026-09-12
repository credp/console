module sdram_single_client_controller
    #(parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
      parameter integer CAS_LATENCY = 3, POWERUP_US = 200,
                        INIT_REFRESH_COUNT = 8,
      parameter integer DQ_TURNAROUND_CYCLES = 1, READ_CAPTURE_CYCLES = 4,
      parameter integer MAX_REFRESH_SERVICE_CYCLES = 64,
      parameter longint unsigned REFRESH_PHASE_CYCLES = 0,
      parameter integer LEN_WIDTH = 16, TAG_WIDTH = 8, MAX_REQUEST_WORDS = 256,
                        MAPPING = 5)
    (input logic clk, reset,
     input logic req_valid,
     output logic req_ready,
     input logic req_write,
     input logic [26 : 0] req_byte_address,
     input logic [LEN_WIDTH - 1 : 0] req_words,
     input logic [TAG_WIDTH - 1 : 0] req_tag,
     input logic write_valid,
     output logic write_ready,
     input logic [15 : 0] write_data,
     input logic [1 : 0] write_byte_enable,
     output logic read_valid,
     input logic read_ready,
     output logic [15 : 0] read_data,
     output logic completion_valid,
     input logic completion_ready,
     output logic [TAG_WIDTH - 1 : 0] completion_tag,
     output logic [LEN_WIDTH - 1 : 0] completion_words,
     output logic completion_error,
     output logic init_done,
     output logic [12 : 0] sdram_a,
     output logic [1 : 0] sdram_ba,
     output logic sdram_cke, sdram_ncs, sdram_nras, sdram_ncas,
     output logic sdram_nwe, sdram_dqml, sdram_dqmh,
     input logic [15 : 0] sdram_dq_in,
     output logic [15 : 0] sdram_dq_out,
     output logic sdram_dq_oe,
     output logic late_refresh0, late_refresh1, refresh_pending,
                  timing_violation,
     output logic turnaround_blocked, row_hit, phy_busy);
  logic frontend_reset, adapter_req_ready;
  logic op_valid, op_ready, op_write, op_chip;
  logic [1 : 0] op_bank;
  logic [12 : 0] op_row;
  logic [9 : 0] op_column;
  logic [127 : 0] op_write_data, op_read_data;
  logic [15 : 0] op_write_byte_enable;
  logic op_read_data_valid;
  logic op_completion_valid, op_completion_ready;

  // The architecture-facing adapter starts from an empty state at the same
  // edge that the initialized runtime becomes available.  Requests presented
  // earlier remain unaccepted; the client may simply hold req_valid high.
  assign frontend_reset = reset || !init_done;
  assign req_ready = init_done && adapter_req_ready;

  // Architecture request stream -> indivisible BL8 operations.
  sdram_single_client_adapter #(.LEN_WIDTH(LEN_WIDTH),
                                .TAG_WIDTH(TAG_WIDTH),
                                .MAX_REQUEST_WORDS(MAX_REQUEST_WORDS),
                                .MAPPING(MAPPING))
      adapter(.clk,
              .reset(frontend_reset),
              .req_valid(req_valid && init_done),
              .req_ready(adapter_req_ready),
              .req_write,
              .req_byte_address,
              .req_words,
              .req_tag,
              .write_valid,
              .write_ready,
              .write_data,
              .write_byte_enable,
              .read_valid,
              .read_ready,
              .read_data,
              .completion_valid,
              .completion_ready,
              .completion_tag,
              .completion_words,
              .completion_error,
              .op_valid,
              .op_ready,
              .op_write,
              .op_chip,
              .op_bank,
              .op_row,
              .op_column,
              .op_write_data,
              .op_write_byte_enable,
              .op_read_data,
              .op_read_data_valid,
              .op_completion_valid,
              .op_completion_ready);
  // Initialization, refresh-aware runtime, and exclusive SDRAM pin ownership.
  sdram_initialized_runtime #(.SDRAM_FREQ_HZ(SDRAM_FREQ_HZ),
                              .CAS_LATENCY(CAS_LATENCY),
                              .POWERUP_US(POWERUP_US),
                              .INIT_REFRESH_COUNT(INIT_REFRESH_COUNT),
                              .DQ_TURNAROUND_CYCLES(DQ_TURNAROUND_CYCLES),
                              .READ_CAPTURE_CYCLES(READ_CAPTURE_CYCLES),
                              .MAX_REFRESH_SERVICE_CYCLES(
                                  MAX_REFRESH_SERVICE_CYCLES),
                              .REFRESH_PHASE_CYCLES(REFRESH_PHASE_CYCLES))
      memory_runtime(.clk,
                     .reset,
                     .init_done,
                     .op_valid,
                     .op_ready,
                     .op_write,
                     .op_chip,
                     .op_bank,
                     .op_row,
                     .op_column,
                     .op_write_data,
                     .op_write_byte_enable,
                     .op_read_data,
                     .op_read_data_valid,
                     .completion_valid(op_completion_valid),
                     .completion_ready(op_completion_ready),
                     .sdram_a,
                     .sdram_ba,
                     .sdram_cke,
                     .sdram_ncs,
                     .sdram_nras,
                     .sdram_ncas,
                     .sdram_nwe,
                     .sdram_dqml,
                     .sdram_dqmh,
                     .sdram_dq_in,
                     .sdram_dq_out,
                     .sdram_dq_oe,
                     .late_refresh0,
                     .late_refresh1,
                     .refresh_pending,
                     .timing_violation,
                     .turnaround_blocked,
                     .row_hit,
                     .phy_busy);
endmodule
