// Smoke testbench for cpu16_core: same stimulus for RTL, gate and gate+SDF runs.
// Adam's SramSBC (1-cycle synchronous read) is preloaded with fixed-seed random
// NON-control-flow instructions (ALU/ADDI/ANDI/LEA/LD/ST/LDR/STR), so the PC walks
// linearly through memory and loads/stores really happen. Every cycle the bus
// (addr, wdata, we) is logged to +TRACE=<file>. Identical traces across the three
// runs = the implementation behaves like the RTL on this stimulus.
`timescale 1ns/1ps
module tb;
  parameter real PERIOD = 10.0;     // slow clock: gate+SDF run is a functional check, not STA
  parameter int  CYCLES = 2000;

  logic clk = 0, rst = 1;
  logic [15:0] mem_rdata, mem_addr, mem_wdata;
  logic        mem_we;

  cpu16_core dut (.*);
  SramSBC    u_mem (.clk(clk), .we(mem_we), .addr(mem_addr), .wdata(mem_wdata), .rdata(mem_rdata));

  always #(PERIOD/2) clk = ~clk;

  localparam logic [3:0] OPS [9] = '{4'h0, 4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'hA, 4'hB, 4'hC};
  int fd, errors = 0, seed = 32'h5EED;
  string trace;
  initial begin
    for (int i = 0; i < 65536; i++)
      u_mem.mem[i] = {OPS[$unsigned($random(seed)) % 9], 12'($random(seed))};
    if (!$value$plusargs("TRACE=%s", trace)) trace = "trace.txt";
    fd = $fopen(trace, "w");
`ifdef FSDB
    $fsdbDumpfile("smoke.fsdb");
    $fsdbDumpvars(0, tb);
`endif
    repeat (3) @(posedge clk);
    #(PERIOD/4) rst = 0;                       // release away from the edge
    // Negative test: a stuck-at-0 store-data bit must make the trace differ.
    if ($test$plusargs("INJECT_FAILURE")) force dut.mem_wdata[0] = 1'b0;
    for (int c = 0; c < CYCLES; c++) begin
      @(negedge clk);                           // sample mid-cycle, after all delays
      if ($isunknown({mem_addr, mem_we}) || (mem_we && $isunknown(mem_wdata))) begin
        errors++;
        if (errors < 5) $display("X on bus at cycle %0d: addr=%h we=%b wdata=%h", c, mem_addr, mem_we, mem_wdata);
      end
      $fdisplay(fd, "%0d %h %h %b", c, mem_addr, mem_we ? mem_wdata : 16'h0, mem_we);
    end
    $fclose(fd);
    if (errors == 0) $display("CPU16_SMOKE_PASS cycles=%0d", CYCLES);
    else             $display("CPU16_SMOKE_FAIL x_errors=%0d", errors);
    $finish;
  end
endmodule
