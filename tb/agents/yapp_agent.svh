class yapp_sequencer extends uvm_sequencer #(yapp_packet);
  `uvm_component_utils(yapp_sequencer)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass

class yapp_driver extends uvm_driver #(yapp_packet);
  `uvm_component_utils(yapp_driver)
  yapp_agent_config cfg;
  virtual yapp_if vif;
  int unsigned sent=0, aborted_count=0;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(yapp_agent_config)::get(this,"","cfg",cfg) || cfg.vif == null)
      `uvm_fatal("NO_CFG","YAPP driver needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task send_byte(bit [7:0] data, bit valid);
    @(vif.drv_cb);
    vif.drv_cb.in_data <= data;
    vif.drv_cb.in_data_vld <= valid;
    do @(vif.mon_cb); while (vif.mon_cb.in_suspend);
  endtask
  task send_packet(yapp_packet packet);
    repeat(packet.gap_cycles) @(vif.drv_cb);
    send_byte({packet.length,packet.addr},1);
    foreach(packet.payload[i]) send_byte(packet.payload[i],1);
    send_byte(packet.parity,0);
  endtask
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      wait(!vif.reset);
      req.aborted=0;
      // Reset can interrupt a stalled byte. Always acknowledge the sequence item.
      fork : drive_or_reset
        send_packet(req);
        begin @(posedge vif.reset); req.aborted=1; end
      join_any
      disable drive_or_reset;
      @(vif.drv_cb);
      vif.drv_cb.in_data_vld <= 0;
      vif.drv_cb.in_data <= 0;
      if(req.aborted) aborted_count++; else sent++;
      seq_item_port.item_done();
    end
  endtask
  function void report_phase(uvm_phase phase);
    `uvm_info("TX_STATS",$sformatf("sent=%0d reset_aborted=%0d",sent,aborted_count),UVM_LOW)
  endfunction
endclass

class yapp_monitor extends uvm_monitor;
  `uvm_component_utils(yapp_monitor)
  uvm_analysis_port #(yapp_packet) packet_ap;
  yapp_agent_config cfg;
  virtual yapp_if vif;
  yapp_packet packet;
  int index;
  int unsigned collected=0, reset_aborted=0;
  function new(string name, uvm_component parent);
    super.new(name,parent); packet_ap=new("packet_ap",this);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(yapp_agent_config)::get(this,"","cfg",cfg) || cfg.vif == null)
      `uvm_fatal("NO_CFG","YAPP monitor needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      @(vif.mon_cb);
      if(vif.mon_cb.reset) begin
        if(packet!=null) reset_aborted++;
        packet=null;
      end else if(!vif.mon_cb.in_suspend) begin
        if(packet==null) begin
          if(vif.mon_cb.in_data_vld) begin
            packet=yapp_packet::type_id::create("observed_packet");
            {packet.length,packet.addr}=vif.mon_cb.in_data;
            packet.payload=new[packet.length];
            index=0;
          end
        end else if(index < packet.length) begin
          if(vif.mon_cb.in_data_vld !== 1'b1 || $isunknown(vif.mon_cb.in_data))
            `uvm_error("YAPP_PROTOCOL","Payload must be known and valid")
          packet.payload[index++]=vif.mon_cb.in_data;
        end else begin
          if(vif.mon_cb.in_data_vld !== 1'b0 || $isunknown(vif.mon_cb.in_data))
            `uvm_error("YAPP_PROTOCOL","Parity must be known with valid low")
          packet.parity=vif.mon_cb.in_data;
          packet.parity_kind=(packet.parity===packet.expected_parity()) ? PARITY_GOOD : PARITY_BAD;
          packet.observed_at=$time;
          packet_ap.write(packet);
          `uvm_info("YAPP_OBSERVED",packet.convert2string(),UVM_HIGH)
          collected++;
          packet=null; // Never reuse a published transaction handle.
        end
      end
    end
  endtask
  function void check_phase(uvm_phase phase);
    if(packet!=null) `uvm_error("YAPP_PARTIAL","Simulation ended with an incomplete input packet")
  endfunction
endclass

class yapp_agent extends uvm_agent;
  `uvm_component_utils(yapp_agent)
  yapp_agent_config cfg;
  yapp_driver driver;
  yapp_sequencer sequencer;
  yapp_monitor monitor;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(yapp_agent_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","YAPP agent needs configuration")
    is_active=cfg.is_active;
    uvm_config_db#(yapp_agent_config)::set(this,"*","cfg",cfg);
    monitor=yapp_monitor::type_id::create("monitor",this);
    if(cfg.is_active==UVM_ACTIVE) begin
      driver=yapp_driver::type_id::create("driver",this);
      sequencer=yapp_sequencer::type_id::create("sequencer",this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    if(cfg.is_active==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
