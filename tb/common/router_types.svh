typedef enum bit {PARITY_GOOD, PARITY_BAD} parity_kind_e;
typedef enum int {ROUTE_OK, DROP_DISABLED, DROP_ADDRESS, DROP_LENGTH} route_reason_e;
localparam bit [15:0] CTRL_ADDR = 16'h1000, ENABLE_ADDR = 16'h1001;
localparam bit [15:0] PARITY_CNT_ADDR = 16'h1004, LENGTH_CNT_ADDR = 16'h1005;
localparam bit [15:0] ILLEGAL_CNT_ADDR = 16'h1006, CH0_CNT_ADDR = 16'h1009;
localparam bit [15:0] CH1_CNT_ADDR = 16'h100a, CH2_CNT_ADDR = 16'h100b;
localparam bit [15:0] LAST_LEN_ADDR = 16'h100d;
localparam bit [15:0] PACKET_MEM_ADDR = 16'h1010, SCRATCH_MEM_ADDR = 16'h1100;

// Only on-wire fields are compared. Delay/sequence metadata are not DUT data.
class yapp_packet extends uvm_sequence_item;
  `uvm_object_utils(yapp_packet)
  rand bit [1:0] addr;
  rand bit [5:0] length;
  rand bit [7:0] payload[];
  logic [7:0] parity;
  rand parity_kind_e parity_kind;
  rand int unsigned gap_cycles;
  // Knobs let negative tests generate otherwise-illegal packets deliberately.
  bit allow_illegal_address = 0;
  bit allow_zero_length = 0;
  bit aborted = 0;
  time observed_at;
  constraint c_payload { payload.size() == int'(length); }
  constraint c_length { if (!allow_zero_length) length inside {[1:63]}; }
  constraint c_address { if (!allow_illegal_address) addr inside {[0:2]}; }
  constraint c_gap { gap_cycles inside {[0:4]}; }
  constraint c_parity { parity_kind dist {PARITY_GOOD := 5, PARITY_BAD := 1}; }
  function new(string name="yapp_packet"); super.new(name); endfunction
  // Pure function: never overwrite the parity captured from the bus.
  function bit [7:0] expected_parity();
    bit [7:0] result = {length, addr};
    foreach (payload[i]) result ^= payload[i];
    return result;
  endfunction
  function void post_randomize();
    parity = expected_parity() ^ (parity_kind == PARITY_BAD ? 8'h01 : 8'h00);
  endfunction
  function void do_copy(uvm_object rhs);
    yapp_packet p;
    super.do_copy(rhs);
    if (!$cast(p, rhs)) `uvm_fatal("COPY_TYPE", "Expected yapp_packet")
    addr=p.addr; length=p.length; payload=p.payload; parity=p.parity;
    parity_kind=p.parity_kind; gap_cycles=p.gap_cycles;
    allow_illegal_address=p.allow_illegal_address; allow_zero_length=p.allow_zero_length;
    aborted=p.aborted; observed_at=p.observed_at;
  endfunction
  function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    yapp_packet p;
    if (!$cast(p, rhs)) return 0;
    if (addr != p.addr || length != p.length || payload.size() != p.payload.size()) return 0;
    foreach (payload[i]) if (payload[i] != p.payload[i]) return 0;
    return parity === p.parity;
  endfunction
  function void do_print(uvm_printer printer);
    super.do_print(printer);
    printer.print_field_int("addr",addr,2,UVM_DEC);
    printer.print_field_int("length",length,6,UVM_DEC);
    foreach(payload[i]) printer.print_field_int($sformatf("payload[%0d]",i),payload[i],8,UVM_HEX);
    printer.print_field_int("parity",parity,8,UVM_HEX);
    printer.print_string("parity_kind",parity_kind.name());
  endfunction
  // Exactly header + payload + parity. Delay and sequence metadata are excluded.
  function void do_pack(uvm_packer packer);
    super.do_pack(packer);
    packer.pack_field_int({length,addr},8);
    foreach(payload[i]) packer.pack_field_int(payload[i],8);
    packer.pack_field_int(parity,8);
  endfunction
  function void do_unpack(uvm_packer packer);
    super.do_unpack(packer);
    {length,addr}=8'(packer.unpack_field_int(8));
    payload=new[length];
    foreach(payload[i]) payload[i]=8'(packer.unpack_field_int(8));
    parity=8'(packer.unpack_field_int(8));
    parity_kind=parity===expected_parity() ? PARITY_GOOD : PARITY_BAD;
  endfunction
  function string convert2string();
    return $sformatf("addr=%0d length=%0d payload=%p parity=%02h (%s)",
      addr, length, payload, parity, parity_kind.name());
  endfunction
endclass

class hbus_item extends uvm_sequence_item;
  `uvm_object_utils(hbus_item)
  rand bit write;
  rand bit [15:0] address;
  rand logic [7:0] data;
  bit aborted = 0;
  function new(string name="hbus_item"); super.new(name); endfunction
  function void do_copy(uvm_object rhs);
    hbus_item t;
    super.do_copy(rhs);
    if (!$cast(t, rhs)) `uvm_fatal("COPY_TYPE", "Expected hbus_item")
    write=t.write; address=t.address; data=t.data; aborted=t.aborted;
  endfunction
  function string convert2string();
    return $sformatf("%s address=%04h data=%02h", write ? "WRITE" : "READ", address, data);
  endfunction
endclass

class channel_response extends uvm_sequence_item;
  `uvm_object_utils(channel_response)
  rand int unsigned stall_cycles, ready_cycles;
  constraint c_delay { stall_cycles inside {[0:8]}; ready_cycles inside {[1:12]}; }
  function new(string name="channel_response"); super.new(name); endfunction
endclass

class reset_item extends uvm_sequence_item;
  `uvm_object_utils(reset_item)
  rand int unsigned cycles;
  constraint c_cycles { cycles inside {[2:10]}; }
  function new(string name="reset_item"); super.new(name); endfunction
endclass

class route_event extends uvm_object;
  `uvm_object_utils(route_event)
  yapp_packet packet;
  route_reason_e reason;
  bit [5:0] maxpktsize;
  function new(string name="route_event"); super.new(name); endfunction
endclass
