interface channel_if(input logic clock, reset);
  timeunit 1ns; timeprecision 1ps;
  wire [7:0] data;
  wire data_vld;
  logic suspend = 1;
  clocking drv_cb @(negedge clock);
    default input #1step output #0;
    output suspend;
    input reset, data_vld;
  endclocking
  clocking mon_cb @(posedge clock);
    default input #1step;
    input reset, data, data_vld, suspend;
  endclocking
  a_output_stable: assert property (@(posedge clock) disable iff (reset)
    data_vld && suspend |=> data_vld && $stable(data))
    else $error("SVA_FAILURE output changed while stalled");
  a_output_known: assert property (@(posedge clock) disable iff (reset)
    data_vld |-> !$isunknown(data))
    else $error("SVA_FAILURE output byte is unknown");
endinterface
