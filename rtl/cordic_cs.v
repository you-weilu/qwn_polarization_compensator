// cordic_cs.v
// Pipelined CORDIC cos/sin in rotation mode. Given an input angle theta,
// computes (cos theta, sin theta) using only shifts and adds.
// Start at (x,y) = (1/k, 0) k: cordic gain

module cordic_cs #(
    parameter W          = 18,  // word width, matches cordic_at and state_decoder pipeline
    parameter ITERATIONS = 16   // number of CORDIC iterations -- match cordic_at for same latency
)(
    input  wire                clk,
    input  wire                rst_n,      // active-low asynchronous reset

    input  wire signed [W-1:0] theta_in,  // angle in Q2.(W-3) format (scale = 2^(W-3) = 32768)
                                          // range [-pi, pi]: same scale as cordic_at angle_out
    input  wire                in_valid,  // high for one cycle when theta_in is valid

    output wire signed [W-1:0] cos_out,   // cos(theta) in Q1.(W-2) format (scale = 2^(W-2) = 65536)
                                          // same format as Stokes values -- ready for matrix multiply
    output wire signed [W-1:0] sin_out,   // sin(theta), same format as cos_out
    output wire                out_valid  // high for one cycle, ITERATIONS+1 cycles after in_valid
);

// returns atan(2^-idx) in Q2.(W-3) format: atan_lut[i] = round(atan(2^-i) * 2^(W-3))
// precomputed for ITERATIONS=16, W=18 (scale = 2^15 = 32768).
// regenerate values if ITERATIONS changes; regenerate scale if W changes.
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

// 1/K in Q1.(W-2): pre-scales initial x so the CORDIC gain K accumulated over
// ITERATIONS cancels out (unscaled output = kcos(theta), ksin(theta))
// K = product of (1/cos(atan(2^-i))) for i=0..ITERATIONS-1 ~= 1.6468 for ITERATIONS=16
// 1/K ~= 0.6073 --> round(0.6073 * 65536) = 39796. Regenerate if ITERATIONS changes.
localparam signed [W-1:0] CORDIC_GAIN_INV = 18'sd39796;

// Pipeline registers
reg signed [W-1:0] x_pipe [0:ITERATIONS];
reg signed [W-1:0] y_pipe [0:ITERATIONS];
reg signed [W-1:0] z_pipe [0:ITERATIONS]; // z: starts at theta and gets driven toward 0
reg valid_pipe [0:ITERATIONS];

// rotation mode converges for z ∈ [-pi/2, pi/2] --> bring z in range at stage 0
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_pipe[0]     <= 0;
        y_pipe[0]     <= 0;
        z_pipe[0]     <= 0;
        valid_pipe[0] <= 1'b0;
    end else begin
        valid_pipe[0] <= in_valid;
        if ($signed(theta_in) > 18'sd51472) begin          // theta > pi/2
            x_pipe[0] <= -CORDIC_GAIN_INV;                // cos(θ-π)=-cos(θ), -1/K cancels the flip
            y_pipe[0] <= 0;
            z_pipe[0] <= $signed(theta_in) - 18'sd102944; // z = theta - pi
        end else if ($signed(theta_in) < -18'sd51472) begin // theta < -pi/2
            x_pipe[0] <= -CORDIC_GAIN_INV;
            y_pipe[0] <= 0;
            z_pipe[0] <= $signed(theta_in) + 18'sd102944; // z = theta + pi
        end else begin                                     // already in range
            x_pipe[0] <= CORDIC_GAIN_INV;
            y_pipe[0] <= 0;
            z_pipe[0] <= theta_in;
        end
    end
end

// for each ITERATIONS: drives z toward 0 by rotating by ±atan(2^-i)
// z > 0: rotate counterclockwise (subtract from z); z < 0: rotate clockwise (add to z)
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
                if (z_pipe[i][W-1]) begin  // z < 0: rotate clockwise (check sign bit)
                    x_pipe[i+1] <= x_pipe[i] + ($signed(y_pipe[i]) >>> i);
                    y_pipe[i+1] <= y_pipe[i] - ($signed(x_pipe[i]) >>> i);
                    z_pipe[i+1] <= z_pipe[i] + atan_lut(i);
                end else begin             // z >= 0: rotate counterclockwise
                    x_pipe[i+1] <= x_pipe[i] - ($signed(y_pipe[i]) >>> i);
                    y_pipe[i+1] <= y_pipe[i] + ($signed(x_pipe[i]) >>> i);
                    z_pipe[i+1] <= z_pipe[i] - atan_lut(i);
                end
            end
        end
    end
endgenerate

assign cos_out  = x_pipe[ITERATIONS];
assign sin_out  = y_pipe[ITERATIONS];
assign out_valid = valid_pipe[ITERATIONS];

endmodule
