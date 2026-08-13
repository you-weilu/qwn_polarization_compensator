// cordic_at.v
// Pipelined CORDIC arctangent in vectoring mode. Computes arctan(y_in / x_in)
// using only shifts and adds. Handles all four input quadrants.

// NOTE: since we only need the ratio y/x, we can ignore the growing magnitude,
// the angle comes out correctly regardless.

module cordic_at #(
    parameter W          = 18,  // word width for x/y inputs and angle output
    parameter ITERATIONS = 16   // number of CORDIC iterations (1-16)
                                // --> more iterations = more accurate but higher latency
)(
    input  wire                  clk,
    input  wire                  rst_n,     // active-low asynchronous reset

    input  wire signed [W-1:0]   x_in,     // x component, Q1.(W-2) signed fixed-point
                                           // x^2+y^2 <= 1 required (magnitude grows due to CORDIC gain, prevent overflow)
                                           // we can ignore as stokes inputs s1^2 + s2^2 + s3^2 <= 1
    input  wire signed [W-1:0]   y_in,     // y component, Q1.(W-2) signed fixed-point
    input  wire                  in_valid, // high for one cycle when x_in/y_in are valid

    // arctan(y_in / x_in) in Q2.(W-3) format (scale = 2^(W-3)) 
    // we need 3 int bits to represent range [-pi, pi]
    output wire signed [W-1:0]   angle_out,
    output wire                  out_valid
);
    // returns atan(2^-idx) in Q2.(W-3) format: atan_lut[i] = round(atan(2^-i) * 2^(W-3))
    // precomputed for W=18 (scale = 2^15 = 32768). regenerate if W changes.
    function signed [W-1:0] atan_lut;
        input integer idx;
        case (idx)
            0:  atan_lut = 18'sd25736;  // atan(2^0)  = pi/4  = 0.7854 rad = 45 deg
            1:  atan_lut = 18'sd15192;  // atan(2^-1) = 0.4636 rad = 26.6 deg
            2:  atan_lut = 18'sd8028;
            3:  atan_lut = 18'sd4075;
            4:  atan_lut = 18'sd2045;   // 'sd: signed, decimal value 2045
            5:  atan_lut = 18'sd1024;
            6:  atan_lut = 18'sd512;
            7:  atan_lut = 18'sd256;
            8:  atan_lut = 18'sd128;
            9:  atan_lut = 18'sd64;
            10: atan_lut = 18'sd32;
            11: atan_lut = 18'sd16;
            12: atan_lut = 18'sd8;
            13: atan_lut = 18'sd4;
            14: atan_lut = 18'sd2;
            15: atan_lut = 18'sd1;
            default: atan_lut = 18'sd0;
        endcase
    endfunction

    // Pipeline registers
    reg signed [W-1:0] x_pipe [0:ITERATIONS];
    reg signed [W-1:0] y_pipe [0:ITERATIONS];
    reg signed [W-1:0] z_pipe [0:ITERATIONS]; // z: angle accumulator
    reg valid_pipe [0:ITERATIONS];

    // stage 0: register inputs and correct quadrant so x >= 0 before CORDIC iterations
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_pipe[0]     <= 0;
            y_pipe[0]     <= 0;
            z_pipe[0]     <= 0;
            valid_pipe[0] <= 1'b0;
        end else begin
            valid_pipe[0] <= in_valid;
            if (x_in[W-1]) begin           // x < 0: rotate into right half-plane
                if (!y_in[W-1]) begin      // quadrant 2 (x<0, y>=0): rotate -90 deg, offset z by +pi/2
                    x_pipe[0] <=  y_in;
                    y_pipe[0] <= -x_in;
                    z_pipe[0] <=  18'sd51472;  // pi/2 in Q2.(W-3): round(pi/2 * 2^15)
                end else begin             // quadrant 3 (x<0, y<0): rotate +90 deg, offset z by -pi/2
                    x_pipe[0] <= -y_in;
                    y_pipe[0] <=  x_in;
                    z_pipe[0] <= -18'sd51472;
                end
            end else begin                 // x >= 0: no correction needed
                x_pipe[0] <= x_in;
                y_pipe[0] <= y_in;
                z_pipe[0] <= 0;
            end
        end
    end

    // stages 1..ITERATIONS: one CORDIC rotation per stage.
    // each stage drives y toward 0 by rotating by atan(2^-i), accumulating the angle in z.
    genvar i;
    generate
        for (i = 0; i < ITERATIONS; i = i + 1) begin : cordic_stage
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    x_pipe[i+1]     <= 0;
                    y_pipe[i+1]     <= 0;
                    z_pipe[i+1]     <= 0;
                    valid_pipe[i+1] <= 1'b0;
                end else begin
                    valid_pipe[i+1] <= valid_pipe[i];
                    if (y_pipe[i][W-1]) begin  // y < 0: rotate counterclockwise
                        x_pipe[i+1] <= x_pipe[i] - ($signed(y_pipe[i]) >>> i); // >>> arithmetic right shift
                        y_pipe[i+1] <= y_pipe[i] + ($signed(x_pipe[i]) >>> i);
                        z_pipe[i+1] <= z_pipe[i] - atan_lut(i);
                    end else begin             // y >= 0: rotate clockwise
                        x_pipe[i+1] <= x_pipe[i] + ($signed(y_pipe[i]) >>> i);
                        y_pipe[i+1] <= y_pipe[i] - ($signed(x_pipe[i]) >>> i);
                        z_pipe[i+1] <= z_pipe[i] + atan_lut(i);
                    end
                end
            end
        end
    endgenerate

    assign angle_out = z_pipe[ITERATIONS];
    assign out_valid  = valid_pipe[ITERATIONS];


endmodule
