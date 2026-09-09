module tb_top;
  timeunit 1ns; timeprecision 1ps;
  import uvm_pkg::*;
  import router_tb_pkg::*;
  hw_top hardware();
  initial begin
    router_env_config cfg;
    string selected_test;
    cfg=router_env_config::type_id::create("cfg");
    cfg.control_vif=hardware.control;
    cfg.yapp.vif=hardware.yapp;
    cfg.hbus.vif=hardware.hbus;
    cfg.channels[0].vif=hardware.ch0;
    cfg.channels[1].vif=hardware.ch1;
    cfg.channels[2].vif=hardware.ch2;
    if($test$plusargs("NO_COVERAGE")) cfg.coverage_enable=0;
    uvm_config_db#(router_env_config)::set(null,"uvm_test_top","cfg",cfg);
    if(!$value$plusargs("UVM_TESTNAME=%s",selected_test)) selected_test="router_smoke_test";
    run_test(selected_test);
  end
  initial begin
    if($test$plusargs("DUMP_VCD")) begin
      $dumpfile("router.vcd"); $dumpvars(0,hardware);
    end
  end
endmodule
