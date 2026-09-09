class hbus_sequencer extends uvm_sequencer #(hbus_item);
  `uvm_component_utils(hbus_sequencer)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass

class hbus_driver extends uvm_driver #(hbus_item);
  `uvm_component_utils(hbus_driver)
  hbus_agent_config cfg;
  virtual hbus_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(hbus_agent_config)::get(this,"","cfg",cfg) || cfg.vif==null)
      `uvm_fatal("NO_CFG","HBUS driver needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task transfer(hbus_item item);
    @(vif.drv_cb);
    vif.drv_cb.hen <= 1;
    vif.drv_cb.hwr_rd <= item.write;
    vif.drv_cb.haddr <= item.address;
    vif.drv_cb.write_data <= item.data;
    @(vif.mon_cb);
    if(!item.write) begin
      @(vif.mon_cb);
      item.data=vif.mon_cb.hdata;
      if($isunknown(item.data)) `uvm_error("HBUS_X","Read returned X/Z")
    end
  endtask
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      wait(!vif.reset); req.aborted=0;
      fork : transfer_or_reset
        transfer(req);
        begin @(posedge vif.reset); req.aborted=1; end
      join_any
      disable transfer_or_reset;
      @(vif.drv_cb);
      vif.drv_cb.hen <= 0;
      vif.drv_cb.hwr_rd <= 0;
      @(vif.mon_cb); // Idle cycle separates transactions, including reads.
      seq_item_port.item_done(); // Read result returned in the original request.
    end
  endtask
endclass

class hbus_monitor extends uvm_monitor;
  `uvm_component_utils(hbus_monitor)
  uvm_analysis_port #(hbus_item) transaction_ap;
  hbus_agent_config cfg;
  virtual hbus_if vif;
  function new(string name, uvm_component parent);
    super.new(name,parent); transaction_ap=new("transaction_ap",this);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(hbus_agent_config)::get(this,"","cfg",cfg) || cfg.vif==null)
      `uvm_fatal("NO_CFG","HBUS monitor needs cfg.vif")
    vif=cfg.vif;
  endfunction
  task run_phase(uvm_phase phase);
    hbus_item item;
    forever begin
      @(vif.mon_cb);
      if(!vif.mon_cb.reset && vif.mon_cb.hen) begin
        item=hbus_item::type_id::create("observed_hbus");
        item.address=vif.mon_cb.haddr;
        item.write=vif.mon_cb.hwr_rd;
        if(!item.write) @(vif.mon_cb);
        if(!vif.mon_cb.reset) begin
          item.data=vif.mon_cb.hdata;
          transaction_ap.write(item);
          `uvm_info("HBUS_OBSERVED",item.convert2string(),UVM_HIGH)
        end
        do @(vif.mon_cb); while(vif.mon_cb.hen && !vif.mon_cb.reset);
      end
    end
  endtask
endclass

class hbus_agent extends uvm_agent;
  `uvm_component_utils(hbus_agent)
  hbus_agent_config cfg;
  hbus_driver driver;
  hbus_sequencer sequencer;
  hbus_monitor monitor;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(hbus_agent_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","HBUS agent needs configuration")
    is_active=cfg.is_active;
    uvm_config_db#(hbus_agent_config)::set(this,"*","cfg",cfg);
    monitor=hbus_monitor::type_id::create("monitor",this);
    if(cfg.is_active==UVM_ACTIVE) begin
      driver=hbus_driver::type_id::create("driver",this);
      sequencer=hbus_sequencer::type_id::create("sequencer",this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    if(cfg.is_active==UVM_ACTIVE) driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
