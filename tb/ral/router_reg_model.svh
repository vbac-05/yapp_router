// Handwritten RAL makes register construction visible while learning.
// Address constants belong to the TB; RTL has its own decode implementation.
class router_byte_reg extends uvm_reg;
  `uvm_object_utils(router_byte_reg)
  uvm_reg_field value;
  function new(string name="router_byte_reg"); super.new(name,8,UVM_NO_COVERAGE); endfunction
  function void build(string access="RO", bit [7:0] reset_value=0, bit is_volatile=1);
    value=uvm_reg_field::type_id::create("value");
    value.configure(this,8,0,access,is_volatile,reset_value,1,0,1);
  endfunction
endclass

class router_ctrl_reg extends uvm_reg;
  `uvm_object_utils(router_ctrl_reg)
  rand uvm_reg_field maxpktsize;
  function new(string name="router_ctrl_reg"); super.new(name,8,UVM_NO_COVERAGE); endfunction
  function void build();
    maxpktsize=uvm_reg_field::type_id::create("maxpktsize");
    maxpktsize.configure(this,6,0,"RW",0,63,1,1,1);
    // Unmodelled upper bits are reserved, excluded from compare masks.
  endfunction
endclass

class router_enable_reg extends uvm_reg;
  `uvm_object_utils(router_enable_reg)
  rand uvm_reg_field router_en, parity_count_en, length_count_en;
  rand uvm_reg_field address_count_en[4];
  function new(string name="router_enable_reg"); super.new(name,8,UVM_NO_COVERAGE); endfunction
  function void build();
    router_en=uvm_reg_field::type_id::create("router_en");
    router_en.configure(this,1,0,"RW",0,1,1,1,0);
    parity_count_en=uvm_reg_field::type_id::create("parity_count_en");
    parity_count_en.configure(this,1,1,"RW",0,0,1,1,0);
    length_count_en=uvm_reg_field::type_id::create("length_count_en");
    length_count_en.configure(this,1,2,"RW",0,0,1,1,0);
    foreach(address_count_en[i]) begin
      address_count_en[i]=uvm_reg_field::type_id::create($sformatf("address%0d_count_en",i));
      address_count_en[i].configure(this,1,4+i,"RW",0,0,1,1,0);
    end
  endfunction
endclass

class router_reg_block extends uvm_reg_block;
  `uvm_object_utils(router_reg_block)
  rand router_ctrl_reg ctrl;
  rand router_enable_reg enable;
  router_byte_reg parity_counter, length_counter, illegal_counter;
  router_byte_reg address_counter[3], last_length;
  uvm_mem packet_memory, scratch_memory;
  function new(string name="router_reg_block"); super.new(name,UVM_NO_COVERAGE); endfunction
  function router_byte_reg add_counter(string name, uvm_reg_addr_t address, string path);
    router_byte_reg r=router_byte_reg::type_id::create(name);
    r.configure(this); r.build("RO",0,1);
    r.add_hdl_path_slice(path,0,8);
    default_map.add_reg(r,address,"RO");
    return r;
  endfunction
  function void build();
    default_map=create_map("hbus_map",0,1,UVM_LITTLE_ENDIAN,1);
    ctrl=router_ctrl_reg::type_id::create("ctrl");
    ctrl.configure(this); ctrl.build();
    ctrl.add_hdl_path_slice("maxpktsize",0,6);
    default_map.add_reg(ctrl,CTRL_ADDR,"RW");
    enable=router_enable_reg::type_id::create("enable");
    enable.configure(this); enable.build();
    enable.add_hdl_path_slice("enables",0,8);
    default_map.add_reg(enable,ENABLE_ADDR,"RW");
    parity_counter=add_counter("parity_counter",PARITY_CNT_ADDR,"parity_count");
    length_counter=add_counter("length_counter",LENGTH_CNT_ADDR,"oversized_count");
    illegal_counter=add_counter("illegal_counter",ILLEGAL_CNT_ADDR,"illegal_count");
    foreach(address_counter[i])
      address_counter[i]=add_counter($sformatf("address%0d_counter",i),CH0_CNT_ADDR+i,
                                    $sformatf("addr_count[%0d]",i));
    last_length=router_byte_reg::type_id::create("last_length");
    last_length.configure(this); last_length.build("RO",0,1);
    last_length.add_hdl_path_slice("last_length",0,6);
    default_map.add_reg(last_length,LAST_LEN_ADDR,"RO");
    packet_memory=new("packet_memory",64,8,"RO",UVM_NO_COVERAGE);
    packet_memory.configure(this,"packet_memory");
    default_map.add_mem(packet_memory,PACKET_MEM_ADDR,"RO");
    scratch_memory=new("scratch_memory",256,8,"RW",UVM_NO_COVERAGE);
    scratch_memory.configure(this,"scratch_memory");
    default_map.add_mem(scratch_memory,SCRATCH_MEM_ADDR,"RW");
    lock_model(); reset();
  endfunction
endclass

class hbus_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(hbus_reg_adapter)
  function new(string name="hbus_reg_adapter");
    super.new(name); supports_byte_enable=0; provides_responses=0;
  endfunction
  function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    hbus_item item=hbus_item::type_id::create("ral_hbus");
    item.write=(rw.kind==UVM_WRITE);
    item.address=rw.addr[15:0]; item.data=rw.data[7:0];
    return item;
  endfunction
  function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    hbus_item item;
    if(!$cast(item,bus_item)) `uvm_fatal("ADAPTER_TYPE","Expected hbus_item")
    rw.kind=item.write ? UVM_WRITE : UVM_READ;
    rw.addr=item.address; rw.data=item.data; rw.n_bits=8;
    rw.status=item.aborted || $isunknown(item.data) ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass
