`timescale 1ps/1ps

module spi_master #(
    parameter DEFAULT_CLK_DIV = 4
)(
    input  wire        clk,
    input  wire        reset,

    // Control interface
    input  wire        start,
    input  wire [7:0]  tx_data,
    input  wire [15:0] clk_div_in,
    output reg  [7:0]  rx_data,
    output reg         ready,
    output reg         busy,
    output reg         done,
    output reg         irq,

    // SPI signals
    input  wire        miso,
    output reg         mosi,
    output reg         sclk,
    output reg         cs
);

    // Internal signals
    reg [7:0]  tx_shift;
    reg [7:0]  rx_shift;
    reg [3:0]  bit_cnt;
    reg [15:0] clk_cnt;
    reg [15:0] clk_div_reg;  // holds active divider
    reg        sclk_en;

    // FSM states
    localparam READY    = 2'b00,
               IDLE     = 2'b01,
               TRANSFER = 2'b10,
               FINISH   = 2'b11;

    reg [1:0] state, next_state;

    // Clock Divider
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_cnt <= 0;
            sclk    <= 0;
        end else if (sclk_en) begin
            if (clk_cnt == (clk_div_reg/2 - 1)) begin
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
            state       <= READY;
            ready       <= 1;
            busy        <= 0;
            done        <= 0;
            irq         <= 0;
            cs          <= 1;
            mosi        <= 0;
            rx_data     <= 0;
            tx_shift    <= 0;
            rx_shift    <= 0;
            bit_cnt     <= 0;
            sclk_en     <= 0;
            clk_div_reg <= DEFAULT_CLK_DIV;
        end else begin
            state <= next_state;

            // Default: clear interrupt unless asserted in FINISH
            irq <= 0;

            case (state)
                READY: begin
                    ready <= 1;
                    busy  <= 0;
                    done  <= 0;
                    cs    <= 1;
                end

                IDLE: begin
                    ready <= 0;
                    busy  <= 0;
                    done  <= 0;
                    cs    <= 1;
                    sclk_en <= 0;
                    if (start) begin
                        busy        <= 1;
                        cs          <= 0;
                        tx_shift    <= tx_data;
                        rx_shift    <= 0;
                        bit_cnt     <= 8;
                        sclk_en     <= 1;
                        clk_div_reg <= (clk_div_in == 0) ? DEFAULT_CLK_DIV : clk_div_in; 
                        $display("[SPI_MASTER] Start received: TX=0x%02h, CLK_DIV=%d", tx_data, clk_div_in);
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
                    irq     <= 1; 
                    $display("[SPI_MASTER] Transfer done: RX=0x%02h", rx_shift);
                end
            endcase
        end
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            READY:    next_state = IDLE;
            IDLE:     if (start) next_state = TRANSFER;
            TRANSFER: if (bit_cnt == 0 && sclk == 1 && clk_cnt == 0)
                          next_state = FINISH;
            FINISH:   next_state = READY;
        endcase
    end

endmodule
