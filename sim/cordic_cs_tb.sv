`timescale 1ns/1ps
module cordic_cs_tb;

    localparam W          = 18;
    localparam ITERATIONS = 16;
    localparam TOLERANCE  = 5;

    // theta_in: Q2.15 (scale 32768)  -- same as cordic_at angle_out
    // cos_out/sin_out: Q1.16 (scale 65536) -- same as Stokes values

    reg                 clk, rst_n;
    reg  signed [W-1:0] theta_in;
    reg                 in_valid;
    wire signed [W-1:0] cos_out, sin_out;
    wire                out_valid;

    cordic_cs #(.W(W), .ITERATIONS(ITERATIONS)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .theta_in (theta_in),
        .in_valid (in_valid),
        .cos_out  (cos_out),
        .sin_out  (sin_out),
        .out_valid(out_valid)
    );

    always #5 clk = ~clk;

    task send;
        input signed [W-1:0] theta;
        @(posedge clk); #1;
        theta_in = theta;
        in_valid = 1;
        @(posedge clk); #1;
        in_valid = 0;
        @(posedge out_valid); #1;
    endtask

    task check;
        input signed [W-1:0] got, exp;
        input [8*20-1:0] label;
        if ($signed(got) - $signed(exp) > TOLERANCE || $signed(got) - $signed(exp) < -TOLERANCE)
            $display("FAIL %s: got %0d expected %0d", label, got, exp);
        else
            $display("PASS %s: got %0d expected %0d", label, got, exp);
    endtask

    initial begin

        clk = 0; rst_n = 0; theta_in = 0; in_valid = 0;
        #12; rst_n = 1; #3;

        // theta = 0: cos=1.0 (65536), sin=0
        send(18'sd0);
        check(cos_out, 18'sd65536, "cos theta=0    ");
        check(sin_out, 18'sd0,     "sin theta=0    ");

        // theta = pi/4 = 25736: cos=sin=1/sqrt(2) (46341)
        send(18'sd25736);
        check(cos_out, 18'sd46341, "cos theta=pi/4 ");
        check(sin_out, 18'sd46341, "sin theta=pi/4 ");

        // theta = pi/2 = 51472: boundary, no quadrant correction
        send(18'sd51472);
        check(cos_out, 18'sd0,     "cos theta=pi/2 ");
        check(sin_out, 18'sd65536, "sin theta=pi/2 ");

        // theta = 3pi/4 = 77208: quadrant II, quadrant correction applied
        send(18'sd77208);
        check(cos_out, -18'sd46341, "cos theta=3pi/4");
        check(sin_out,  18'sd46341, "sin theta=3pi/4");

        // theta = -pi/4 = -25736
        send(-18'sd25736);
        check(cos_out,  18'sd46341, "cos theta=-pi/4");
        check(sin_out, -18'sd46341, "sin theta=-pi/4");

        // theta = -3pi/4 = -77208: quadrant III, quadrant correction applied
        send(-18'sd77208);
        check(cos_out, -18'sd46341, "cos theta=-3pi/4");
        check(sin_out, -18'sd46341, "sin theta=-3pi/4");

        // theta = pi/6 = 17157: cos=sqrt(3)/2 (56755), sin=0.5 (32768)
        send(18'sd17157);
        check(cos_out, 18'sd56755, "cos theta=pi/6 ");
        check(sin_out, 18'sd32768, "sin theta=pi/6 ");

        $display("cordic_cs testbench done");
        $finish;
    end

endmodule
