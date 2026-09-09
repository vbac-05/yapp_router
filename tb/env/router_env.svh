class router_virtual_sequencer extends uvm_sequencer #(uvm_sequence_item);
  `uvm_component_utils(router_virtual_sequencer)
  yapp_sequencer yapp_seqr;
  hbus_sequencer hbus_seqr;
  channel_sequencer channel_seqr[3];
  reset_sequencer reset_seqr;
  router_reg_block regs;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass

// A module UVC owns end-to-end verification and exposes top-level TLM exports.
class router_module_env extends uvm_env;
  `uvm_component_utils(router_module_env)
  router_reference reference_model;
  router_scoreboard scoreboard;
  router_coverage coverage;
  router_output_coverage output_coverage;
  router_error_checker error_checker;
  uvm_analysis_export #(yapp_packet) input_export, channel_export[3];
  uvm_analysis_export #(hbus_item) hbus_export;
  uvm_analysis_export #(reset_item) reset_export;
  router_env_config cfg;
  function new(string name, uvm_component parent);
    super.new(name,parent);
    input_export=new("input_export",this); hbus_export=new("hbus_export",this);
    reset_export=new("reset_export",this);
    foreach(channel_export[i]) channel_export[i]=new($sformatf("channel%0d_export",i),this);
  endfunction
  function void build_phase(uvm_phase phase);
    if(!uvm_config_db#(router_env_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","Router module needs cfg")
    reference_model=router_reference::type_id::create("reference_model",this);
    scoreboard=router_scoreboard::type_id::create("scoreboard",this);
    scoreboard.inject_fault=cfg.inject_scoreboard_fault;
    error_checker=router_error_checker::type_id::create("error_checker",this);
    error_checker.vif=cfg.yapp.vif;
    if(cfg.coverage_enable) begin
      coverage=router_coverage::type_id::create("coverage",this);
      output_coverage=router_output_coverage::type_id::create("output_coverage",this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    input_export.connect(reference_model.input_imp);
    hbus_export.connect(reference_model.hbus_imp);
    reference_model.expected_ap.connect(scoreboard.expected_imp);
    channel_export[0].connect(scoreboard.ch0_imp);
    channel_export[1].connect(scoreboard.ch1_imp);
    channel_export[2].connect(scoreboard.ch2_imp);
    reset_export.connect(reference_model.reset_imp);
    reset_export.connect(scoreboard.reset_imp);
    reset_export.connect(error_checker.reset_imp);
    reference_model.route_ap.connect(error_checker.route_imp);
    if(cfg.coverage_enable) begin
      reference_model.route_ap.connect(coverage.analysis_export);
      scoreboard.matched_ap.connect(output_coverage.analysis_export);
    end
  endfunction
endclass

class router_env extends uvm_env;
  `uvm_component_utils(router_env)
  router_env_config cfg;
  yapp_agent yapp;
  channel_agent channels[3];
  hbus_agent hbus;
  clock_reset_agent control;
  router_module_env router;
  router_virtual_sequencer virtual_sequencer;
  router_reg_block regs;
  hbus_reg_adapter adapter;
  uvm_reg_predictor #(hbus_item) predictor;
  hbus_coverage bus_coverage;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(router_env_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","Router environment needs configuration")
    uvm_config_db#(yapp_agent_config)::set(this,"yapp","cfg",cfg.yapp);
    uvm_config_db#(hbus_agent_config)::set(this,"hbus","cfg",cfg.hbus);
    uvm_config_db#(virtual clock_reset_if)::set(this,"control.*","vif",cfg.control_vif);
    uvm_config_db#(router_env_config)::set(this,"router","cfg",cfg);
    yapp=yapp_agent::type_id::create("yapp",this);
    hbus=hbus_agent::type_id::create("hbus",this);
    foreach(channels[i]) begin
      string instance_name=$sformatf("channel%0d",i);
      uvm_config_db#(channel_agent_config)::set(this,instance_name,"cfg",cfg.channels[i]);
      channels[i]=channel_agent::type_id::create(instance_name,this);
    end
    control=clock_reset_agent::type_id::create("control",this);
    router=router_module_env::type_id::create("router",this);
    virtual_sequencer=router_virtual_sequencer::type_id::create("virtual_sequencer",this);
    regs=router_reg_block::type_id::create("regs"); regs.build();
    regs.set_hdl_path_root("tb_top.hardware.dut");
    adapter=hbus_reg_adapter::type_id::create("adapter");
    predictor=uvm_reg_predictor#(hbus_item)::type_id::create("predictor",this);
    if(cfg.coverage_enable) bus_coverage=hbus_coverage::type_id::create("bus_coverage",this);
  endfunction
  function void connect_phase(uvm_phase phase);
    yapp.monitor.packet_ap.connect(router.input_export);
    hbus.monitor.transaction_ap.connect(router.hbus_export);
    foreach(channels[i]) channels[i].monitor.packet_ap.connect(router.channel_export[i]);
    control.monitor.reset_ap.connect(router.reset_export);
    router.reference_model.regs=regs;
    regs.default_map.set_sequencer(hbus.sequencer,adapter);
    regs.default_map.set_auto_predict(0); // One explicit bus observer, no double prediction.
    regs.default_map.set_check_on_read(1);
    predictor.map=regs.default_map; predictor.adapter=adapter;
    hbus.monitor.transaction_ap.connect(predictor.bus_in);
    if(cfg.coverage_enable) hbus.monitor.transaction_ap.connect(bus_coverage.analysis_export);
    virtual_sequencer.yapp_seqr=yapp.sequencer;
    virtual_sequencer.hbus_seqr=hbus.sequencer;
    virtual_sequencer.reset_seqr=control.sequencer;
    foreach(channels[i]) virtual_sequencer.channel_seqr[i]=channels[i].sequencer;
    virtual_sequencer.regs=regs;
  endfunction
endclass
