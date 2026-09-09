class channel_sequencer extends uvm_sequencer #(channel_response);
  `uvm_component_utils(channel_sequencer)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass

class channel_driver extends uvm_driver #(channel_response);
  `uvm_component_utils(channel_driver)
  channel_agent_config cfg;
  virtual channel_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(channel_agent_config)::get(this,"","cfg",cfg) || cfg.vif==null)
      `uvm_fatal("NO_CFG","Channel driver needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task drive_cycles(int unsigned count, bit stalled);
    repeat(count) begin
      @(vif.drv_cb);
      vif.drv_cb.suspend <= vif.drv_cb.reset ? 1'b1 : stalled;
    end
  endtask
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive_cycles(req.stall_cycles,1);
      drive_cycles(req.ready_cycles,0);
      seq_item_port.item_done();
    end
  endtask
endclass

class channel_monitor extends uvm_monitor;
  `uvm_component_utils(channel_monitor)
  uvm_analysis_port #(yapp_packet) packet_ap;
  channel_agent_config cfg;
  virtual channel_if vif;
  yapp_packet packet;
  int index;
  int unsigned collected=0;
  function new(string name, uvm_component parent);
    super.new(name,parent); packet_ap=new("packet_ap",this);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(channel_agent_config)::get(this,"","cfg",cfg) || cfg.vif==null)
      `uvm_fatal("NO_CFG","Channel monitor needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if(vif.mon_cb.reset) packet=null;
      else if(vif.mon_cb.data_vld && !vif.mon_cb.suspend) begin
        if($isunknown(vif.mon_cb.data)) `uvm_error("CHANNEL_X","Unknown output byte")
        if(packet==null) begin
          packet=yapp_packet::type_id::create("observed_packet");
          {packet.length,packet.addr}=vif.mon_cb.data;
          packet.payload=new[packet.length]; index=0;
          if(packet.addr != cfg.channel_id)
            `uvm_error("MISROUTE",$sformatf("Channel %0d received addr %0d",cfg.channel_id,packet.addr))
        end else if(index < packet.length) packet.payload[index++]=vif.mon_cb.data;
        else begin
          packet.parity=vif.mon_cb.data;
          packet.parity_kind=packet.parity===packet.expected_parity() ? PARITY_GOOD : PARITY_BAD;
          packet.observed_at=$time;
          packet_ap.write(packet);
          collected++; packet=null;
        end
      end
    end
  endtask
  function void check_phase(uvm_phase phase);
    if(packet!=null) `uvm_error("CHANNEL_PARTIAL","Simulation ended with incomplete output packet")
  endfunction
endclass

class channel_agent extends uvm_agent;
  `uvm_component_utils(channel_agent)
  channel_agent_config cfg;
  channel_driver driver;
  channel_sequencer sequencer;
  channel_monitor monitor;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(channel_agent_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","Channel agent needs configuration")
    is_active=cfg.is_active;
    uvm_config_db#(channel_agent_config)::set(this,"*","cfg",cfg);
    monitor=channel_monitor::type_id::create("monitor",this);
    if(cfg.is_active==UVM_ACTIVE) begin
      driver=channel_driver::type_id::create("driver",this);
      sequencer=channel_sequencer::type_id::create("sequencer",this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    if(cfg.is_active==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
