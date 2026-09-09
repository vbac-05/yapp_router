`uvm_analysis_imp_decl(_route)

// The clean DUT produces its parity-error pulse at parity acceptance.
// A #1step monitor sees the registered pulse at the NEXT sampling edge.
class router_error_checker extends uvm_component;
  `uvm_component_utils(router_error_checker)
  uvm_analysis_imp_route #(route_event,router_error_checker) route_imp;
  uvm_analysis_imp_reset #(reset_item,router_error_checker) reset_imp;
  virtual yapp_if vif;
  typedef struct {time packet_finished; bit expected;} expectation_t;
  expectation_t expectations[$];
  int unsigned pulses_checked=0;
  bit reset_seen=0;
  function new(string name, uvm_component parent);
    super.new(name,parent); route_imp=new("route_imp",this); reset_imp=new("reset_imp",this);
  endfunction
  function void write_route(route_event t);
    expectation_t e;
    e.packet_finished=t.packet.observed_at;
    e.expected=t.reason==ROUTE_OK && t.packet.parity_kind==PARITY_BAD;
    expectations.push_back(e);
  endfunction
  function void write_reset(reset_item t); expectations.delete(); reset_seen=1; endfunction
  task run_phase(uvm_phase phase);
    expectation_t e;
    bit expect_error;
    forever begin
      @(vif.mon_cb);
      if(reset_seen && !vif.mon_cb.reset) begin
        expect_error=0;
        if(expectations.size()!=0 && expectations[0].packet_finished < $time) begin
          e=expectations.pop_front(); expect_error=e.expected;
          if(e.expected) pulses_checked++;
        end
        if(vif.mon_cb.error !== expect_error)
          `uvm_error("PARITY_SIGNAL",$sformatf("expected error=%0b observed=%0b",expect_error,vif.mon_cb.error))
      end
    end
  endtask
  function void check_phase(uvm_phase phase);
    if(expectations.size()!=0) `uvm_error("PARITY_PENDING","Error expectations remain unchecked")
  endfunction
endclass
