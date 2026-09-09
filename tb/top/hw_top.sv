module hw_top;
  timeunit 1ns; timeprecision 1ps;
  clock_reset_if control();
  yapp_if yapp(control.clock,control.reset);
  channel_if ch0(control.clock,control.reset);
  channel_if ch1(control.clock,control.reset);
  channel_if ch2(control.clock,control.reset);
  hbus_if hbus(control.clock,control.reset);
  yapp_router dut(
    .clock(control.clock), .reset(control.reset),
    .in_data(yapp.in_data), .in_data_vld(yapp.in_data_vld),
    .in_suspend(yapp.in_suspend), .error(yapp.error),
    .data_0(ch0.data), .data_vld_0(ch0.data_vld), .suspend_0(ch0.suspend),
    .data_1(ch1.data), .data_vld_1(ch1.data_vld), .suspend_1(ch1.suspend),
    .data_2(ch2.data), .data_vld_2(ch2.data_vld), .suspend_2(ch2.suspend),
    .haddr(hbus.haddr), .hdata(hbus.hdata), .hen(hbus.hen), .hwr_rd(hbus.hwr_rd)
  );
endmodule
