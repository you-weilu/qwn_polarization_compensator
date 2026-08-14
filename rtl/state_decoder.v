// state_decoder.v
// Converts raw ADC samples into normalized Stokes values 
// (S1, S2, S3) and then computes ψ (orientation), χ
// (ellipticity), δ (residual phase angle) via Eq. 3.

module state_decoder #(
    parameter ADC_W = 12,    // raw ADC word width
    parameter STOKES_W = 18, // internal fixed-point width
    parameter ANGLE_W = 18   // Output angle width
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
    output reg                 out_valid
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
    reg                        in_valid_d;

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

    wire signed [STOKES_W-1:0] psi_raw, chi_raw, delta_raw;
    wire                       psi_valid, chi_valid, delta_valid;
    wire signed [STOKES_W-1:0] sqrt_s3;
    wire                       sqrt_valid;

    cordic_at #(.W(STOKES_W)) cordic_psi (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (s1_d),
        .y_in     (s2_d),
        .in_valid (in_valid_d),
        .angle_out(psi_raw),
        .out_valid(psi_valid)
    );

    cordic_at #(.W(STOKES_W)) cordic_delta (
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

    cordic_at #(.W(STOKES_W)) cordic_chi (
        .clk      (clk),
        .rst_n    (rst_n),
        .x_in     (sqrt_s3),
        .y_in     (s3_d),
        .in_valid (sqrt_valid),
        .angle_out(chi_raw),
        .out_valid(chi_valid)
    );

    // 3. Output ψ, χ, δ

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            psi_out <= 0;
            chi_out <= 0;
            delta_out <= 0;
            out_valid <= 0;
        end else begin
            psi_out   <= $signed(psi_raw) >>> 1;
            chi_out   <= $signed(chi_raw) >>> 1;
            delta_out <= delta_raw;
            out_valid <= chi_valid; // all 3 valid signals fire same cycle
        end
    end

endmodule

