class yapp_agent_config extends uvm_object;
  `uvm_object_utils(yapp_agent_config)
  virtual yapp_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  function new(string name="yapp_agent_config"); super.new(name); endfunction
endclass
class channel_agent_config extends uvm_object;
  `uvm_object_utils(channel_agent_config)
  virtual channel_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  int unsigned channel_id;
  function new(string name="channel_agent_config"); super.new(name); endfunction
endclass
class hbus_agent_config extends uvm_object;
  `uvm_object_utils(hbus_agent_config)
  virtual hbus_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  function new(string name="hbus_agent_config"); super.new(name); endfunction
endclass
class router_env_config extends uvm_object;
  `uvm_object_utils(router_env_config)
  yapp_agent_config yapp;
  channel_agent_config channels[3];
  hbus_agent_config hbus;
  virtual clock_reset_if control_vif;
  bit coverage_enable = 1;
  bit inject_scoreboard_fault = 0;
  int unsigned timeout_cycles = 100000;
  function new(string name="router_env_config");
    super.new(name);
    yapp = yapp_agent_config::type_id::create("yapp_cfg");
    hbus = hbus_agent_config::type_id::create("hbus_cfg");
    foreach (channels[i]) begin
      channels[i] = channel_agent_config::type_id::create($sformatf("channel%0d_cfg", i));
      channels[i].channel_id = i;
    end
  endfunction
endclass
