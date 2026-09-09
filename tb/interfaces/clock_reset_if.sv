interface clock_reset_if;
  timeunit 1ns; timeprecision 1ps;
  logic clock = 0;
  logic reset = 0;
  parameter time PERIOD = 10ns;
  always #(PERIOD/2) clock = ~clock;
  clocking drv_cb @(negedge clock);
    default input #1step output #0;
    output reset;
  endclocking
endinterface
