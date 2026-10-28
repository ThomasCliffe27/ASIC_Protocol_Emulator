# Run with: vivado -mode batch -source Scripts/build_uart.tcl
# A separate non-project build leaves any open GUI project/runs untouched.
set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root Build uart_tx]
file mkdir $output
cd $output
read_verilog -sv [glob [file join $root Sources *.sv]]
read_xdc [file join $root Sources Basys3_Master.xdc]
synth_design -top top -part xc7a35tcpg236-1
opt_design
place_design
phys_opt_design
route_design

report_utilization -file utilization.rpt
report_timing_summary -check_timing_verbose -report_unconstrained -file timing_summary.rpt
report_drc -file drc.rpt
write_checkpoint -force uart_tx_routed.dcp

foreach delay_type {max min} {
    set paths [get_timing_paths -delay_type $delay_type -max_paths 1]
    if {[llength $paths] == 0} { error "No $delay_type timing paths found" }
    set slack [get_property SLACK [lindex $paths 0]]
    if {$slack < 0} { error "Timing failed: $delay_type slack is $slack ns" }
    puts "PASS: $delay_type timing slack $slack ns"
}
write_bitstream -force uart_tx.bit
puts "PASS: bitstream ready at [file join $output uart_tx.bit]"
