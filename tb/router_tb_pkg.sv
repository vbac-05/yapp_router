package router_tb_pkg;
  timeunit 1ns; timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  // Read this list as a dependency graph: types -> agents -> model -> env -> tests.
  `include "router_types.svh"
  `include "router_config.svh"
  `include "yapp_agent.svh"
  `include "channel_agent.svh"
  `include "hbus_agent.svh"
  `include "clock_reset_agent.svh"
  `include "router_reg_model.svh"
  `include "router_reference.svh"
  `include "router_scoreboard.svh"
  `include "router_coverage.svh"
  `include "router_error_checker.svh"
  `include "router_env.svh"
  `include "router_sequences.svh"
  `include "router_tests.svh"
endpackage
