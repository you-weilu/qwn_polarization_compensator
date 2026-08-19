// threshold_checker_tb.sv
// Testbench for threshold_checker. Sends V and D pass results and
// verifies correction_needed is asserted correctly.

`timescale 1ns/1ps

module threshold_checker_tb;

    localparam ANGLE_W     = 18;
    localparam PSI_V_IDEAL = 18'sd51472;
    localparam PSI_D_IDEAL = 18'sd25736;
    localparam CHI_IDEAL   = 18'sd0;
    localparam THRESHOLD   = 18'sd5726;    // 10 deg in Q2.15
    localparam TOLERANCE   = 0;            // output is a single bit, exact match only

    logic                      clk;
    logic                      rst_n;
    logic signed [ANGLE_W-1:0] psi;
    logic signed [ANGLE_W-1:0] chi;
    logic                      pass_sel;
    logic                      valid;
    logic                      correction_needed;

    threshold_checker #(
        .ANGLE_W    (ANGLE_W),
        .PSI_V_IDEAL(PSI_V_IDEAL),
        .PSI_D_IDEAL(PSI_D_IDEAL),
        .CHI_IDEAL  (CHI_IDEAL),
        .THRESHOLD  (THRESHOLD)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .psi              (psi),
        .chi              (chi),
        .pass_sel         (pass_sel),
        .valid            (valid),
        .correction_needed(correction_needed)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // check task: verify correction_needed matches expected one cycle after D pass
    task check;
        input string name;
        input        expected;
        @(posedge clk); #1;
        if (correction_needed === expected)
            $display("PASS %s: correction_needed=%0b", name, correction_needed);
        else
            $display("FAIL %s: got=%0b  expected=%0b", name, correction_needed, expected);
    endtask

    // send task: drive one V pass then one D pass, then check result
    task send;
        input signed [ANGLE_W-1:0] psi_v, chi_v;  // V pass angles
        input signed [ANGLE_W-1:0] psi_d, chi_d;  // D pass angles
        // V pass
        @(posedge clk); #1;
        psi = psi_v; chi = chi_v; pass_sel = 1; valid = 1;
        @(posedge clk); #1;
        valid = 0;
        // D pass
        @(posedge clk); #1;
        psi = psi_d; chi = chi_d; pass_sel = 0; valid = 1;
        @(posedge clk); #1;
        valid = 0;
    endtask

    initial begin
        $dumpfile("sim/threshold_checker_tb.vcd");
        $dumpvars(0, threshold_checker_tb);

        rst_n = 0; psi = 0; chi = 0; pass_sel = 0; valid = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // both V and D ideal: no correction needed
        send(PSI_V_IDEAL, CHI_IDEAL, PSI_D_IDEAL, CHI_IDEAL);
        check("ideal V and D", 0);

        // V psi just inside upper threshold boundary: no correction
        send(PSI_V_IDEAL + THRESHOLD, CHI_IDEAL, PSI_D_IDEAL, CHI_IDEAL);
        check("V psi at upper boundary", 0);

        // V psi just over upper threshold: correction needed
        send(PSI_V_IDEAL + THRESHOLD + 1, CHI_IDEAL, PSI_D_IDEAL, CHI_IDEAL);
        check("V psi over upper boundary", 1);

        // V psi just inside lower threshold boundary: no correction
        send(PSI_V_IDEAL - THRESHOLD, CHI_IDEAL, PSI_D_IDEAL, CHI_IDEAL);
        check("V psi at lower boundary", 0);

        // V psi just under lower threshold: correction needed
        send(PSI_V_IDEAL - THRESHOLD - 1, CHI_IDEAL, PSI_D_IDEAL, CHI_IDEAL);
        check("V psi under lower boundary", 1);

        // D psi over threshold: correction needed
        send(PSI_V_IDEAL, CHI_IDEAL, PSI_D_IDEAL + THRESHOLD + 1, CHI_IDEAL);
        check("D psi over threshold", 1);

        // V chi over threshold: correction needed
        send(PSI_V_IDEAL, THRESHOLD + 1, PSI_D_IDEAL, CHI_IDEAL);
        check("V chi over threshold", 1);

        // D chi under threshold (negative): correction needed
        send(PSI_V_IDEAL, CHI_IDEAL, PSI_D_IDEAL, -(THRESHOLD + 1));
        check("D chi under threshold", 1);

        // both V and D at maximum drift (worst case): correction needed
        send(PSI_V_IDEAL + THRESHOLD + 1, THRESHOLD + 1,
             PSI_D_IDEAL + THRESHOLD + 1, THRESHOLD + 1);
        check("all angles over threshold", 1);

        $finish;
    end

endmodule
