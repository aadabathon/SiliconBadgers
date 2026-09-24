# Headless layout screenshot of the saved block (needs an X display, e.g. Xvfb).
source [file join [file dirname [file normalize [info script]]] config.tcl]
open_lib $TOP.dlib
open_block $TOP
gui_start
set w [gui_get_current_window -types Layout -mru]
gui_zoom -window $w -full
gui_write_window_image -window $w -file ${TOP}_layout.png -format png
gui_stop
puts "=== SCREENSHOT DONE: ${TOP}_layout.png ==="
exit
