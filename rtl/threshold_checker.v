// threshold_checker.v
// Compares the decoded V and D reference states against
// tolerance thresholds; asserts beyond_threshold to trigger
// a correction cycle or within_threshold to loop back for
// the next measurement.
//
// BACKGROUND (Sec. 3A of Gül et al.):
//   The fiber transforms known input states S_V and S_D into
//   measured output states S''_V and S''_D. If the measured
//   states match the ideal states within tolerance, the channel
//   is sufficiently compensated and no correction is needed.
//   If any angle has drifted beyond tolerance, a correction
//   cycle is triggered.
//
// IDEAL REFERENCE ANGLES (fixed by choice of V and D states):
//   V (vertical polarization):  psi = pi/2, chi = 0
//   D (diagonal polarization):  psi = pi/4, chi = 0
//
//   In Q2.15 fixed-point (32768 counts = 1 rad):
//     PSI_V_IDEAL  = round(pi/2 * 32768) = 51472
//     PSI_D_IDEAL  = round(pi/4 * 32768) = 25736
//     CHI_IDEAL    = 0  (both V and D are linear, so chi=0)
//
// NOTE: delta is NOT checked here. It is undefined for V
//   (S2=S3=0 makes arctan(S3/S2) degenerate) and feeds
//   directly into the correction_solver algorithm instead.
//
// THRESHOLD:
//   Paper target is 10 degrees on the Poincare sphere.
//   10 deg × (pi/180) × 32768 ≈ 5726 counts.
//   Exposed as a parameter so it can be tuned at synthesis time.

module threshold_checker #(
    parameter ANGLE_W     = 18,
    parameter PSI_V_IDEAL = 18'sd51472,  // pi/2 in Q2.15: ideal psi for V pass
    parameter PSI_D_IDEAL = 18'sd25736,  // pi/4 in Q2.15: ideal psi for D pass
    parameter CHI_IDEAL   = 18'sd0,      // both V and D are linear so chi=0
    parameter THRESHOLD   = 18'sd5726    // 10 deg in Q2.15
)(
    input wire clk,
    input wire rst_n,
    input wire signed [ANGLE_W-1:0] psi,
    input wire signed [ANGLE_W-1:0] chi,
    input wire pass_sel, // 1 = V pass, 0 = D pass
    input wire valid, // high when psi and chi are valid

    output reg correction_needed // 1 = beyond threshold, 0 = within
);
    reg signed [ANGLE_W-1:0] V_psi;
    reg signed [ANGLE_W-1:0] V_chi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            correction_needed <= 0;
            V_psi             <= 0;
            V_chi             <= 0;
        end else if (valid && pass_sel) begin  // V pass arrived: latch
            V_psi <= $signed(psi);
            V_chi <= $signed(chi);
        end else if (valid && !pass_sel) begin // D pass arrived: compare all four
            correction_needed <= ($signed(V_psi) > $signed(PSI_V_IDEAL) + THRESHOLD) ||
                                 ($signed(V_psi) < $signed(PSI_V_IDEAL) - THRESHOLD) ||
                                 ($signed(V_chi) > $signed(CHI_IDEAL)   + THRESHOLD) ||
                                 ($signed(V_chi) < $signed(CHI_IDEAL)   - THRESHOLD) ||
                                 ($signed(psi)   > $signed(PSI_D_IDEAL) + THRESHOLD) ||
                                 ($signed(psi)   < $signed(PSI_D_IDEAL) - THRESHOLD) ||
                                 ($signed(chi)   > $signed(CHI_IDEAL)   + THRESHOLD) ||
                                 ($signed(chi)   < $signed(CHI_IDEAL)   - THRESHOLD);
        end
    end

endmodule
