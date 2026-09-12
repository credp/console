module sdram_refresh_deadline #(
    parameter longint unsigned SDRAM_FREQ_HZ = 130_000_000,
    // Contract with the downstream scheduler/core: no more than this many
    // clocks from refresh_valid first asserting to refresh completion.
    parameter integer MAX_SERVICE_CYCLES = 64,
    parameter longint unsigned REFRESH_PHASE_CYCLES = 0
) (
    input  logic clk,
    input  logic reset,
    // Assert after SDRAM initialization and keep asserted during normal use.
    input  logic enable,

    output logic refresh_valid,
    input  logic refresh_ready,
    output logic refresh_chip,
    input  logic refresh_completion_valid,
    output logic refresh_completion_ready,

    output logic late_refresh0,
    output logic late_refresh1,
    output logic refresh_pending
);
    localparam longint unsigned TREFI_CYCLES =
        (SDRAM_FREQ_HZ * 64'd78) / 64'd10_000_000;
    localparam longint unsigned PHASE_CYCLES =
        (REFRESH_PHASE_CYCLES == 0) ? TREFI_CYCLES/2 : REFRESH_PHASE_CYCLES;
    // Two extra clocks cover detecting the threshold and registering the
    // persistent request before the downstream service-bound clock starts.
    localparam longint unsigned REQUEST_MARGIN = MAX_SERVICE_CYCLES + 2;
    localparam longint unsigned REQUEST_AGE =
        (TREFI_CYCLES > REQUEST_MARGIN) ? TREFI_CYCLES-REQUEST_MARGIN : 0;
    localparam integer AGE_BITS = (TREFI_CYCLES > 1) ?
                                  $clog2(TREFI_CYCLES + 1) : 1;
    localparam logic [AGE_BITS-1:0] AGE_LIMIT = TREFI_CYCLES[AGE_BITS-1:0];
    localparam logic [AGE_BITS-1:0] PHASE_INITIAL = PHASE_CYCLES[AGE_BITS-1:0];

    logic [AGE_BITS-1:0] age0,age1;
    logic request_active,request_chip_q,inflight,inflight_chip;
    logic was_enabled;

    assign refresh_valid = request_active;
    assign refresh_chip = request_chip_q;
    assign refresh_completion_ready = 1'b1;
    assign refresh_pending = request_active || inflight;

    always_ff @(posedge clk) begin
        if (reset) begin
            age0 <= '0;
            age1 <= PHASE_INITIAL;
            request_active <= 1'b0;
            request_chip_q <= 1'b0;
            inflight <= 1'b0;
            inflight_chip <= 1'b0;
            late_refresh0 <= 1'b0;
            late_refresh1 <= 1'b0;
            was_enabled <= 1'b0;
        end else begin
            was_enabled <= enable;
            if (!enable) begin
                // Re-arm the initial half-interval staggering. Initialization
                // time is not charged to the runtime refresh deadline.
                age0 <= '0;
                age1 <= PHASE_INITIAL;
                request_active <= 1'b0;
                inflight <= 1'b0;
            end else begin
                if (!was_enabled) begin
                    age0 <= '0;
                    age1 <= PHASE_INITIAL;
                end else begin
                    if (age0 != AGE_LIMIT) age0 <= age0 + 1'b1;
                    if (age1 != AGE_LIMIT) age1 <= age1 + 1'b1;
                end

                if (age0 >= AGE_LIMIT &&
                    !(refresh_completion_valid && inflight && !inflight_chip))
                    late_refresh0 <= 1'b1;
                if (age1 >= AGE_LIMIT &&
                    !(refresh_completion_valid && inflight && inflight_chip))
                    late_refresh1 <= 1'b1;

                if (!request_active && !inflight) begin
                    // Oldest-first matters only if reset/exception handling
                    // ever allows both thresholds to be crossed together.
                    if (age0 >= REQUEST_AGE && age0 >= age1) begin
                        request_active <= 1'b1;
                        request_chip_q <= 1'b0;
                    end else if (age1 >= REQUEST_AGE) begin
                        request_active <= 1'b1;
                        request_chip_q <= 1'b1;
                    end
                end

                if (refresh_valid && refresh_ready) begin
                    request_active <= 1'b0;
                    inflight <= 1'b1;
                    inflight_chip <= refresh_chip;
                end

                // Completion means the scheduler has actually issued REF, not
                // merely accepted our request. Only that event resets age.
                if (refresh_completion_valid && inflight) begin
                    inflight <= 1'b0;
                    if (inflight_chip) age1 <= '0;
                    else age0 <= '0;
                end
            end
        end
    end

`ifdef FORMAL
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
        if (!reset) begin
            assert(age0 <= AGE_LIMIT);
            assert(age1 <= AGE_LIMIT);
            assert(!(request_active && inflight));
            if (f_past_valid && !$past(reset) &&
                $past(refresh_valid && !refresh_ready)) begin
                assert(refresh_valid);
                assert(refresh_chip == $past(refresh_chip));
            end
        end
    end
`endif

    initial begin
        if (TREFI_CYCLES < 4) $error("SDRAM clock too slow for refresh model");
        if (REQUEST_MARGIN >= TREFI_CYCLES)
            $error("refresh service bound leaves no usable interval");
        if (PHASE_CYCLES == 0 || PHASE_CYCLES >= TREFI_CYCLES)
            $error("refresh phase must be inside tREFI");
        if (PHASE_CYCLES <= REQUEST_MARGIN ||
            TREFI_CYCLES-PHASE_CYCLES <= REQUEST_MARGIN)
            $error("chip refresh phase is too narrow for service bound");
    end
endmodule
