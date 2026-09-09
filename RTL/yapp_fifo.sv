// Educational FIFO: first-word fall-through, one writer and one reader.
module yapp_fifo #(
  parameter int DEPTH = 16,
  parameter int PTR_W = DEPTH > 1 ? $clog2(DEPTH) : 1
) (
  input  logic       clock, reset,
  input  logic       push, pop,
  input  logic [7:0] data_in,
  output logic [7:0] data_out,
  output logic       full, empty
);
  logic [7:0] storage [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr, rd_ptr;
  logic [PTR_W:0] count;
  logic do_push, do_pop;

  assign full = (count == DEPTH);
  assign empty = (count == 0);
  assign do_pop = pop && !empty;
  // Conservative full handling: a full FIFO accepts a new byte next cycle.
  assign do_push = push && !full;
  assign data_out = empty ? 8'h00 : storage[rd_ptr];

  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count <= '0;
    end else begin
      if (do_push) begin
        storage[wr_ptr] <= data_in;
        wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1'b1;
      end
      if (do_pop)
        rd_ptr <= (rd_ptr == DEPTH-1) ? '0 : rd_ptr + 1'b1;
      case ({do_push, do_pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
