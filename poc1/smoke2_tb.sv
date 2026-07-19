// smoke2: per-instance context via chandle + two independent instances.
// DPI-C only (Icarus dropped). chandle native on Verilator/Questa/VCS.
module tb;
  import "DPI-C" function chandle  ctr_new(input int seed);
  import "DPI-C" function longint  ctr_next(input chandle h);
  import "DPI-C" function void     ctr_free(input chandle h);

  chandle a, b;
  longint va, vb;

  initial begin
    a = ctr_new(10);    // step 11: 21,32,...
    b = ctr_new(100);   // step 101: 201,302,...

    va = ctr_next(a); vb = ctr_next(b);
    $display("a=%0d b=%0d (want 21 201)", va, vb);
    va = ctr_next(a); vb = ctr_next(b);
    $display("a=%0d b=%0d (want 32 302)", va, vb);

    if (va == 32 && vb == 302) $display("SMOKE2 PASS");
    else                       $display("SMOKE2 FAIL");

    ctr_free(a); ctr_free(b);
    $finish;
  end
endmodule
