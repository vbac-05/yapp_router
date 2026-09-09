`uvm_analysis_imp_decl(_expected)
`uvm_analysis_imp_decl(_ch0)
`uvm_analysis_imp_decl(_ch1)
`uvm_analysis_imp_decl(_ch2)

class router_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(router_scoreboard)
  uvm_analysis_imp_expected #(yapp_packet,router_scoreboard) expected_imp;
  uvm_analysis_imp_ch0 #(yapp_packet,router_scoreboard) ch0_imp;
  uvm_analysis_imp_ch1 #(yapp_packet,router_scoreboard) ch1_imp;
  uvm_analysis_imp_ch2 #(yapp_packet,router_scoreboard) ch2_imp;
  uvm_analysis_imp_reset #(reset_item,router_scoreboard) reset_imp;
  uvm_analysis_port #(yapp_packet) matched_ap;
  typedef yapp_packet packet_queue_t[$];
  packet_queue_t expected[3];
  int unsigned received=0, flushed=0;
  int unsigned matched[3]='{default:0}, mismatched[3]='{default:0}, unexpected[3]='{default:0};
  bit inject_fault=0, fault_injected=0;
  function new(string name, uvm_component parent);
    super.new(name,parent);
    expected_imp=new("expected_imp",this);
    ch0_imp=new("ch0_imp",this); ch1_imp=new("ch1_imp",this); ch2_imp=new("ch2_imp",this);
    reset_imp=new("reset_imp",this);
    matched_ap=new("matched_ap",this);
  endfunction
  function void write_expected(yapp_packet packet);
    yapp_packet copy;
    if(packet.addr>2) `uvm_fatal("REFERENCE_BAD_ADDR","Invalid expected packet address")
    if(!$cast(copy,packet.clone())) `uvm_fatal("CLONE","Packet clone failed")
    if(inject_fault && !fault_injected) begin copy.parity^=8'h01; fault_injected=1; end
    expected[copy.addr].push_back(copy);
    received++;
  endfunction
  function void compare_channel(int channel_id, yapp_packet actual);
    yapp_packet exp;
    if(expected[channel_id].size()==0) begin
      unexpected[channel_id]++;
      `uvm_error("UNEXPECTED_PACKET",$sformatf("channel=%0d %s",channel_id,actual.convert2string()))
      return;
    end
    // Consume exactly one expectation for every observation, even on mismatch.
    exp=expected[channel_id].pop_front();
    if(!exp.compare(actual)) begin
      mismatched[channel_id]++;
      `uvm_error("PACKET_MISMATCH",$sformatf("channel=%0d expected={%s} actual={%s}",
        channel_id,exp.convert2string(),actual.convert2string()))
    end else begin matched[channel_id]++; matched_ap.write(actual); end
  endfunction
  function void write_ch0(yapp_packet packet); compare_channel(0,packet); endfunction
  function void write_ch1(yapp_packet packet); compare_channel(1,packet); endfunction
  function void write_ch2(yapp_packet packet); compare_channel(2,packet); endfunction
  function int unsigned pending();
    return expected[0].size()+expected[1].size()+expected[2].size();
  endfunction
  function void write_reset(reset_item item);
    flushed+=pending();
    foreach(expected[i]) expected[i].delete();
  endfunction
  function void check_phase(uvm_phase phase);
    if(pending()!=0) `uvm_error("MISSING_PACKET",$sformatf("%0d packets never arrived",pending()))
    if(received != matched.sum()+mismatched.sum()+flushed+pending())
      `uvm_error("ACCOUNTING","Scoreboard accounting inconsistent")
  endfunction
  function void report_phase(uvm_phase phase);
    `uvm_info("SCOREBOARD_STATS",$sformatf(
      "expected=%0d matched=%0d mismatched=%0d unexpected=%0d reset_flushed=%0d pending=%0d",
      received,matched.sum(),mismatched.sum(),unexpected.sum(),flushed,pending()),UVM_LOW)
  endfunction
endclass
