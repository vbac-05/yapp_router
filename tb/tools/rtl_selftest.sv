// Standalone RTL checks for machines without a licensed UVM simulator.
// This is supplemental validation; the UVM testbench remains the learning target.
module rtl_selftest;
  timeunit 1ns; timeprecision 1ps;
  logic clock=0, reset=0;
  always #5 clock=~clock;
  logic [7:0] in_data=0;
  logic in_data_vld=0;
  wire in_suspend, error;
  wire [7:0] data[0:2];
  wire [2:0] valid;
  logic [2:0] suspend=0;
  logic [15:0] haddr=0;
  logic [7:0] hwrite_data=0;
  logic hen=0, hwr_rd=0;
  wire [7:0] hdata;
  assign hdata=hen && hwr_rd && !reset ? hwrite_data : 8'hzz;
  yapp_router dut(.clock,.reset,.in_data,.in_data_vld,.in_suspend,.error,
    .data_0(data[0]),.data_1(data[1]),.data_2(data[2]),
    .data_vld_0(valid[0]),.data_vld_1(valid[1]),.data_vld_2(valid[2]),
    .suspend_0(suspend[0]),.suspend_1(suspend[1]),.suspend_2(suspend[2]),
    .haddr,.hdata,.hen,.hwr_rd);
  logic [7:0] expected[0:2][0:32767];
  integer head[0:2],tail[0:2];
  integer checked=0, packets=0, dropped=0, error_pulses=0, stalls=0;
  integer length_limit=63;
  logic [7:0] enable=8'h01;
  logic [7:0] address_count[0:2], bad_count=0, length_count=0, illegal_count=0;
  logic [7:0] last_packet[0:63];
  integer last_length=0;
  bit random_backpressure=0;
  bit corrupt_output=0;
  logic [2:0] forced_suspend=0;
  integer mon_index=-1,mon_length=0;
  bit mon_routed=0;
  logic [7:0] mon_parity=0;
  logic error_expected=0;
  bit reset_seen=0;

  always @(negedge clock) begin
    #1;
    if(random_backpressure)
      suspend=forced_suspend | {$urandom_range(0,1)==1,$urandom_range(0,1)==1,$urandom_range(0,1)==1};
    else suspend=forced_suspend;
  end

  always @(posedge clock) begin
    if(reset) begin
      mon_index=-1; error_expected=0; reset_seen=1;
    end else if(reset_seen) begin
      if(error !== error_expected) $fatal(1,"PARITY_SIGNAL expected=%b actual=%b",error_expected,error);
      if(error) error_pulses++;
      error_expected=0;
      if(in_suspend) stalls++;
      if(!in_suspend) begin
        if(mon_index==-1 && in_data_vld) begin
          mon_length=in_data[7:2]; mon_index=0; mon_parity=in_data;
          mon_routed=enable[0] && in_data[1:0]!=3 && mon_length>0 && mon_length<=length_limit;
        end else if(mon_index>=0 && mon_index<mon_length) begin
          mon_parity^=in_data; mon_index++;
        end else if(mon_index>=0) begin
          error_expected=mon_routed && in_data!=mon_parity;
          mon_index=-1;
        end
      end
      for(integer c=0;c<3;c++) begin
        if(valid[c] && !suspend[c]) begin
          if(head[c]>=tail[c]) $fatal(1,"UNEXPECTED output channel=%0d data=%h",c,data[c]);
          if(data[c]!==expected[c][head[c]])
            $fatal(1,"DATA_MISMATCH channel=%0d index=%0d expected=%h actual=%h",c,head[c],expected[c][head[c]],data[c]);
          head[c]++; checked++;
        end
      end
    end
  end

  task automatic bus_write(input logic [15:0] addr,input logic [7:0] value);
    @(negedge clock); #2;
    haddr=addr; hwrite_data=value; hen=1; hwr_rd=1;
    @(negedge clock); #2; hen=0; hwr_rd=0;
    if(addr==16'h1000) length_limit=value[5:0];
    if(addr==16'h1001) enable=value & 8'hf7;
    @(posedge clock);
  endtask
  task automatic bus_check(input logic [15:0] addr,input logic [7:0] expected_value);
    @(negedge clock); #2; haddr=addr; hen=1; hwr_rd=0;
    repeat(2) @(posedge clock);
    if(hdata!==expected_value)
      $fatal(1,"HBUS_MISMATCH addr=%h expected=%h actual=%h",addr,expected_value,hdata);
    @(negedge clock); #2; hen=0;
    @(posedge clock);
  endtask
  task automatic drive_byte(input logic [7:0] value,input bit is_payload);
    @(negedge clock); #2; in_data=value; in_data_vld=is_payload;
    @(posedge clock);
    while(in_suspend) @(posedge clock);
  endtask
  task automatic send_packet(input integer addr,input integer length,input bit bad=0);
    logic [7:0] bytes[0:64];
    logic [7:0] parity;
    bit route;
    bytes[0]={6'(length),2'(addr)}; parity=bytes[0];
    for(integer i=1;i<=length;i++) begin
      bytes[i]=8'((i*37) ^ packets ^ addr); parity^=bytes[i];
    end
    if(bad) parity^=8'h01;
    route=enable[0] && addr<3 && length>0 && length<=length_limit;
    if(route) begin
      for(integer i=0;i<=length;i++) begin expected[addr][tail[addr]]=bytes[i]; tail[addr]++; end
      expected[addr][tail[addr]]=parity ^ (corrupt_output ? 8'h01 : 8'h00); tail[addr]++;
      corrupt_output=0;
    end else dropped++;
    if(enable[0]) begin
      last_length=length;
      for(integer i=0;i<=length;i++) last_packet[i]=bytes[i];
      if(addr==3) begin if(enable[7]) illegal_count++; end
      else if(length==0 || length>length_limit) begin if(enable[2]) length_count++; end
      else begin
        if(enable[4+addr]) address_count[addr]++;
        if(bad && enable[1]) bad_count++;
      end
    end
    drive_byte(bytes[0],1);
    for(integer i=1;i<=length;i++) drive_byte(bytes[i],1);
    drive_byte(parity,0);
    @(negedge clock); #2; in_data=0; in_data_vld=0;
    packets++;
  endtask
  task automatic drain();
    integer cycles;
    cycles=0;
    while(head[0]!=tail[0] || head[1]!=tail[1] || head[2]!=tail[2]) begin
      @(negedge clock); cycles++;
      if(cycles>4000) $fatal(1,"DRAIN_TIMEOUT");
    end
    repeat(5) @(negedge clock);
  endtask
  task automatic check_counters();
    bus_check(16'h1004,bad_count); bus_check(16'h1005,length_count);
    bus_check(16'h1006,illegal_count);
    for(integer c=0;c<3;c++) bus_check(16'h1009+16'(c),address_count[c]);
  endtask
  task automatic do_reset();
    @(negedge clock); #2; reset=1; in_data_vld=0; in_data=0; hen=0;
    for(integer c=0;c<3;c++) begin head[c]=0; tail[c]=0; address_count[c]=0; end
    for(integer i=0;i<64;i++) last_packet[i]=0;
    enable=1; length_limit=63; bad_count=0; length_count=0; illegal_count=0; last_length=0;
    repeat(5) @(negedge clock);
    #2; reset=0;
  endtask
  initial begin
    integer seed, ignored;
    seed=1;
    ignored=$value$plusargs("SEED=%d",seed);
    ignored=$urandom(seed);
    do_reset();
    bus_check(16'h1000,63); bus_check(16'h1001,1); check_counters();
    for(integer i=0;i<64;i++) bus_check(16'h1010+16'(i),0);
    for(integer i=0;i<256;i++) bus_check(16'h1100+16'(i),0);
    if($test$plusargs("NEGATIVE_SCOREBOARD")) corrupt_output=1;
    for(integer c=0;c<3;c++) send_packet(c,8);
    bus_write(16'h1001,8'hff); bus_check(16'h1001,8'hf7);
    random_backpressure=1;
    for(integer c=0;c<3;c++) begin
      send_packet(c,1); send_packet(c,15); send_packet(c,16);
      send_packet(c,17); send_packet(c,63); send_packet(c,8,1);
    end
    bus_write(16'h1000,20);
    for(integer c=0;c<3;c++) begin send_packet(c,20); send_packet(c,21); send_packet(c,0); end
    send_packet(3,8); send_packet(3,63);
    bus_write(16'h1001,8'hf6);
    send_packet(0,8); send_packet(1,63); send_packet(3,8);
    bus_write(16'h1001,8'hf7); bus_write(16'h1000,63);
    // Force FIFO-full input suspension, then release the receiver.
    forced_suspend=3'b001;
    fork
      send_packet(0,63,1);
      begin repeat(100) @(negedge clock); forced_suspend=0; end
    join
    for(integer i=0;i<200;i++) send_packet($urandom_range(0,3),$urandom_range(0,63),$urandom_range(0,1));
    drain(); check_counters();
    bus_write(16'h1009,8'haa); bus_check(16'h1009,address_count[0]);
    bus_check(16'h100d,8'(last_length));
    for(integer i=0;i<=last_length;i++) bus_check(16'h1010+16'(i),last_packet[i]);
    for(integer i=0;i<256;i++) bus_write(16'h1100+16'(i),8'(i^8'ha5));
    for(integer i=0;i<256;i++) bus_check(16'h1100+16'(i),8'(i^8'ha5));
    do_reset();
    bus_write(16'h1001,8'hf7);
    for(integer i=0;i<260;i++) send_packet(0,1);
    drain(); check_counters(); bus_check(16'h1009,4);
    // Start an incomplete packet while the receiver is blocked, then abort it.
    forced_suspend=3'b111;
    drive_byte({6'd63,2'd0},1); drive_byte(8'ha5,1); drive_byte(8'h5a,1);
    do_reset(); forced_suspend=0;
    for(integer c=0;c<3;c++) send_packet(c,8);
    drain(); check_counters();
    if(stalls==0 || error_pulses==0) $fatal(1,"VACUOUS: stalls/parity errors were not tested");
    $display("RTL_SELFTEST_PASS packets=%0d dropped=%0d bytes_checked=%0d parity_pulses=%0d stalled_cycles=%0d",
      packets,dropped,checked,error_pulses,stalls);
    $finish;
  end
  initial begin #5000000; $fatal(1,"GLOBAL_TIMEOUT"); end
endmodule
