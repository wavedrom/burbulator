// poc2 testbench: 2 independent sources + 2 independent sinks around radix2.
//   radix2:  x = a + b,  y = a - b   (per matched beat, DW-wrapped)
// Verifies multiple independent src/snk chandle instances + a reference model.
module tb #(parameter DW = 32);

  import "DPI-C" function chandle  src_new(input int seed, input int bubble_pct,
                                           input int dw, input int ntxn);
  import "DPI-C" function void     src_tick(input chandle h, input bit accepted,
                                            output bit valid, output longint data);
  import "DPI-C" function int      src_count(input chandle h);
  import "DPI-C" function void     src_free(input chandle h);

  import "DPI-C" function chandle  snk_new(input int seed, input int backp_pct);
  import "DPI-C" function void     snk_tick(input chandle h, input bit valid,
                                            input longint data, output bit ready_next);
  import "DPI-C" function int      snk_done(input chandle h, input int ntxn);
  import "DPI-C" function longint  snk_checksum(input chandle h);
  import "DPI-C" function int      snk_count(input chandle h);
  import "DPI-C" function void     snk_free(input chandle h);

  import "DPI-C" function longint  combine_ref(input int seedA, input int seedB,
                                               input int ntxn, input int op);

  logic clk = 0, reset_n = 0;
  always #5 clk = ~clk;

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb);
  end

  // sources -> targets a,b
  bit           t_a_req, t_b_req;
  logic [DW-1:0] t_a_dat, t_b_dat;
  logic         t_a_ack, t_b_ack;
  // initiators x,y -> sinks
  logic         i_x_req, i_y_req;
  logic [DW-1:0] i_x_dat, i_y_dat;
  bit           i_x_ack, i_y_ack;

  radix2 dut (
    .clk(clk), .reset_n(reset_n),
    .t_a_dat(t_a_dat), .t_a_req(t_a_req), .t_a_ack(t_a_ack),
    .t_b_dat(t_b_dat), .t_b_req(t_b_req), .t_b_ack(t_b_ack),
    .i_x_dat(i_x_dat), .i_x_req(i_x_req), .i_x_ack(i_x_ack),
    .i_y_dat(i_y_dat), .i_y_req(i_y_req), .i_y_ack(i_y_ack)
  );

  chandle sa, sb, kx, ky;
  int     seed = 1, ntxn = 1000, bubble = 20, backp = 20, seedA, seedB;
  bit     ava, avb, mrx, mry, acc_a, acc_b;
  longint da, db;

  initial begin
    void'($value$plusargs("seed=%d",   seed));
    void'($value$plusargs("ntxn=%d",   ntxn));
    void'($value$plusargs("bubble=%d", bubble));
    void'($value$plusargs("backp=%d",  backp));
    seedA = seed;
    seedB = seed ^ 32'h5eed;          // distinct, independent stream

    sa = src_new(seedA, bubble, DW, ntxn);
    sb = src_new(seedB, bubble, DW, ntxn);
    kx = snk_new(seedA,  backp);       // sink seeds only pick backpressure stream
    ky = snk_new(seedB,  backp);

    t_a_req = 0; t_b_req = 0; i_x_ack = 0; i_y_ack = 0;
    repeat (3) @(posedge clk);
    reset_n = 1;
  end

  always @(posedge clk) if (reset_n) begin
    // two independent sources
    acc_a = t_a_req & t_a_ack;
    acc_b = t_b_req & t_b_ack;
    src_tick(sa, acc_a, ava, da);  t_a_req <= ava;  t_a_dat <= da[DW-1:0];
    src_tick(sb, acc_b, avb, db);  t_b_req <= avb;  t_b_dat <= db[DW-1:0];

    // two independent sinks
    snk_tick(kx, i_x_req, i_x_dat, mrx);  i_x_ack <= mrx;
    snk_tick(ky, i_y_req, i_y_dat, mry);  i_y_ack <= mry;

    if (snk_done(kx, ntxn) && snk_done(ky, ntxn)) begin
      automatic longint ex = combine_ref(seedA, seedB, ntxn, 0); // a+b
      automatic longint ey = combine_ref(seedA, seedB, ntxn, 1); // a-b
      if (snk_count(kx) == ntxn && snk_count(ky) == ntxn
          && snk_checksum(kx) == ex && snk_checksum(ky) == ey)
        $display("PASS ntxn=%0d bubble=%0d backp=%0d  x_chk=%0h y_chk=%0h",
                 ntxn, bubble, backp, snk_checksum(kx), snk_checksum(ky));
      else
        $display("FAIL x:%0h/%0h y:%0h/%0h cnt %0d/%0d",
                 snk_checksum(kx), ex, snk_checksum(ky), ey,
                 snk_count(kx), snk_count(ky));
      src_free(sa); src_free(sb); snk_free(kx); snk_free(ky);
      $finish;
    end
  end

  initial begin
    repeat (200000) @(posedge clk);
    $display("FAIL timeout kx=%0d ky=%0d", snk_count(kx), snk_count(ky));
    $finish;
  end

endmodule
