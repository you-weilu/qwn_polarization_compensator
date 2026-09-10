// correction_solver.v
// Computes the three LCR retardances (Γ1, Γ2, Γ3) needed to compensate
// fiber birefringence using a 3-LCR chain with fixed axes at 0°, 45°, 0°.
//
// The compensation is derived from two polarimeter measurements:
//   V pass (pass_sel=1): measures where the vertical reference state landed
//   D pass (pass_sel=0): measures where the diagonal reference state landed
//
// On the Poincaré sphere, the targets are:
//   V state -> (1, 0, 0)  (+S1 axis)
//   D state -> (0, 1, 0)  (+S2 axis)
//
// The three retardances are found analytically:
// (A retarder with fast axis at θ rotates the Poincaré sphere about the axis at 2θ on the EQUATOR (linear polarization --> s3=0).
//  Fast axis 0° -> rotation about S1; fast axis 45° -> rotation about S2.)
//
//   Γ1 = arctan(-S2_V / S3_V)
//        LCR1 (0° axis) rotates the V state in the S2-S3 plane to zero out S2.
//
//   Γ2 = arctan(-R / S1_V)   where R = sqrt(S2_V^2 + S3_V^2)
//        LCR2 (45° axis) rotates the V state in the S1-S3 plane up to (1,0,0).
//        After this, V is at its target. Γ3 is still free.
//
//   Γ3 = arctan(f'' / e'')
//        LCR3 (0° axis) rotates the D state (which M1+M2 left somewhere on the
//        S2-S3 circle) around to (0,1,0). e'' and f'' are the S2 and S3
//        components of the D state after M1 and M2 have been applied:
//          e'' = (S2_D*S3_V - S3_D*S2_V) / R
//          f'' = -S1_D*R + S1_V*(S2_D*S2_V + S3_D*S3_V) / R
//
// All three Γ values are arctan expressions -> use cordic_at for each.
// Γ2 also needs sqrt(S2_V^2 + S3_V^2) before the arctan.
// e'' and f'' require fixed-point multiplies of the V and D Stokes values.
//
// The V-pass Stokes (s1_in, s2_in, s3_in) are latched when pass_sel=1.
// The D-pass Stokes are read live when pass_sel=0 and correction_needed=1.

module correction_solver #(
    parameter ANGLE_W    = 18,
    parameter CORDIC_ITER = 16
)(
    input wire clk,
    input wire rst_n,

    // inputs from state_decoder (angles not used in new algorithm, kept for compatibility)
    input wire signed [ANGLE_W-1:0] psi,
    input wire signed [ANGLE_W-1:0] chi,
    input wire signed [ANGLE_W-1:0] delta,
    // delayed Stokes from state_decoder, valid on the same cycle as out_valid
    input wire signed [ANGLE_W-1:0] s1_in,
    input wire signed [ANGLE_W-1:0] s2_in,
    input wire signed [ANGLE_W-1:0] s3_in,
    input wire                      pass_sel,  // 1 = V pass, 0 = D pass
    input wire                      stokes_valid,

    // input from threshold_checker
    input wire correction_needed,

    // outputs: three LCR retardances in Q2.15 format
    output reg signed [ANGLE_W-1:0] lcr1_retardance,  // Γ1: LCR at 0°
    output reg signed [ANGLE_W-1:0] lcr2_retardance,  // Γ2: LCR at 45°
    output reg signed [ANGLE_W-1:0] lcr3_retardance   // Γ3: LCR at 0°
);

    // Latch V-pass Stokes on V pass; used during D pass to compute all three Γ values
    reg signed [ANGLE_W-1:0] s1_v;
    reg signed [ANGLE_W-1:0] s2_v;
    reg signed [ANGLE_W-1:0] s3_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_v <= 0;
            s2_v <= 0;
            s3_v <= 0;
            lcr1_retardance <= 0;
            lcr2_retardance <= 0;
            lcr3_retardance <= 0;
        end else if (stokes_valid && pass_sel) begin  // V pass: latch Stokes
            s1_v <= s1_in;
            s2_v <= s2_in;
            s3_v <= s3_in;
        end
    end

    // Γ1 = arctan(-S2_V / S3_V)
    // Triggered on D pass; s2_v and s3_v are already latched from V pass.
    // cordic_at computes arctan(y/x), so x=s3_v, y=-s2_v.
    wire signed [ANGLE_W-1:0] gamma1_raw;
    wire                      gamma1_valid;

    cordic_at #(.W(ANGLE_W), .ITERATIONS(CORDIC_ITER)) cordic_gamma1 (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (s3_v),
        .y_in     (-s2_v),
        .in_valid (stokes_valid && !pass_sel && correction_needed),
        .angle_out(gamma1_raw),
        .out_valid(gamma1_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lcr1_retardance <= 0;
        else if (gamma1_valid)
            lcr1_retardance <= gamma1_raw;
    end

    // Γ2 = arctan(-R / S1_V), R = sqrt(1 - S1_V^2)
    // sqrt_lut computes sqrt(1 - input^2), so feed s1_v to get R.
    // s1_v is already stable (latched from V pass) when this fires on D pass.
    wire signed [ANGLE_W-1:0] R_wire;
    wire                      R_valid;

    sqrt_lut #(.W(ANGLE_W)) r_lut (
        .clk      (clk),
        .rst_n    (rst_n),
        .s3_in    (s1_v),
        .in_valid (stokes_valid && !pass_sel && correction_needed),
        .sqrt_out (R_wire),
        .out_valid(R_valid)
    );

    // cordic_at: x=s1_v, y=-R to get arctan(-R/S1_V).
    // R_valid fires one cycle after the trigger; s1_v is still stable at that point.
    wire signed [ANGLE_W-1:0] gamma2_raw;
    wire                      gamma2_valid;

    cordic_at #(.W(ANGLE_W), .ITERATIONS(CORDIC_ITER)) cordic_gamma2 (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (s1_v),
        .y_in     (-R_wire),
        .in_valid (R_valid),
        .angle_out(gamma2_raw),
        .out_valid(gamma2_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lcr2_retardance <= 0;
        else if (gamma2_valid)
            lcr2_retardance <= gamma2_raw;
    end

    // Γ3 = arctan(y/x) where x = S2_D·S3_V - S3_D·S2_V, y = -S1_D.

    // Multiply: latch the two 18x18 products and pipeline s1_in to stay aligned.

    // Shift and subtract: >>16 to return to Q1.16; subtract in 20-bit before narrowing.

    // CORDIC + latch: x=cross product, y=-s1_d_pipe; triggered by mul_valid.

endmodule
