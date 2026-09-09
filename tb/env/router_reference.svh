`uvm_analysis_imp_decl(_input)
`uvm_analysis_imp_decl(_hbus)
`uvm_analysis_imp_decl(_reset)

// Functional specification, not an RTL/FIFO implementation model.
class router_reference extends uvm_component;
  `uvm_component_utils(router_reference)
  uvm_analysis_imp_input #(yapp_packet,router_reference) input_imp;
  uvm_analysis_imp_hbus #(hbus_item,router_reference) hbus_imp;
  uvm_analysis_imp_reset #(reset_item,router_reference) reset_imp;
  uvm_analysis_port #(yapp_packet) expected_ap;
  uvm_analysis_port #(route_event) route_ap;
  router_reg_block regs;
  bit [7:0] enable=8'h01;
  bit [5:0] maxpktsize=63;
  bit [7:0] parity_count, length_count, illegal_count, addr_count[3];
  bit [5:0] last_length;
  bit [7:0] packet_memory[64], scratch_memory[256];
  int unsigned observed=0, forwarded=0, dropped[4]='{default:0}, reset_count=0;
  function new(string name, uvm_component parent);
    super.new(name,parent);
    input_imp=new("input_imp",this); hbus_imp=new("hbus_imp",this);
    reset_imp=new("reset_imp",this); expected_ap=new("expected_ap",this);
    route_ap=new("route_ap",this);
  endfunction
  function void predict_counters();
    // HW changes are not HBUS transfers: explicitly predict these values.
    if(regs!=null) begin
      void'(regs.parity_counter.predict(parity_count));
      void'(regs.length_counter.predict(length_count));
      void'(regs.illegal_counter.predict(illegal_count));
      foreach(addr_count[i]) void'(regs.address_counter[i].predict(addr_count[i]));
      void'(regs.last_length.predict(last_length));
    end
  endfunction
  function void write_input(yapp_packet packet);
    route_event result=route_event::type_id::create("route_decision");
    yapp_packet expected;
    observed++;
    result.packet=packet; result.maxpktsize=maxpktsize;
    if(!enable[0]) result.reason=DROP_DISABLED;
    else begin
      last_length=packet.length;
      packet_memory[0]={packet.length,packet.addr};
      foreach(packet.payload[i]) packet_memory[i+1]=packet.payload[i];
      if(packet.addr==3) begin
        result.reason=DROP_ADDRESS;
        if(enable[7]) illegal_count++;
      end else if(packet.length==0 || packet.length>maxpktsize) begin
        result.reason=DROP_LENGTH;
        if(enable[2]) length_count++;
      end else begin
        result.reason=ROUTE_OK;
        if(enable[4+packet.addr]) addr_count[packet.addr]++;
        if(packet.parity!==packet.expected_parity() && enable[1]) parity_count++;
      end
    end
    if(result.reason==ROUTE_OK) begin
      if(!$cast(expected,packet.clone())) `uvm_fatal("CLONE","Packet clone failed")
      expected_ap.write(expected);
      forwarded++;
    end else dropped[int'(result.reason)]++;
    predict_counters();
    route_ap.write(result);
  endfunction
  function void write_hbus(hbus_item item);
    bit [7:0] expected;
    bit check_read=1;
    if(item.write) begin
      case(item.address)
        CTRL_ADDR: maxpktsize=item.data[5:0];
        ENABLE_ADDR: enable=item.data & 8'hf7;
        default: if(item.address>=SCRATCH_MEM_ADDR && item.address<=16'h11ff)
          scratch_memory[item.address-SCRATCH_MEM_ADDR]=item.data;
      endcase
    end else begin
      case(item.address)
        CTRL_ADDR: expected={2'b00,maxpktsize};
        ENABLE_ADDR: expected=enable;
        PARITY_CNT_ADDR: expected=parity_count;
        LENGTH_CNT_ADDR: expected=length_count;
        ILLEGAL_CNT_ADDR: expected=illegal_count;
        CH0_CNT_ADDR: expected=addr_count[0];
        CH1_CNT_ADDR: expected=addr_count[1];
        CH2_CNT_ADDR: expected=addr_count[2];
        LAST_LEN_ADDR: expected={2'b00,last_length};
        default: begin
          if(item.address>=SCRATCH_MEM_ADDR && item.address<=16'h11ff)
            expected=scratch_memory[item.address-SCRATCH_MEM_ADDR];
          else if(item.address>=PACKET_MEM_ADDR && item.address<=16'h104f)
            expected=packet_memory[item.address-PACKET_MEM_ADDR];
          else expected=0; // Clean DUT defines unmapped reads as zero.
        end
      endcase
      if(check_read && item.data!==expected)
        `uvm_error("HBUS_MISMATCH",$sformatf("addr=%04h expected=%02h actual=%02h",
          item.address,expected,item.data))
    end
  endfunction
  function void write_reset(reset_item item);
    enable=8'h01; maxpktsize=63;
    parity_count=0; length_count=0; illegal_count=0; last_length=0;
    foreach(addr_count[i]) addr_count[i]=0;
    foreach(packet_memory[i]) packet_memory[i]=0;
    foreach(scratch_memory[i]) scratch_memory[i]=0;
    if(regs!=null) regs.reset();
    reset_count++;
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("REFERENCE_STATS",$sformatf(
      "observed=%0d forwarded=%0d disabled=%0d illegal_addr=%0d length_drop=%0d resets=%0d",
      observed,forwarded,dropped[DROP_DISABLED],dropped[DROP_ADDRESS],dropped[DROP_LENGTH],reset_count),UVM_LOW)
    if(observed!=forwarded+dropped[DROP_DISABLED]+dropped[DROP_ADDRESS]+dropped[DROP_LENGTH])
      `uvm_error("ACCOUNTING","Reference accounting inconsistent")
  endfunction
endclass
