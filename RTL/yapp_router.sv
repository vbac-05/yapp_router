// Clean learning DUT derived from the documented YAPP behavior.
// This is new RTL, NOT a patched or certified Cadence router implementation.
// All transfers are accepted on posedge clock. Outputs use a FWFT FIFO.
module yapp_router (
  input  logic       clock, reset,
  input  logic [7:0] in_data,
  input  logic       in_data_vld,
  output logic       in_suspend,
  output logic       error,
  output logic [7:0] data_0, data_1, data_2,
  output logic       data_vld_0, data_vld_1, data_vld_2,
  input  logic       suspend_0, suspend_1, suspend_2,
  input  logic [15:0] haddr,
  inout  wire  [7:0] hdata,
  input  logic       hen, hwr_rd
);
  typedef enum logic [1:0] {HEADER, PAYLOAD, PARITY} state_t;
  state_t state;
  logic [5:0] maxpktsize, remaining;
  logic [7:0] enables, parity_accum;
  logic [1:0] destination;
  logic route_packet;
  logic [6:0] packet_index;
  logic [7:0] parity_count, oversized_count, illegal_count;
  logic [7:0] addr_count [0:2];
  logic [7:0] packet_memory [0:63]; // Header + up to 63 payload bytes; no parity.
  logic [7:0] scratch_memory [0:255];
  logic [5:0] last_length;
  logic [2:0] fifo_push, fifo_pop, fifo_full, fifo_empty;
  wire [7:0] fifo_data [0:2];
  logic accepted_header, valid_header, accepted_byte;
  logic [7:0] hread_data;
  logic hread_valid;

  assign valid_header = enables[0] && in_data[1:0] != 2'b11 &&
                        in_data[7:2] != 0 && in_data[7:2] <= maxpktsize;
  always_comb begin
    in_suspend = 1'b0;
    if (!reset) begin
      if (state == HEADER && in_data_vld && valid_header)
        in_suspend = fifo_full[in_data[1:0]];
      else if (state != HEADER && route_packet)
        in_suspend = fifo_full[destination];
    end
  end
  assign accepted_header = !reset && state == HEADER && in_data_vld && !in_suspend;
  assign accepted_byte = !reset && !in_suspend && (state != HEADER || in_data_vld);

  always_comb begin
    fifo_push = '0;
    if (accepted_header && valid_header)
      fifo_push[in_data[1:0]] = 1'b1;
    else if (accepted_byte && state != HEADER && route_packet)
      fifo_push[destination] = 1'b1;
  end
  assign fifo_pop = {data_vld_2 && !suspend_2,
                     data_vld_1 && !suspend_1,
                     data_vld_0 && !suspend_0};
  assign data_0 = fifo_data[0];
  assign data_1 = fifo_data[1];
  assign data_2 = fifo_data[2];
  assign data_vld_0 = !reset && !fifo_empty[0];
  assign data_vld_1 = !reset && !fifo_empty[1];
  assign data_vld_2 = !reset && !fifo_empty[2];
  for (genvar c = 0; c < 3; c++) begin : channels
    yapp_fifo fifo (.clock, .reset, .push(fifo_push[c]), .pop(fifo_pop[c]),
      .data_in(in_data), .data_out(fifo_data[c]),
      .full(fifo_full[c]), .empty(fifo_empty[c]));
  end

  // Register bus: WRITE = one enabled cycle, READ = two enabled cycles.
  // The slave releases the bidirectional bus unless a read is in progress.
  assign hdata = hen && !hwr_rd && hread_valid && !reset ? hread_data : 8'hzz;
  function automatic logic [7:0] read_address(input logic [15:0] address);
    case (address)
      16'h1000: return {2'b00, maxpktsize};
      16'h1001: return enables;
      16'h1004: return parity_count;
      16'h1005: return oversized_count;
      16'h1006: return illegal_count;
      16'h1009: return addr_count[0];
      16'h100a: return addr_count[1];
      16'h100b: return addr_count[2];
      16'h100d: return {2'b00, last_length};
      default: begin
        if (address >= 16'h1010 && address <= 16'h104f)
          return packet_memory[address - 16'h1010];
        if (address >= 16'h1100 && address <= 16'h11ff)
          return scratch_memory[address - 16'h1100];
        return 8'h00; // Defined learning-project behavior for unmapped addresses.
      end
    endcase
  endfunction

  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      maxpktsize <= 6'd63;
      enables <= 8'h01;
      hread_data <= '0;
      hread_valid <= 1'b0;
      for (int i = 0; i < 256; i++) scratch_memory[i] <= '0;
    end else begin
      if (hen && !hwr_rd) begin
        if (!hread_valid) hread_data <= read_address(haddr);
        hread_valid <= 1'b1;
      end else hread_valid <= 1'b0;
      if (hen && hwr_rd) begin
        case (haddr)
          16'h1000: maxpktsize <= hdata[5:0];
          16'h1001: enables <= hdata & 8'hf7; // Bit 3 is reserved, reads zero.
          default: begin
            if (haddr >= 16'h1100 && haddr <= 16'h11ff) begin
`ifdef INJECT_ERROR
              scratch_memory[haddr - 16'h1100] <= haddr == 16'h110f ? ~hdata : hdata;
`else
              scratch_memory[haddr - 16'h1100] <= hdata;
`endif
            end
          end
        endcase
      end
    end
  end

  // Policy is latched at the header; tests change control only between packets.
  // Drop precedence: disabled -> address -> length. Bad parity is forwarded.
  // Counters wrap modulo 256. Reset aborts packets and flushes all channel FIFOs.
  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      state <= HEADER;
      remaining <= '0;
      destination <= '0;
      route_packet <= 1'b0;
      parity_accum <= '0;
      packet_index <= '0;
      error <= 1'b0;
      parity_count <= '0;
      oversized_count <= '0;
      illegal_count <= '0;
      last_length <= '0;
      for (int c = 0; c < 3; c++) addr_count[c] <= '0;
      for (int i = 0; i < 64; i++) packet_memory[i] <= '0;
    end else begin
      error <= 1'b0;
      if (accepted_byte) begin
        case (state)
          HEADER: begin
            destination <= in_data[1:0];
            remaining <= in_data[7:2];
            parity_accum <= in_data;
            route_packet <= valid_header;
            packet_index <= 1;
            if (in_data[7:2] == 0) state <= PARITY;
            else state <= PAYLOAD;
            if (enables[0]) begin
              last_length <= in_data[7:2];
              packet_memory[0] <= in_data;
              if (in_data[1:0] == 3) begin
                if (enables[7]) illegal_count <= illegal_count + 1'b1;
              end else if (in_data[7:2] == 0 || in_data[7:2] > maxpktsize) begin
                if (enables[2]) oversized_count <= oversized_count + 1'b1;
              end else if (enables[4 + in_data[1:0]])
                addr_count[in_data[1:0]] <= addr_count[in_data[1:0]] + 1'b1;
            end
          end
          PAYLOAD: begin
            parity_accum <= parity_accum ^ in_data;
            if (enables[0]) packet_memory[packet_index] <= in_data;
            packet_index <= packet_index + 1'b1;
            remaining <= remaining - 1'b1;
            if (remaining == 1) state <= PARITY;
          end
          PARITY: begin
            if (route_packet && in_data != parity_accum) begin
              error <= 1'b1;
              if (enables[1]) parity_count <= parity_count + 1'b1;
            end
            state <= HEADER;
            route_packet <= 1'b0;
          end
          default: state <= HEADER;
        endcase
      end
    end
  end
endmodule
