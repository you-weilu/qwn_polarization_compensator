// state_decoder_tb.sv
// Testbench for state_decoder. Feeds raw Stokes values
// into DUT and verifies output angles.

`timescale 1ns/1ps

module state_decoder_tb;

    localparam ADC_W    = 12;
    localparam STOKES_W = 18;
    localparam ANGLE_W  = 18;

    logic clk;
    logic rst_n;

    logic [ADC_W-1:0]   s1_raw;    // raw ADC sample (ADC_W-bit signed)
    logic [ADC_W-1:0]   s2_raw;
    logic [ADC_W-1:0]   s3_raw;
    logic               in_valid;

    logic [ANGLE_W-1:0] psi_out;   // ψ, signed fixed-point
    logic [ANGLE_W-1:0] chi_out;   // χ
    logic [ANGLE_W-1:0] delta_out; // δ
    logic               out_valid;

    // delayed Stokes outputs, must be valid on the same cycle as out_valid
    logic signed [STOKES_W-1:0] s1_out;
    logic signed [STOKES_W-1:0] s2_out;
    logic signed [STOKES_W-1:0] s3_out;

    // instantiate DUT
    state_decoder #(
        .ADC_W   (ADC_W),
        .STOKES_W(STOKES_W),
        .ANGLE_W (ANGLE_W)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .s1_raw   (s1_raw),
        .s2_raw   (s2_raw),
        .s3_raw   (s3_raw),
        .in_valid (in_valid),
        .psi_out  (psi_out),
        .chi_out  (chi_out),
        .delta_out(delta_out),
        .out_valid(out_valid),
        .s1_out   (s1_out),
        .s2_out   (s2_out),
        .s3_out   (s3_out)
    );

    // clock generation
    initial clk = 0;
    always #5 clk = ~clk; // 10ns period

    // ADC input scale: 12-bit signed, max positive = 2047 ≈ 1.0 normalized
    localparam ADC_MAX        = (1 << (ADC_W-1)) - 1; // 2047
    localparam ONE_OVER_SQRT2 = 1448; // round(2047 / sqrt(2)): equal s1=s2 or s2=s3 on sphere
    localparam ONE_OVER_SQRT3 = 1182; // round(2047 / sqrt(3)): equal s1=s2=s3 on sphere

    localparam ANGLE_SCALE    = 1 << (ANGLE_W-3); // 32768: Q2.15 counts per radian
    localparam TOLERANCE      = 3;                // CORDIC <= 0.5 counts + sqrt_lut < 1 count; 3 gives safe headroom

    // Stokes path is pure registered delay — no arithmetic, so expect exact values.
    // Scale factor: ADC is Q1.11 (scale 2^11), Stokes internal is Q1.16 (scale 2^16) => shift left by 5.
    localparam STOKES_SCALE = 1 << (STOKES_W - ADC_W - 1); // 32
    localparam STOKES_MAX   = ADC_MAX        * STOKES_SCALE; // 65504
    localparam STOKES_SQRT2 = ONE_OVER_SQRT2 * STOKES_SCALE; // 46336
    localparam STOKES_SQRT3 = ONE_OVER_SQRT3 * STOKES_SCALE; // 37824

    // check task: passes if got is within TOLERANCE of expected
    task check;
        input string               name;
        input signed [ANGLE_W-1:0] got;
        input integer              expected;
        if ($signed(got) >= (expected - TOLERANCE) &&
            $signed(got) <= (expected + TOLERANCE))
            $display("PASS %s: got %0d  expected %0d", name, $signed(got), expected);
        else
            $display("FAIL %s: got %0d  expected %0d", name, $signed(got), expected);
    endtask

    // check_stokes: exact match; Stokes delay pipeline has no rounding
    task check_stokes;
        input string                name;
        input signed [STOKES_W-1:0] got;
        input integer               expected;
        if ($signed(got) === expected)
            $display("PASS %s: got %0d  expected %0d", name, $signed(got), expected);
        else
            $display("FAIL %s: got %0d  expected %0d", name, $signed(got), expected);
    endtask

    // send task: apply one Stokes input vector and wait for result
    task send;
        input signed [ADC_W-1:0] s1v, s2v, s3v;
        @(posedge clk); #1;
        s1_raw = s1v; s2_raw = s2v; s3_raw = s3v; in_valid = 1;
        @(posedge clk); #1;
        in_valid = 0;
        @(posedge out_valid);
    endtask



    // expected angle values: round(angle_rad * 32768), then >>1 for psi/chi outputs
    // arctan(1)   = pi/4  -> 25736 cordic; psi/chi out = 12868
    // arctan(inf) = pi/2  -> 51472 cordic; psi/chi out = 25736
    // arctan(1/sqrt(2)) ~ 0.6155 rad -> 20168 cordic; chi out = 10084
    initial begin
        $dumpfile("sim/state_decoder_tb.vcd");
        $dumpvars(0, state_decoder_tb);
        rst_n = 0; s1_raw = 0; s2_raw = 0; s3_raw = 0; in_valid = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Linear horizontal: s1=1, s2=s3=0 -> psi=0, chi=0; delta=arctan(0/0) undefined, not checked
        send(ADC_MAX, 0, 0);
        check("psi  lin-H",   psi_out,    0);
        check("chi  lin-H",   chi_out,    0);
        check_stokes("s1 lin-H", s1_out, STOKES_MAX); check_stokes("s2 lin-H", s2_out, 0); check_stokes("s3 lin-H", s3_out, 0);

        // Linear 45 deg: s2=1, s1=s3=0 -> psi=pi/4, chi=0, delta=0
        send(0, ADC_MAX, 0);
        check("psi  lin-45",  psi_out,  25736);
        check("chi  lin-45",  chi_out,      0);
        check("delta lin-45", delta_out,    0);
        check_stokes("s1 lin-45", s1_out, 0); check_stokes("s2 lin-45", s2_out, STOKES_MAX); check_stokes("s3 lin-45", s3_out, 0);

        // Linear diagonal balanced: s1=s2=1/sqrt(2), s3=0 -> psi=pi/4, chi=0, delta=0
        send(ONE_OVER_SQRT2, ONE_OVER_SQRT2, 0);
        check("psi  sqrt2",   psi_out,  12868);
        check("chi  sqrt2",   chi_out,      0);
        check("delta sqrt2",  delta_out,    0);
        check_stokes("s1 sqrt2", s1_out, STOKES_SQRT2); check_stokes("s2 sqrt2", s2_out, STOKES_SQRT2); check_stokes("s3 sqrt2", s3_out, 0);

        // s2=s3=1/sqrt(2), s1=0 -> psi=pi/4, chi=pi/8, delta=pi/4
        send(0, ONE_OVER_SQRT2, ONE_OVER_SQRT2);
        check("psi  s2s3",    psi_out,  25736);
        check("chi  s2s3",    chi_out,  12868);
        check("delta s2s3",   delta_out,25736);
        check_stokes("s1 s2s3", s1_out, 0); check_stokes("s2 s2s3", s2_out, STOKES_SQRT2); check_stokes("s3 s2s3", s3_out, STOKES_SQRT2);

        // Equal Stokes: s1=s2=s3=1/sqrt(3) -> psi=pi/8, chi~0.308rad/2, delta=pi/4
        send(ONE_OVER_SQRT3, ONE_OVER_SQRT3, ONE_OVER_SQRT3);
        check("psi  sqrt3",   psi_out,  12868);
        check("chi  sqrt3",   chi_out,  10080);
        check("delta sqrt3",  delta_out,25736);
        check_stokes("s1 sqrt3", s1_out, STOKES_SQRT3); check_stokes("s2 sqrt3", s2_out, STOKES_SQRT3); check_stokes("s3 sqrt3", s3_out, STOKES_SQRT3);

        $finish;
    end

endmodule