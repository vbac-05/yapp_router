interface hbus_if(input logic clock, reset);
  timeunit 1ns; timeprecision 1ps;
  logic [15:0] haddr = '0;
  logic [7:0] write_data = '0;
  logic hen = 0, hwr_rd = 0;
  wire [7:0] hdata;
  assign hdata = hen && hwr_rd && !reset ? write_data : 8'hzz;
  clocking drv_cb @(negedge clock);
    default input #1step output #0;
    output haddr, write_data, hen, hwr_rd;
    input reset, hdata;
  endclocking
  clocking mon_cb @(posedge clock);
    default input #1step;
    input reset, haddr, hdata, hen, hwr_rd;
  endclocking
  a_read_two_cycles: assert property (@(posedge clock) disable iff (reset)
    $rose(hen) && !hwr_rd |=> hen && !hwr_rd && $stable(haddr))
    else $error("SVA_FAILURE HBUS read must hold address for two cycles");
  a_write_data_known: assert property (@(posedge clock) disable iff (reset)
    hen && hwr_rd |-> !$isunknown({haddr, hdata}))
    else $error("SVA_FAILURE HBUS unknown write data/address");
endinterface
