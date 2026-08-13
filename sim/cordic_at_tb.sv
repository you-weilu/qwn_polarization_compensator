// cordic_at_tb.sv
// Testbench for cordic_at. Feeds known (x, y) pairs and checks angle_out
// against hand-calculated arctan(y/x) values.

`timescale 1ns/1ps

module cordic_at_tb;

    parameter W = 18;

    // inputs to DUT
    logic             clk;
    logic             rst_n;
    logic signed [W-1:0] x_in;
    logic signed [W-1:0] y_in;
    logic             in_valid;

    // outputs from DUT
    logic signed [W-1:0] angle_out;
    logic             out_valid;

    // Instantiate DUT
    cordic_at #(.W(W)) DUT (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (x_in),
        .y_in     (y_in),
        .in_valid (in_valid),
        .angle_out(angle_out),
        .out_valid(out_valid)
    );

    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;


    // Q1.16 scale for inputs, Q2.15 scale for angle output
    localparam SCALE          = 1 << (W-2);  // 65536: represents 1.0 in Q1.16
    localparam ANGLE_SCALE    = 1 << (W-3);  // 32768: Q2.15 angle scale [-pi, pi]
    localparam ONE_OVER_SQRT2 = 46341;        // round(1/sqrt(2) * 65536): max safe value for diagonal inputs
                                              // diagonal inputs must satisfy x^2 + y^2 <= 1 to avoid CORDIC overflow
    localparam TOLERANCE      = 10;          // acceptable fixed-point error (~0.0003 rad)
    // With 16 iterations, error is at most 2^-16 radians
    // --> error in fixed point (Q2.15, scale = 2^15)= 2^-16 * 2^15 = 0.5
    // Tolerance 20 * max error to give headroom for rounding in LUT constants

    // check task: passes if got is within TOLERANCE of expected
    task check;
        input string        name;
        input signed [W-1:0] got;
        input integer       expected;
        if ($signed(got) >= (expected - TOLERANCE) &&
            $signed(got) <= (expected + TOLERANCE))
            $display("PASS %s: got %0d  expected %0d", name, $signed(got), expected);
        else
            $display("FAIL %s: got %0d  expected %0d", name, $signed(got), expected);
    endtask

    // send task: apply one input vector and wait for the result
    task send;
        input signed [W-1:0] xv, yv;
        @(posedge clk);
        x_in = xv; y_in = yv; in_valid = 1;
        @(posedge clk);
        in_valid = 0;
        @(posedge out_valid);
    endtask

    initial begin
        rst_n = 0; x_in = 0; y_in = 0; in_valid = 0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // expected values: round(angle_rad * 2^15)
        // diagonal cases use ONE_OVER_SQRT2 so x^2+y^2 = 1, staying within CORDIC overflow limit
        send( ONE_OVER_SQRT2,  ONE_OVER_SQRT2); check("arctan( 1, 1) =  pi/4", angle_out,  25736);
        send( SCALE,           0);              check("arctan( 0, 1) =     0", angle_out,      0);
        send( 0,               SCALE);          check("arctan( 1, 0) =  pi/2", angle_out,  51472);
        send(-ONE_OVER_SQRT2,  ONE_OVER_SQRT2); check("arctan( 1,-1) = 3pi/4", angle_out,  77208);
        send(-ONE_OVER_SQRT2, -ONE_OVER_SQRT2); check("arctan(-1,-1) =-3pi/4", angle_out, -77208);
        send( ONE_OVER_SQRT2, -ONE_OVER_SQRT2); check("arctan(-1, 1) = -pi/4", angle_out, -25736);

        $finish;
    end



    
endmodule