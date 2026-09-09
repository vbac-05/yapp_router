class router_base_test extends uvm_test;
  `uvm_component_utils(router_base_test)
  router_env env;
  router_env_config cfg;
  channel_ready_sequence responders[3];
  int unsigned initial_stall=0, max_stall=8;
  bit allow_empty=0;
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(router_env_config)::get(this,"","cfg",cfg))
      `uvm_fatal("NO_CFG","tb_top must supply router_env_config")
    uvm_config_db#(router_env_config)::set(this,"env","cfg",cfg);
    env=router_env::type_id::create("env",this);
  endfunction
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_root::get().print_topology();
  endfunction
  task reset_dut();
    reset_sequence seq=reset_sequence::type_id::create("reset");
    seq.start(env.control.sequencer);
  endtask
  task start_responders();
    foreach(responders[i]) begin
      responders[i]=channel_ready_sequence::type_id::create($sformatf("responder%0d",i));
      responders[i].initial_stall=initial_stall;
      responders[i].max_stall=max_stall;
      fork
        automatic int channel_id=i;
        responders[channel_id].start(env.channels[channel_id].sequencer);
      join_none
    end
  endtask
  task send(int address, int length, int bad=0, int count=1);
    yapp_packet_sequence seq=yapp_packet_sequence::type_id::create("traffic");
    seq.address=address; seq.packet_length=length; seq.bad_parity=bad; seq.count=count;
    seq.start(env.yapp.sequencer);
  endtask
  task write_register(uvm_reg rg, uvm_reg_data_t value);
    uvm_status_e status;
    rg.write(status,value);
    if(status!=UVM_IS_OK) `uvm_fatal("RAL_STATUS","Register write failed")
  endtask
  task raw_access(bit write, bit [15:0] addr, logic [7:0] data=0);
    hbus_access_sequence seq=hbus_access_sequence::type_id::create("raw_hbus");
    seq.write_access=write; seq.address=addr; seq.data=data;
    seq.start(env.hbus.sequencer);
  endtask
  task wait_for_drain();
    // Demand 4 consecutive idle observations; include monitor partial packets.
    // A watchdog bounds missing outputs instead of an arbitrary fixed drain time.
    int stable=0;
    for(int cycle=0;cycle<4000;cycle++) begin
      @(negedge cfg.control_vif.clock);
      if(env.router.scoreboard.pending()==0 && env.yapp.monitor.packet==null &&
         env.channels[0].monitor.packet==null && env.channels[1].monitor.packet==null &&
         env.channels[2].monitor.packet==null &&
         !cfg.channels[0].vif.data_vld && !cfg.channels[1].vif.data_vld && !cfg.channels[2].vif.data_vld)
        stable++;
      else stable=0;
      if(stable==4) return;
    end
    `uvm_fatal("DRAIN_TIMEOUT","DUT/scoreboard did not drain within 4000 cycles")
  endtask
  virtual task scenario(); for(int ch=0;ch<3;ch++) send(ch,8); endtask
  task read_counters();
    raw_access(0,PARITY_CNT_ADDR); raw_access(0,LENGTH_CNT_ADDR); raw_access(0,ILLEGAL_CNT_ADDR);
    raw_access(0,CH0_CNT_ADDR); raw_access(0,CH1_CNT_ADDR); raw_access(0,CH2_CNT_ADDR);
  endtask
  task run_phase(uvm_phase phase);
    phase.raise_objection(this,"Reset, traffic, and drain must all finish");
    fork : watchdog
      begin
        repeat(cfg.timeout_cycles) @(posedge cfg.control_vif.clock);
        `uvm_fatal("TEST_TIMEOUT","Global cycle watchdog expired")
      end
    join_none
    reset_dut();
    start_responders();
    scenario();
    wait_for_drain();
    foreach(responders[i]) responders[i].kill();
    disable watchdog;
    phase.drop_objection(this,"All observed packets checked");
  endtask
  function void check_phase(uvm_phase phase);
    if(!allow_empty && env.router.reference_model.observed==0)
      `uvm_error("VACUOUS_TEST","Traffic test observed zero input packets")
  endfunction
  function void report_phase(uvm_phase phase);
    uvm_report_server server=uvm_report_server::get_server();
    if(server.get_severity_count(UVM_ERROR)==0 && server.get_severity_count(UVM_FATAL)==0)
      `uvm_info("TEST_PASS",get_type_name(),UVM_NONE)
    else `uvm_info("TEST_FAIL",get_type_name(),UVM_NONE)
  endfunction
endclass

class router_smoke_test extends router_base_test;
  `uvm_component_utils(router_smoke_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
endclass

class router_boundary_test extends router_base_test;
  `uvm_component_utils(router_boundary_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    int lengths[8]='{1,14,15,16,17,20,21,63};
    write_register(env.regs.enable,8'hf7);
    for(int ch=0;ch<3;ch++) foreach(lengths[i]) send(ch,lengths[i]);
    wait_for_drain(); read_counters();
  endtask
endclass

class router_drop_test extends router_base_test;
  `uvm_component_utils(router_drop_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    write_register(env.regs.enable,8'hf7); write_register(env.regs.ctrl,20);
    for(int ch=0;ch<3;ch++) begin send(ch,20); send(ch,21); send(ch,0); end
    send(3,8); send(3,63); // Illegal address takes precedence over length.
    write_register(env.regs.enable,8'hf6);
    send(0,8); send(1,63); send(3,8);
    write_register(env.regs.enable,8'hf7); send(2,8);
    wait_for_drain(); read_counters();
  endtask
endclass

class router_parity_test extends router_base_test;
  `uvm_component_utils(router_parity_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    write_register(env.regs.enable,8'hf7);
    for(int ch=0;ch<3;ch++) begin send(ch,1,1); send(ch,63,1); send(ch,8,0); end
    wait_for_drain(); read_counters();
    if(env.router.error_checker.pulses_checked!=6)
      `uvm_error("PARITY_COUNT","Expected six independently checked parity-error pulses")
  endtask
endclass

class router_backpressure_test extends router_base_test;
  `uvm_component_utils(router_backpressure_test)
  function new(string name, uvm_component parent);
    super.new(name,parent); initial_stall=120;
  endfunction
  task scenario();
    bit saw_input_stall=0;
    fork : pressure
      begin
        for(int ch=0;ch<3;ch++) send(ch,63,0,4);
      end
      begin
        forever begin
          @(cfg.yapp.vif.mon_cb);
          if(cfg.yapp.vif.mon_cb.in_suspend) saw_input_stall=1;
        end
      end
    join_any
    disable pressure;
    if(!saw_input_stall) `uvm_error("NO_BACKPRESSURE","Test never exercised input backpressure")
  endtask
endclass

class router_reset_test extends router_base_test;
  `uvm_component_utils(router_reset_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    yapp_packet_sequence seq=yapp_packet_sequence::type_id::create("interrupted_packet");
    seq.address=0; seq.packet_length=63; seq.bad_parity=0;
    fork
      seq.start(env.yapp.sequencer);
      begin
        wait(env.yapp.monitor.packet!=null);
        repeat(5) @(negedge cfg.control_vif.clock);
        reset_dut();
      end
    join
    if(seq.aborted_count!=1) `uvm_error("RESET_ABORT","The input packet was not interrupted")
    write_register(env.regs.enable,8'hf7);
    for(int ch=0;ch<3;ch++) send(ch,8);
    wait_for_drain(); read_counters();
  endtask
endclass

class router_virtual_test extends router_base_test;
  `uvm_component_utils(router_virtual_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    router_virtual_sequence seq=router_virtual_sequence::type_id::create("system_sequence");
    seq.start(env.virtual_sequencer);
    wait_for_drain(); read_counters();
  endtask
endclass

class router_random_test extends router_base_test;
  `uvm_component_utils(router_random_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    write_register(env.regs.enable,8'hf7);
    send(-1,-1,-1,200);
    wait_for_drain(); read_counters();
  endtask
endclass

class router_factory_test extends router_base_test;
  `uvm_component_utils(router_factory_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    yapp_packet::type_id::set_type_override(short_yapp_packet::get_type());
    super.build_phase(phase);
  endfunction
  task scenario(); send(-1,-1,0,12); endtask
endclass

class router_register_test extends router_base_test;
  `uvm_component_utils(router_register_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    uvm_reg_hw_reset_seq reset_check=uvm_reg_hw_reset_seq::type_id::create("reset_check");
    reset_check.model=env.regs; reset_check.start(null);
    for(int i=0;i<64;i++) raw_access(0,PACKET_MEM_ADDR+16'(i));
    write_register(env.regs.ctrl,20); raw_access(0,CTRL_ADDR);
    write_register(env.regs.ctrl,63);
    // Raw HBUS writes demonstrate explicit RAL prediction outside the RAL API.
    raw_access(1,ENABLE_ADDR,8'h01);
    for(int ch=0;ch<3;ch++) send(ch,8);
    wait_for_drain(); read_counters(); // Enables clear -> counters stay zero.
    raw_access(1,ENABLE_ADDR,8'hf7);
    if(env.regs.enable.get_mirrored_value()!=8'hf7)
      `uvm_error("PREDICTOR","Raw HBUS write was not mirrored in RAL")
    for(int ch=0;ch<3;ch++) send(ch,8,0,2);
    wait_for_drain(); read_counters();
    // Frontdoor writes to read-only counters must have no effect.
    raw_access(1,CH0_CNT_ADDR,8'haa); raw_access(0,CH0_CNT_ADDR);
    // Read the last packet through its memory-mapped window.
    raw_access(0,LAST_LEN_ADDR);
    for(int i=0;i<9;i++) raw_access(0,PACKET_MEM_ADDR+16'(i));
  endtask
endclass

class router_memory_test extends router_base_test;
  `uvm_component_utils(router_memory_test)
  function new(string name, uvm_component parent); super.new(name,parent); allow_empty=1; endfunction
  task scenario();
    uvm_status_e status;
    uvm_reg_data_t value;
    for(int i=0;i<256;i++) begin
      env.regs.scratch_memory.read(status,i,value);
      if(status!=UVM_IS_OK || value!==0)
        `uvm_error("MEMORY_RESET",$sformatf("Nonzero reset value at index %0d",i))
    end
    // Full address sweep; 8-bit patterns distinguish each memory location.
    for(int i=0;i<256;i++) begin
      env.regs.scratch_memory.write(status,i,8'(i^8'ha5));
      if(status!=UVM_IS_OK) `uvm_error("RAL_STATUS","Memory write failed")
    end
    for(int i=0;i<256;i++) begin
      env.regs.scratch_memory.read(status,i,value);
      if(status!=UVM_IS_OK || value[7:0]!=8'(i^8'ha5))
        `uvm_error("MEMORY_DATA",$sformatf("Memory mismatch at index %0d",i))
    end
  endtask
endclass

class router_counter_wrap_test extends router_base_test;
  `uvm_component_utils(router_counter_wrap_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    write_register(env.regs.enable,8'hf7);
    send(0,1,0,260);
    wait_for_drain(); read_counters();
    if(env.regs.address_counter[0].get_mirrored_value()!=4)
      `uvm_error("COUNTER_WRAP","8-bit channel counter must wrap 260 to 4")
  endtask
endclass

class router_scoreboard_negative_test extends router_base_test;
  `uvm_component_utils(router_scoreboard_negative_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase); cfg.inject_scoreboard_fault=1;
  endfunction
  // Expected to FAIL with PACKET_MISMATCH; the runner checks that exact signature.
endclass

// Lab 1 concepts, isolated from DUT routing so object bugs are easy to locate.
class router_packet_api_test extends router_base_test;
  `uvm_component_utils(router_packet_api_test)
  function new(string name, uvm_component parent); super.new(name,parent); allow_empty=1; endfunction
  task scenario();
    yapp_packet original, copied, unpacked;
    byte unsigned stream[];
    int packed_bits, unpacked_bits;
    bit [7:0] saved_parity;
    original=yapp_packet::type_id::create("original");
    unpacked=yapp_packet::type_id::create("unpacked");
    if(!original.randomize() with { length==8; parity_kind==PARITY_BAD; })
      `uvm_fatal("RANDOMIZE","Packet API test randomization failed")
    saved_parity=original.parity;
    void'(original.expected_parity());
    if(original.parity!==saved_parity) `uvm_error("PARITY_PURITY","Calculation modified stored parity")
    if(!$cast(copied,original.clone())) `uvm_fatal("CLONE","Packet clone failed")
    if(!original.compare(copied)) `uvm_error("COPY_COMPARE","Clone differs from original")
    copied.payload[0]^=8'h01;
    if(original.payload[0]==copied.payload[0]) `uvm_error("COPY_ALIAS","Payload is not independently copied")
    if(original.compare(copied)) `uvm_error("COMPARE_FAULT","Corrupted payload was not detected")
    packed_bits=original.pack_bytes(stream);
    unpacked_bits=unpacked.unpack_bytes(stream);
    if(packed_bits!=unpacked_bits || !original.compare(unpacked))
      `uvm_error("PACK_ROUNDTRIP","Packet pack/unpack did not round-trip")
    original.print();
  endtask
endclass

class router_enable_bits_test extends router_base_test;
  `uvm_component_utils(router_enable_bits_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    int counter_bits[6]='{1,2,4,5,6,7};
    foreach(counter_bits[i]) begin
      reset_dut();
      write_register(env.regs.ctrl,20);
      write_register(env.regs.enable,8'(1 | (1 << counter_bits[i])));
      // Only one counter enable is set, although every error kind is exercised.
      for(int ch=0;ch<3;ch++) begin send(ch,8,1); send(ch,21); end
      send(3,8); send(0,0);
      wait_for_drain(); read_counters();
    end
    // Reserved bits and zero max length have explicit clean-DUT behavior.
    raw_access(1,CTRL_ADDR,8'hff); raw_access(0,CTRL_ADDR);
    raw_access(1,ENABLE_ADDR,8'hff); raw_access(0,ENABLE_ADDR);
    write_register(env.regs.ctrl,0);
    for(int ch=0;ch<3;ch++) send(ch,1);
    wait_for_drain(); read_counters();
    raw_access(0,16'h1234); // Unmapped reads return zero.
  endtask
endclass

class router_backdoor_test extends router_base_test;
  `uvm_component_utils(router_backdoor_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction
  task scenario();
    uvm_status_e status;
    uvm_reg_data_t value;
    // Observe frontdoor effects through backdoor. Do not bypass HBUS prediction
    // with hidden backdoor writes that would leave the reference model stale.
    write_register(env.regs.ctrl,20);
    env.regs.ctrl.peek(status,value);
    if(status!=UVM_IS_OK || value!=20) `uvm_error("BACKDOOR","Control HDL path/data incorrect")
    write_register(env.regs.enable,8'hf7);
    send(2,8); wait_for_drain();
    env.regs.address_counter[2].peek(status,value);
    if(status!=UVM_IS_OK || value!=1) `uvm_error("BACKDOOR","Counter HDL path/data incorrect")
    env.regs.scratch_memory.write(status,15,8'ha5);
    if(status!=UVM_IS_OK) `uvm_error("RAL_STATUS","Scratch frontdoor write failed")
    env.regs.scratch_memory.peek(status,15,value);
    if(status!=UVM_IS_OK || value!=8'ha5) `uvm_error("BACKDOOR","Scratch HDL path/data incorrect")
  endtask
endclass

class router_memory_walk_test extends router_base_test;
  `uvm_component_utils(router_memory_walk_test)
  function new(string name, uvm_component parent); super.new(name,parent); allow_empty=1; endfunction
  task scenario();
    uvm_mem_walk_seq seq=uvm_mem_walk_seq::type_id::create("memory_walk");
    seq.model=env.regs;
    seq.start(null);
  endtask
endclass
