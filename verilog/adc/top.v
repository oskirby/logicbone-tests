module top(input refclk,
    input pwr_button,
    output [3:0] led,
    
    output adc_csel,
    output adc_sclk,
    output adc_mosi,
    input  adc_miso,

    output [3:0] debug
);

reg [7:0] por_delay = 8'hff;
always @(posedge refclk) if (por_delay) por_delay <= por_delay - 1;

reg [3:0] led_data = 3'b0;
always @(posedge refclk) begin
    if (adc_valid && (adc_channel == 0)) led_data <= adc_data[11:8];
end
assign led = ~led_data;

wire [11:0] adc_data;
wire [3:0]  adc_channel;
wire        adc_valid;

adc adc_instance(
    .clk(refclk),
    .reset(por_delay != 0),

    .csel(adc_csel),
    .sclk(adc_sclk),
    .mosi(adc_mosi),
    .miso(adc_miso),

    .adc_data(adc_data),
    .adc_channel(adc_channel),
    .adc_valid(adc_valid)
);

assign debug = {adc_miso, adc_mosi, adc_sclk, adc_csel};

endmodule
