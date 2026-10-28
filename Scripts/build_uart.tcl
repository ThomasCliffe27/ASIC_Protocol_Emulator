# Run with: vivado -mode batch -source Scripts/build_uart.tcl
# A separate non-project build leaves any open GUI project/runs untouched.
set root [file normalize [file join [file dirname [info script]] ..]]
set output [file join $root Build uart_tx]
file mkdir $output
puts [exec python [file join $root Assembler assembler.py] \
    [file join $root Programs uart_tx.asm] [file join $root Programs uart_tx.hex]]

# PROGRAM_WORDS in top.sv describes this program's initialized address range.
set handle [open [file join $root Programs uart_tx.hex] r]
set word_count [llength [split [string trim [read $handle]] "\n"]]
close $handle
set handle [open [file join $root Sources top.sv] r]
set top_source [read $handle]
close $handle
if {![regexp {parameter int PROGRAM_WORDS\s*=\s*([0-9]+)} $top_source match configured_words]} {
    error "Cannot find the PROGRAM_WORDS default in top.sv"
}
if {$word_count != $configured_words} {
    error "Update PROGRAM_WORDS in top.sv: image contains $word_count words, configured for $configured_words"
}
file copy -force [file join $root Programs uart_tx.hex] [file join $output uart_tx.hex]
cd $output

read_verilog -sv [list [file join $root Sources cpu.sv] \
    [file join $root Sources gpio.sv] [file join $root Sources memory.sv] \
    [file join $root Sources top.sv]]
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
