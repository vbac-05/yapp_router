class router_coverage extends uvm_subscriber #(route_event);
  `uvm_component_utils(router_coverage)
  covergroup packet_cg with function sample(int address, int length, bit bad_parity,
                                            int reason, bit at_limit);
    option.per_instance=1;
    cp_addr: coverpoint address { bins legal[]={[0:2]}; bins illegal_address={3}; }
    cp_length: coverpoint length {
      bins zero={0}; bins minimum={1}; bins short_payload={[2:14]};
      bins fifo_boundary[]={[15:17]}; bins medium_payload={[18:62]}; bins maximum={63};
    }
    cp_parity: coverpoint bad_parity;
    cp_reason: coverpoint reason { bins outcomes[]={[0:3]}; }
    cp_limit: coverpoint at_limit;
    addr_length: cross cp_addr,cp_length;
    addr_parity: cross cp_addr,cp_parity;
    addr_outcome: cross cp_addr,cp_reason {
      // Address 3 can only be disabled/address-dropped; legal addresses cannot
      // trigger an address drop. These are spec exclusions, not coverage holes.
      ignore_bins illegal_forward = binsof(cp_addr.illegal_address) && binsof(cp_reason) intersect {0,3};
      ignore_bins legal_address_drop = binsof(cp_addr.legal) && binsof(cp_reason) intersect {2};
    }
  endgroup
  function new(string name, uvm_component parent);
    super.new(name,parent); packet_cg=new();
  endfunction
  function void write(route_event t);
    packet_cg.sample(t.packet.addr,t.packet.length,
      t.packet.parity_kind==PARITY_BAD,int'(t.reason),t.packet.length==t.maxpktsize);
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("COVERAGE",$sformatf("Input/decision coverage: %.2f%% (not a sign-off claim)",
      packet_cg.get_inst_coverage()),UVM_LOW)
  endfunction
endclass

// Sample only scoreboard-confirmed output packets, never sequence intentions.
class router_output_coverage extends uvm_subscriber #(yapp_packet);
  `uvm_component_utils(router_output_coverage)
  covergroup output_cg with function sample(int address, int length, bit bad);
    option.per_instance=1;
    cp_channel: coverpoint address { bins channels[]={[0:2]}; }
    cp_length: coverpoint length {
      bins minimum={1}; bins short_payload={[2:14]}; bins fifo_boundary[]={[15:17]};
      bins long_payload={[18:62]}; bins maximum={63};
    }
    cp_parity: coverpoint bad;
    checked_packet: cross cp_channel,cp_length,cp_parity;
  endgroup
  function new(string name, uvm_component parent); super.new(name,parent); output_cg=new(); endfunction
  function void write(yapp_packet t);
    output_cg.sample(t.addr,t.length,t.parity_kind==PARITY_BAD);
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("OUTPUT_COVERAGE",$sformatf("Checked output coverage %.2f%%",output_cg.get_inst_coverage()),UVM_LOW)
  endfunction
endclass

class hbus_coverage extends uvm_subscriber #(hbus_item);
  `uvm_component_utils(hbus_coverage)
  covergroup bus_cg with function sample(int address, bit write);
    option.per_instance=1;
    cp_addr: coverpoint address {
      bins config_regs[]={16'h1000,16'h1001};
      bins counters[]={16'h1004,16'h1005,16'h1006,16'h1009,16'h100a,16'h100b,16'h100d};
      bins packet_memory={[16'h1010:16'h104f]};
      bins scratch_memory={[16'h1100:16'h11ff]};
      bins unmapped=default;
    }
    cp_write: coverpoint write;
    access_kind: cross cp_addr,cp_write;
  endgroup
  function new(string name, uvm_component parent); super.new(name,parent); bus_cg=new(); endfunction
  function void write(hbus_item t); bus_cg.sample(t.address,t.write); endfunction
endclass
