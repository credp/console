# Run after fitting: quartus_sta -t report_sdram_timing.tcl
# Report only; does not change assignments or compile the design.
package require ::quartus::project
package require ::quartus::sta
project_open -current_revision Template
create_timing_netlist
read_sdc
update_timing_netlist
set dq [get_ports {SDRAM_DQ[*]}]
set captured [get_registers {*phy_sdram_dq_in*}]
set buffered [get_registers {*sdram_engine|dq_handoff*}]
foreach collection [list $dq $captured $buffered [get_clocks sdram_clk_out]] {
    if {[get_collection_size $collection] == 0} {
        error "An SDRAM timing endpoint/clock was not found"
    }
}
foreach analysis {setup hold} {
    report_timing -$analysis -from $dq -to $captured -npaths 16 -detail full_path \
        -file output_files/sdram_input_${analysis}.rpt
    report_timing -$analysis -from $captured -to $buffered -npaths 16 -detail full_path \
        -file output_files/sdram_handoff_${analysis}.rpt
    report_timing -$analysis -to_clock [get_clocks sdram_clk_out] -npaths 16 -detail full_path \
        -file output_files/sdram_output_${analysis}.rpt
    report_timing -$analysis -from [get_registers {*sdram_engine* *sdram_test*}] \
        -to [get_registers {*sdram_engine* *sdram_test*}] -npaths 16 -detail full_path \
        -file output_files/sdram_internal_${analysis}.rpt
}
project_close
