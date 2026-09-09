interface yapp_if(input logic clock, reset);
  timeunit 1ns; timeprecision 1ps;
  logic [7:0] in_data = '0;
  logic in_data_vld = 0;
  wire in_suspend, error;
  // Drivers change pins on falling edges. Monitors observe values accepted
  // by the RTL on rising edges, before the RTL's nonblocking updates.
  clocking drv_cb @(negedge clock);
    default input #1step output #0;
    output in_data, in_data_vld;
    input reset, in_suspend;
  endclocking
  clocking mon_cb @(posedge clock);
    default input #1step;
    input reset, in_data, in_data_vld, in_suspend, error;
  endclocking
  a_stable_when_stalled: assert property (@(posedge clock) disable iff (reset)
    in_suspend |=> $stable({in_data, in_data_vld}))
    else $error("SVA_FAILURE YAPP changed a stalled byte");
  a_input_known: assert property (@(posedge clock) disable iff (reset)
    in_data_vld |-> !$isunknown({in_data, in_suspend}))
    else $error("SVA_FAILURE YAPP unknown valid byte");
endinterface
