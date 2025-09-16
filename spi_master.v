`timescale 1ps/1ps

module spi_master #(
    parameter clk_div = 4
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] tx_data,     
    output reg  [7:0] rx_data,    
    output reg        busy,        
    output reg        done,       

    input  wire       miso,        
    output reg        mosi,       
    output reg        sclk,        
    output reg        cs           
);

    // Internal signals
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [3:0] bit_cnt;
    reg [15:0] clk_cnt; 
    reg sclk_en;

    // FSM states
    localparam IDLE     = 2'b00,
               TRANSFER = 2'b01,
               FINISH   = 2'b10;

    reg [1:0] state, next_state;

    // Clock Divider
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt <= 0;
            sclk    <= 0;
        end else if (sclk_en) begin
            if (clk_cnt == (clk_div/2 - 1)) begin
                clk_cnt <= 0;
                sclk    <= ~sclk; 
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end else begin
            clk_cnt <= 0;
            sclk    <= 0;
        end
    end

    // State machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= IDLE;
            busy     <= 0;
            done     <= 0;
            cs       <= 1;  
            mosi     <= 0;
            rx_data  <= 0;
            tx_shift <= 0;
            rx_shift <= 0;
            bit_cnt  <= 0;
            sclk_en  <= 0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    busy <= 0;
                    done <= 0;
                    cs   <= 1;
                    sclk_en <= 0;
                    if (start) begin
                        busy     <= 1;
                        cs       <= 0;
                        tx_shift <= tx_data;
                        rx_shift <= 0;
                        bit_cnt  <= 8;
                        sclk_en  <= 1;
                    end
                end

                TRANSFER: begin
                    // On falling edge: output data
                    if (sclk == 0 && clk_cnt == 0) begin
                        mosi     <= tx_shift[7];
                        tx_shift <= {tx_shift[6:0], 1'b0};
                    end

                    // On rising edge: sample data
                    if (sclk == 1 && clk_cnt == 0) begin
                        rx_shift <= {rx_shift[6:0], miso};
                        if (bit_cnt > 0)
                            bit_cnt <= bit_cnt - 1;
                    end
                end

                FINISH: begin
                    busy    <= 0;
                    done    <= 1;
                    cs      <= 1;
                    sclk_en <= 0;
                    rx_data <= rx_shift;
                end
            endcase
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     if (start) next_state = TRANSFER;
            TRANSFER: if (bit_cnt == 0 && sclk == 1 && clk_cnt == 0) next_state = FINISH;
            FINISH:   next_state = IDLE;
        endcase
    end

endmodule