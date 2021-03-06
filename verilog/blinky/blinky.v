module top(input clk, input pwr_button, output [3:0] led);
    localparam ctr_width = 26;
    localparam ctr_max = 2**ctr_width - 1;
    reg [ctr_width-1:0] ctr = 0;
    reg [9:0] pwm_ctr = 0;
    reg dir = 0;

    always@(posedge clk) begin
    ctr <= dir ? ctr - 1'b1 - pwr_button: ctr + 1'b1 + pwr_button;
        if (ctr[ctr_width-1 : ctr_width-3] == 0 && dir == 1)
            dir <= 1'b0;
        else if (ctr[ctr_width-1 : ctr_width-3] == 7 && dir == 0)
            dir <= 1'b1;
        pwm_ctr <= pwm_ctr + 1'b1;
    end

    reg [9:0] brightness [0:7];
    localparam bright_max = 2**10 - 1;
    reg [7:0] led_reg;

    genvar i;
    generate
    for (i = 0; i < 4; i=i+1) begin
       always @ (posedge clk) begin
            if (ctr[ctr_width-1 : ctr_width-2] == i)
                brightness[i] <= bright_max;
            else if (ctr[ctr_width-1 : ctr_width-2] == (i - 1))
                brightness[i] <= ctr[ctr_width-3:ctr_width-12];
             else if (ctr[ctr_width-1 : ctr_width-2] == (i + 1))
                 brightness[i] <= bright_max - ctr[ctr_width-3:ctr_width-12];
            else
                brightness[i] <= 0;
            led_reg[i] <= pwm_ctr < brightness[i];
       end
    end
    endgenerate

    assign led = ~led_reg;
endmodule
