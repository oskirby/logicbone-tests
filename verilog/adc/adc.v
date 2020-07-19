module adc #(
    parameter CHANNEL_MASK = 8'b01111111,
) (
    input clk,
    input reset,
    
    // SPI Bus Pins
    output reg csel,
    output reg sclk,
    output reg mosi,
    input      miso,

    // ADC measurement data.
    output reg [11:0] adc_data,
    output reg [3:0]  adc_channel,
    output reg        adc_valid
);

    localparam ADC_STATE_INIT           = 4'h0;
    localparam ADC_STATE_RESET          = 4'h1;
    localparam ADC_STATE_READ_STATUS    = 4'h2; 
    localparam ADC_STATE_POLL_STATUS    = 4'h3;
    localparam ADC_STATE_START_CAL      = 4'h4;
    localparam ADC_STATE_READ_CAL       = 4'h5;
    localparam ADC_STATE_POLL_CAL       = 4'h6;
    localparam ADC_STATE_CFG_DATA       = 4'h7;
    localparam ADC_STATE_CFG_CHAN       = 4'h8;
    localparam ADC_STATE_CFG_SEQ        = 4'h9;
    localparam ADC_STATE_READOUT        = 4'hA;

    localparam ADC_OPCODE_NOP    = 8'b00000000;
    localparam ADC_OPCODE_READ   = 8'b00010000;
    localparam ADC_OPCODE_WRITE  = 8'b00001000;
    localparam ADC_OPCODE_SETBIT = 8'b00011000;
    localparam ADC_OPCODE_CLRBIT = 8'b00100000;

    localparam ADC_REG_SYSTEM_STATUS = 8'h00;
    localparam ADC_REG_GENERAL_CFG   = 8'h01;
    localparam ADC_REG_DATA_CFG      = 8'h02;
    localparam ADC_REG_SEQUENCE_CFG  = 8'h10;
    localparam ADC_REG_AUTO_SEQ_CH_SEL = 8'h12;

    reg adc_reset_done = 1'b0;
    reg adc_cal_done = 1'b0;

    reg [3:0] adc_state         = ADC_STATE_INIT;
    reg [3:0] next_adc_state    = ADC_STATE_INIT;
    reg [23:0] next_adc_outdata = 0;
    reg [4:0] next_adc_bitcount = 0;
    always @(*) begin
        next_adc_state <= adc_state;
        next_adc_bitcount <= 0;
        next_adc_outdata <= 0;

        case (adc_state)
            ADC_STATE_INIT : begin
                // After init, start by resetting the ADC.
                next_adc_outdata <= {ADC_OPCODE_WRITE, ADC_REG_GENERAL_CFG, 8'h01};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_RESET;
            end

            ADC_STATE_RESET: begin
                // After reset, check the status register for the BOR bit to be set.
                next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_SYSTEM_STATUS, 8'h00};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_READ_STATUS;
            end

            ADC_STATE_READ_STATUS: begin
                // Issue a read command to get the BOR status bit.
                next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_SYSTEM_STATUS, 8'h00};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_POLL_STATUS;
            end

            ADC_STATE_POLL_STATUS: begin
                // Keep sending reads until the BOR status bit is set.
                if (~adc_reset_done) begin
                    next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_SYSTEM_STATUS, 8'h00};
                    next_adc_bitcount <= 24;
                    next_adc_state <= ADC_STATE_POLL_STATUS;

                // Start ADC offset calibration once the reset has finished.
                end else begin
                    next_adc_outdata <= {ADC_OPCODE_WRITE, ADC_REG_GENERAL_CFG, 8'h02};
                    next_adc_bitcount <= 24;
                    next_adc_state <= ADC_STATE_START_CAL;
                end
            end

            ADC_STATE_START_CAL: begin
                // Issue a read command to get the CAL status bit.
                next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_GENERAL_CFG, 8'h00};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_READ_CAL;
            end

            ADC_STATE_READ_CAL: begin
                next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_GENERAL_CFG, 8'h00};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_POLL_CAL;
            end

            ADC_STATE_POLL_CAL: begin
                // Keep sending reads until the CAL bit is clear.
                if (~adc_cal_done) begin
                    next_adc_outdata <= {ADC_OPCODE_READ, ADC_REG_GENERAL_CFG, 8'h00};
                    next_adc_bitcount <= 24;
                    next_adc_state <= ADC_STATE_READ_CAL;
                
                // Configure the data channel after calibration is complete.
                end else begin
                    next_adc_outdata <= {ADC_OPCODE_WRITE, ADC_REG_DATA_CFG, 8'h10};
                    next_adc_bitcount <= 24;
                    next_adc_state <= ADC_STATE_CFG_DATA;
                end
            end

            ADC_STATE_CFG_DATA: begin
                // After data configuration, select the channels to readout.
                next_adc_outdata <= {ADC_OPCODE_WRITE, ADC_REG_AUTO_SEQ_CH_SEL, CHANNEL_MASK};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_CFG_CHAN;
            end

            ADC_STATE_CFG_CHAN: begin
                // After data configuration, enable auto-sequence mode.
                next_adc_outdata <= {ADC_OPCODE_WRITE, ADC_REG_SEQUENCE_CFG, 8'h11};
                next_adc_bitcount <= 24;
                next_adc_state <= ADC_STATE_CFG_SEQ;
            end

            ADC_STATE_CFG_SEQ: begin
                // After the auto-sequence mode has been enable, start ADC readout.
                next_adc_outdata <= {ADC_OPCODE_NOP, 8'h00};
                next_adc_bitcount <= 16;
                next_adc_state <= ADC_STATE_READOUT;
            end

            ADC_STATE_READOUT: begin
                // Continue reading ADC data.
                next_adc_outdata <= {ADC_OPCODE_NOP, 8'h00};
                next_adc_bitcount <= 16;
                next_adc_state <= ADC_STATE_READOUT;
            end
        endcase
    end

    // SPI shift registers.
    reg [4:0]  spi_bitcount = 0;
    reg [3:0]  spi_cseldelay = 0;
    reg [23:0] spi_shiftreg_out = 0;
    reg [23:0] spi_shiftreg_in = 0;

    always @(posedge clk) begin
        adc_valid <= 0;

        if (reset) begin
            csel <= 1'b1;
            sclk <= 1'b0;
            msoi <= 1'b0;

            adc_reset_done <= 1'b0;
            adc_cal_done <= 1'b0;
        end

        // Clock bits in and out of the SPI interface.
        else if (spi_bitcount) begin
            csel <= 1'b0;
            if (sclk) begin
                sclk <= 1'b0;
                mosi <= spi_shiftreg_out[spi_bitcount-1];
            end else begin
                sclk <= 1'b1;
                spi_shiftreg_in <= {spi_shiftreg_in[22:0], miso};
                spi_bitcount <= spi_bitcount - 1;
            end
        end

        // Deactivate the chipselect and latch the output.
        else if (spi_cseldelay) begin
            if (adc_state == ADC_STATE_POLL_STATUS) begin
                adc_reset_done <= spi_shiftreg_in[16];
            end
            if (adc_state == ADC_STATE_POLL_CAL) begin
                adc_cal_done <= ~spi_shiftreg_in[17];
            end
            if (adc_state == ADC_STATE_READOUT) begin
                adc_data <= spi_shiftreg_in[15:4];
                adc_channel <= spi_shiftreg_in[3:0];
                adc_valid <= 1;
            end

            if (sclk) begin
                csel <= 1'b0;
                sclk <= 1'b0;
                msoi <= 1'b0;
            end else begin
                csel <= 1'b1;
                sclk <= 1'b0;
                spi_cseldelay <= spi_cseldelay - 1;
            end
        end

        // Start the next command.
        else if (next_adc_bitcount) begin
            adc_state <= next_adc_state;

            spi_bitcount <= next_adc_bitcount;
            spi_cseldelay <= 4;
            spi_shiftreg_out <= next_adc_outdata;

            // Activate the chipselect and start the next word.
            sclk <= 1'b0;
            csel <= 1'b0;
            mosi <= next_adc_outdata[next_adc_bitcount-1];
        end
    end
endmodule
