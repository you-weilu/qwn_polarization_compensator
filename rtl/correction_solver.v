// correction_solver.v
// Latches the V-pass result (psi, chi, delta) into an internal 
// register on the first pass; combines it with the D-pass result 
// on the second pass to compute the required QWP angle, HWP angle, 
// and LCR retardance following the paper's algorithm (Sec. 3A).

module correction_solver #(
    parameter ANGLE_W = 18,
    parameter PI_OVER_4 = 18'sd25736  // pi/4 in Q2.15
)(
    input wire clk,
    input wire rst_n,

    // inputs from state_decoder
    input wire signed [ANGLE_W-1:0] psi,
    input wire signed [ANGLE_W-1:0] chi,
    input wire signed [ANGLE_W-1:0] delta,
    input wire                      pass_sel,  // 1 = V pass, 0 = D pass
    input wire                      out_valid,

    // input from threshold_checker
    input wire correction_needed,

    // outputs to output interface
    output reg signed [ANGLE_W-1:0] qwp_theta,
    output reg signed [ANGLE_W-1:0] hwp_theta,
    output reg signed [ANGLE_W-1:0] lcr_theta
);

    reg signed [ANGLE_W-1:0] psi_v;
    reg signed [ANGLE_W-1:0] chi_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psi_v     <= 0;
            chi_v     <= 0;
            qwp_theta <= 0;
            hwp_theta <= 0;
            lcr_theta <= 0;
        end else if (out_valid && pass_sel) begin  // V pass: latch
            psi_v <= psi;
            chi_v <= chi;
        end else if (out_valid && !pass_sel && correction_needed) begin  // D pass: compute
            // QWP fast axis aligned to semi-major axis of V ellipse
            qwp_theta <= psi_v;

            // after QWP --> linear state pointing at angle (psi_v - chi_v)

            // HWP introduces 180 deg phase shift between fast and slow axes
            // π/2 = 2·hwp_theta − (ψ_V − χ_V) (align linear state to pi/2)
            // 2·hwp_theta = π/2 + (ψ_V − χ_V)
            // hwp_theta = (ψ_V − χ_V)/2 + π/4
            hwp_theta <= (($signed(psi_v) - $signed(chi_v)) >>> 1) - PI_OVER_4;

            // LCR: find how far the D state drifted after the QWP and HWP are applied,
            // then apply the negative of that phase to bring it back.
            //
            // Step 1: apply M_QWP(theta=psi_v) to D Stokes vector [s1_d, s2_d, s3_d]
            //         needs cos(2*psi_v), sin(2*psi_v) -- requires cordic_cs (rotation mode)
            //
            // Step 2: apply M_HWP(theta=hwp_theta) to result of step 1
            //         needs cos(4*hwp_theta), sin(4*hwp_theta) -- requires cordic_cs
            //
            // Step 3: lcr_theta = -arctan(S3_rot / S2_rot) of the rotated D vector
            //         requires cordic_at (vectoring mode, already exists)
            //
            // cordic_cs (rotation mode): feed in angle theta, get (cos theta, sin theta)
            // same shift-and-add structure as cordic_at but runs in opposite direction
            //
            // TODO: implement cordic_cs, pipe raw s1_d/s2_d/s3_d from state_decoder,
            //       add fixed-point multiplies for matrix steps 1 and 2.
            lcr_theta <= 0;


        end
    end

endmodule