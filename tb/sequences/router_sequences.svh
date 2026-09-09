class short_yapp_packet extends yapp_packet;
  `uvm_object_utils(short_yapp_packet)
  constraint c_short { length inside {[1:14]}; }
  function new(string name="short_yapp_packet"); super.new(name); endfunction
endclass

class yapp_packet_sequence extends uvm_sequence #(yapp_packet);
  `uvm_object_utils(yapp_packet_sequence)
  int address=-1, packet_length=-1, bad_parity=-1;
  int unsigned count=1, aborted_count=0;
  bit incrementing_payload=0;
  function new(string name="yapp_packet_sequence"); super.new(name); endfunction
  task body();
    repeat(count) begin
      req=yapp_packet::type_id::create("packet");
      req.allow_illegal_address=(address==3);
      req.allow_zero_length=(packet_length==0);
      start_item(req);
      if(!req.randomize() with {
        if(local::address>=0) addr==local::address;
        if(local::packet_length>=0) length==local::packet_length;
        if(local::bad_parity>=0) int'(parity_kind)==local::bad_parity;
      }) `uvm_fatal("RANDOMIZE","Packet constraints are inconsistent")
      if(incrementing_payload) begin
        foreach(req.payload[i]) req.payload[i]=8'(i);
        req.post_randomize();
      end
      finish_item(req);
      if(req.aborted) aborted_count++;
    end
  endtask
endclass

class channel_ready_sequence extends uvm_sequence #(channel_response);
  `uvm_object_utils(channel_ready_sequence)
  int unsigned initial_stall=0, max_stall=8;
  function new(string name="channel_ready_sequence"); super.new(name); endfunction
  task body();
    if(initial_stall!=0) begin
      req=channel_response::type_id::create("initial_backpressure");
      start_item(req); req.stall_cycles=initial_stall; req.ready_cycles=1; finish_item(req);
    end
    // This responder is intentionally forever. The TEST owns the objection.
    forever begin
      req=channel_response::type_id::create("response");
      start_item(req);
      if(!req.randomize() with {stall_cycles<=local::max_stall;})
        `uvm_fatal("RANDOMIZE","Channel response randomization failed")
      finish_item(req);
    end
  endtask
endclass

class reset_sequence extends uvm_sequence #(reset_item);
  `uvm_object_utils(reset_sequence)
  int unsigned duration=5;
  function new(string name="reset_sequence"); super.new(name); endfunction
  task body();
    req=reset_item::type_id::create("reset_request");
    start_item(req); req.cycles=duration; finish_item(req);
  endtask
endclass

class hbus_access_sequence extends uvm_sequence #(hbus_item);
  `uvm_object_utils(hbus_access_sequence)
  bit write_access;
  bit [15:0] address;
  logic [7:0] data;
  function new(string name="hbus_access_sequence"); super.new(name); endfunction
  task body();
    req=hbus_item::type_id::create("access");
    start_item(req);
    req.write=write_access; req.address=address; req.data=data;
    finish_item(req);
    data=req.data;
    if(req.aborted) `uvm_error("HBUS_ABORTED","Register access interrupted by reset")
  endtask
endclass

class router_virtual_sequence extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(router_virtual_sequence)
  `uvm_declare_p_sequencer(router_virtual_sequencer)
  function new(string name="router_virtual_sequence"); super.new(name); endfunction
  task configure_router(bit [7:0] max_length, bit [7:0] enables);
    uvm_status_e status;
    uvm_reg_data_t value;
    p_sequencer.regs.ctrl.write(status,max_length,UVM_FRONTDOOR,null,this);
    if(status!=UVM_IS_OK) `uvm_fatal("RAL_STATUS","Control write failed")
    p_sequencer.regs.enable.write(status,enables,UVM_FRONTDOOR,null,this);
    if(status!=UVM_IS_OK) `uvm_fatal("RAL_STATUS","Enable write failed")
    p_sequencer.regs.ctrl.read(status,value,UVM_FRONTDOOR,null,this);
    if(status!=UVM_IS_OK || value[5:0]!=max_length[5:0])
      `uvm_error("CONFIG_READBACK","Incorrect maximum length")
  endtask
  task send(int addr, int length, int bad=0, int count=1);
    yapp_packet_sequence seq=yapp_packet_sequence::type_id::create("traffic");
    seq.address=addr; seq.packet_length=length; seq.bad_parity=bad; seq.count=count;
    seq.start(p_sequencer.yapp_seqr,this);
  endtask
  task body();
    configure_router(20,8'hf7);
    for(int ch=0;ch<3;ch++) begin
      send(ch,1); send(ch,20); send(ch,21); send(ch,8,1);
    end
    send(3,8); send(0,0);
    configure_router(63,8'hf7);
    send(-1,-1,-1,12);
  endtask
endclass
