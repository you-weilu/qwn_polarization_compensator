// state_decoder.v
// Converts raw ADC samples into normalized Stokes values
// (S1, S2, S3) and then computes psi, chi, delta via Eq. 3.
//
// POLARIZATION STATE DEFINITIONS:
//
// The electric field of light oscillates in the x-y plane (perpendicular
// to the direction of propagation). The x and y components oscillate at
// the same frequency but can have different amplitudes and a phase offset
// between them. This phase offset is what determines the polarization state:
//
//   phase offset = 0            --> linear  (field rocks along a straight line)
//   phase offset = 0-180 deg    --> elliptical (field tip traces an ellipse)
//   phase offset = 90, A = B    --> circular (field tip traces a circle)
//
// Any elliptical state can be described by two angles on the Poincare sphere:
//
//   psi (orientation, 0 to pi/2):
//     The angle of the semi-major axis of the polarization ellipse measured
//     from the x-axis. Tells you which direction the ellipse is pointing.
//     psi = 0   --> major axis along x (horizontal)
//     psi = pi/4 -> major axis at 45 degrees
//     psi = pi/2 -> major axis along y (vertical)
//
//   chi (ellipticity, -pi/4 to pi/4):
//     Describes the shape of the ellipse -- how far it is from linear.
//     Defined as arctan(b/a) where b is the semi-minor axis and a is the
//     semi-major axis. In the frame of the ellipse's own axes, chi captures
//     the 90 degree phase offset between the major and minor components.
//     chi = 0      --> linear (b=0, ellipse is a flat line)
//     chi = pi/4   --> circular (b=a, ellipse is a perfect circle)
//     chi = -pi/4  --> circular, opposite handedness
//
//   delta (residual phase, -pi to pi):
//     The phase angle of the D state projected onto the S2-S3 plane after
//     the QWP and HWP have been applied. Used by the correction_solver to
//     set the LCR retardance. delta = arctan(S3/S2).


module state_decoder #(
    parameter ADC_W       = 12,  // raw ADC word width
    parameter STOKES_W    = 18,  // internal fixed-point width
    parameter ANGLE_W     = 18,  // output angle width
    parameter CORDIC_ITER = 16   // CORDIC iterations; changing this adjusts latency and precision
)(
    input wire clk,
    input wire rst_n,

    input  wire [ADC_W-1:0]    s1_raw,    // raw ADC sample (ADC_W-bit signed)
    input  wire [ADC_W-1:0]    s2_raw,
    input  wire [ADC_W-1:0]    s3_raw,
    input  wire                in_valid,  

    output reg  [ANGLE_W-1:0]  psi_out,   // ψ, signed fixed-point
    output reg  [ANGLE_W-1:0]  chi_out,   // χ
    output reg  [ANGLE_W-1:0]  delta_out, // δ
    output reg                 out_valid,

    // delayed Stokes values, valid on same cycle as out_valid
    output reg signed [STOKES_W-1:0] s1_out,
    output reg signed [STOKES_W-1:0] s2_out,
    output reg signed [STOKES_W-1:0] s3_out
);

    // Sign-extend raw Stokes values from 12-bit (scale 2^11) to 18-bit (scale 2^16)
    // (2^16 / 2^11) = 2^5 Left shift by 5

    wire signed [STOKES_W-1:0] s1;
    wire signed [STOKES_W-1:0] s2;
    wire signed [STOKES_W-1:0] s3;

    assign s1 = { {(STOKES_W-ADC_W){s1_raw[ADC_W-1]}},s1_raw } <<< (STOKES_W - ADC_W - 1);
    assign s2 = { {(STOKES_W-ADC_W){s2_raw[ADC_W-1]}},s2_raw } <<< (STOKES_W - ADC_W - 1);
    assign s3 = { {(STOKES_W-ADC_W){s3_raw[ADC_W-1]}},s3_raw } <<< (STOKES_W - ADC_W - 1);
    
    // Instantiate submodules
    // 2ψ = arctan(s2 / s1)
    // 2χ = arcsin(s3) = arctan(s3 / sqrt(1-s3^2))
    // δ = arctan(s3 / s2)

    // chi path as 1 extra cycle (sqrt_lut latency)
    // delay inputs to cordic_psi and cordic_delta to ensure outputs arrive at the same time

    reg signed [STOKES_W-1:0] s1_d;
    reg signed [STOKES_W-1:0] s2_d;
    reg signed [STOKES_W-1:0] s3_d;
    reg                       in_valid_d;

    // delay logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_d       <= 0;
            s2_d       <= 0;
            s3_d       <= 0;
            in_valid_d <= 0;
        end else begin
            s1_d       <= s1;
            s2_d       <= s2;
            s3_d       <= s3;
            in_valid_d <= in_valid;
        end
    end

    // Stokes delay pipeline: CORDIC_ITER+1 stages so s1/s2/s3 arrive in sync with out_valid
    localparam STOKES_DELAY = CORDIC_ITER + 1;
    reg signed [STOKES_W-1:0] s1_delay [0:STOKES_DELAY-1];
    reg signed [STOKES_W-1:0] s2_delay [0:STOKES_DELAY-1];
    reg signed [STOKES_W-1:0] s3_delay [0:STOKES_DELAY-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_delay[0] <= 0; s2_delay[0] <= 0; s3_delay[0] <= 0;
        end else begin
            s1_delay[0] <= s1_d;
            s2_delay[0] <= s2_d;
            s3_delay[0] <= s3_d;
        end
    end

    genvar j;
    generate
        for (j = 1; j < STOKES_DELAY; j = j + 1) begin : stokes_pipe
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    s1_delay[j] <= 0; s2_delay[j] <= 0; s3_delay[j] <= 0;
                end else begin
                    s1_delay[j] <= s1_delay[j-1];
                    s2_delay[j] <= s2_delay[j-1];
                    s3_delay[j] <= s3_delay[j-1];
                end
            end
        end
    endgenerate

    wire signed [STOKES_W-1:0] psi_raw, chi_raw, delta_raw;
    wire                       psi_valid, chi_valid, delta_valid;
    wire signed [STOKES_W-1:0] sqrt_s3;
    wire                       sqrt_valid;

    cordic_at #(.W(STOKES_W), .ITERATIONS(CORDIC_ITER)) cordic_psi (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (s1_d),
        .y_in     (s2_d),
        .in_valid (in_valid_d),
        .angle_out(psi_raw),
        .out_valid(psi_valid)
    );

    cordic_at #(.W(STOKES_W), .ITERATIONS(CORDIC_ITER)) cordic_delta (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (s2_d),
        .y_in     (s3_d),
        .in_valid (in_valid_d),
        .angle_out(delta_raw),
        .out_valid(delta_valid)
    );

    sqrt_lut #(.W(STOKES_W)) sqrt_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .s3_in    (s3),
        .in_valid (in_valid),
        .sqrt_out (sqrt_s3),
        .out_valid(sqrt_valid)
    );

    cordic_at #(.W(STOKES_W), .ITERATIONS(CORDIC_ITER)) cordic_chi (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (sqrt_s3),
        .y_in     (s3_d),
        .in_valid (sqrt_valid),
        .angle_out(chi_raw),
        .out_valid(chi_valid)
    );

    // Update output registers

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psi_out   <= 0;
            chi_out   <= 0;
            delta_out <= 0;
            s1_out    <= 0;
            s2_out    <= 0;
            s3_out    <= 0;
            out_valid <= 0;
        end else begin
            psi_out   <= $signed(psi_raw) >>> 1;
            chi_out   <= $signed(chi_raw) >>> 1;
            delta_out <= delta_raw;
            s1_out    <= s1_delay[STOKES_DELAY-1];
            s2_out    <= s2_delay[STOKES_DELAY-1];
            s3_out    <= s3_delay[STOKES_DELAY-1];
            out_valid <= chi_valid;
        end
    end

endmodule

