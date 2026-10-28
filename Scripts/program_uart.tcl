# Programs volatile FPGA configuration only; does not modify SPI flash.
# Run after build_uart.tcl: vivado -mode batch -source Scripts/program_uart.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set bitstream [file join $root Build uart_tx uart_tx.bit]
if {![file exists $bitstream]} { error "Build uart_tx.bit first" }

open_hw_manager
connect_hw_server -url localhost:3121
set targets [get_hw_targets -quiet *Digilent*]
if {[llength $targets] != 1} {
    error "Expected exactly one Digilent target, found: $targets"
}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices -quiet xc7a35t_*]
if {[llength $devices] != 1} { error "Expected one Basys 3 xc7a35t, found: $devices" }
set device [lindex $devices 0]
current_hw_device $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
refresh_hw_device $device
puts "PASS: programmed $device with $bitstream"
close_hw_target
close_hw_manager
