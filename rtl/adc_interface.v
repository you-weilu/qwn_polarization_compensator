// adc_interface.v
// Interface with Radiant hard ADC IP block

module adc_interface (
    input  wire        clk,
    input  wire        rst_n,
    
    // Inputs from ADC
    input  wire [11:0] adc_ip_data,
    input  wire        adc_ip_valid,
    input  wire [3:0]  adc_ip_channel,
    
    // Outputs to State Decoder
    output reg  [11:0] sample_i0,
    output reg  [11:0] sample_i1,
    output reg  [11:0] sample_i2,
    output reg  [11:0] sample_i3,
    output reg         polarimeter_data_valid
);
endmodule