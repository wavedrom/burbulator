// burbulator PoC testbench: A(src) -> top(DUT) -> C(sink), DPI-C.
module tb #(parameter DW = 64);

  import "DPI-C" function chandle  src_new(input int seed, input int bubble_pct,
                                           input int dw, input int ntxn);
  import "DPI-C" function void     src_tick(input chandle h, input bit accepted,
                                            output bit valid, output longint data);
  import "DPI-C" function longint  src_checksum(input chandle h);
  import "DPI-C" function int      src_count(input chandle h);
  import "DPI-C" function void     src_free(input chandle h);

  import "DPI-C" function chandle  snk_new(input int seed, input int backp_pct);
  import "DPI-C" function void     snk_tick(input chandle h, input bit valid,
                                            input longint data, output bit ready_next);
  import "DPI-C" function int      snk_done(input chandle h, input int ntxn);
  import "DPI-C" function longint  snk_checksum(input chandle h);
  import "DPI-C" function int      snk_count(input chandle h);
  import "DPI-C" function void     snk_free(input chandle h);

  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  // VCD dump (Verilator needs --trace; Questa/VCS honor $dumpvars directly)
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb);
  end

  // A -> DUT (upstream / target port)
  bit           t_req;
  logic [DW-1:0] t_dat;
  logic         t_ack;
  // DUT -> C (downstream / initiator port)
  logic         i_req;
  logic [DW-1:0] i_dat;
  bit           i_ack;

  top #(.DW(DW)) dut (
    .clk(clk), .rst(rst),
    .t_0_dat(t_dat), .t_0_req(t_req), .t_0_ack(t_ack),
    .i_0_dat(i_dat), .i_0_req(i_req), .i_0_ack(i_ack)
  );

  chandle sh, kh;
  int     seed = 1, ntxn = 1000, bubble = 20, backp = 20;
  bit     sv, mr, accepted;
  longint sd;

  initial begin
    void'($value$plusargs("seed=%d",   seed));
    void'($value$plusargs("ntxn=%d",   ntxn));
    void'($value$plusargs("bubble=%d", bubble));
    void'($value$plusargs("backp=%d",  backp));

    sh = src_new(seed, bubble, DW, ntxn);
    kh = snk_new(seed, backp);

    t_req = 0; t_dat = 0; i_ack = 0;
    repeat (3) @(posedge clk);
    rst = 0;                       // deassert after a few clocks
  end

  always @(posedge clk) if (!rst) begin
    // source: offer beat, sample its acceptance
    accepted = t_req & t_ack;
    src_tick(sh, accepted, sv, sd);
    t_req <= sv;
    t_dat <= sd[DW-1:0];

    // sink: consume + set next-cycle backpressure
    snk_tick(kh, i_req, i_dat, mr);
    i_ack <= mr;

    if (snk_done(kh, ntxn)) begin
      if (src_count(sh) == ntxn && snk_count(kh) == ntxn
          && src_checksum(sh) == snk_checksum(kh))
        $display("PASS ntxn=%0d bubble=%0d backp=%0d chk=%0h",
                 ntxn, bubble, backp, snk_checksum(kh));
      else
        $display("FAIL src_cnt=%0d snk_cnt=%0d src_chk=%0h snk_chk=%0h",
                 src_count(sh), snk_count(kh), src_checksum(sh), snk_checksum(kh));
      src_free(sh); snk_free(kh);
      $finish;
    end
  end

  // safety timeout
  initial begin
    repeat (100000) @(posedge clk);
    $display("FAIL timeout"); $finish;
  end

endmodule
