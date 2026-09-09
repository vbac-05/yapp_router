class reset_sequencer extends uvm_sequencer #(reset_item);
  `uvm_component_utils(reset_sequencer)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass
class reset_driver extends uvm_driver #(reset_item);
  `uvm_component_utils(reset_driver)
  virtual clock_reset_if vif;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    if(!uvm_config_db#(virtual clock_reset_if)::get(this,"","vif",vif) || vif==null)
      `uvm_fatal("NO_VIF","Reset driver needs virtual interface")
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      @(vif.drv_cb); vif.drv_cb.reset <= 1;
      repeat(req.cycles) @(vif.drv_cb);
      vif.drv_cb.reset <= 0;
      @(posedge vif.clock);
      seq_item_port.item_done();
    end
  endtask
endclass
class reset_monitor extends uvm_monitor;
  `uvm_component_utils(reset_monitor)
  virtual clock_reset_if vif;
  uvm_analysis_port #(reset_item) reset_ap;
  function new(string name, uvm_component parent);
    super.new(name,parent); reset_ap=new("reset_ap",this);
  endfunction
  function void build_phase(uvm_phase phase);
    if(!uvm_config_db#(virtual clock_reset_if)::get(this,"","vif",vif) || vif==null)
      `uvm_fatal("NO_VIF","Reset monitor needs virtual interface")
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      reset_item item;
      @(posedge vif.reset);
      item=reset_item::type_id::create("observed_reset");
      reset_ap.write(item);
    end
  endtask
endclass
class clock_reset_agent extends uvm_agent;
  `uvm_component_utils(clock_reset_agent)
  reset_driver driver;
  reset_sequencer sequencer;
  reset_monitor monitor;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    driver=reset_driver::type_id::create("driver",this);
    sequencer=reset_sequencer::type_id::create("sequencer",this);
    monitor=reset_monitor::type_id::create("monitor",this);
  endfunction
  function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
