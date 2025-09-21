`timescale 1ps/1ps

module axi_spi_master #(
    parameter DEFAULT_CLK_DIV = 4,
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    // Clock and Reset
    input  wire                        axi_aclk,
    input  wire                        axi_aresetn,
    
    // AXI4-Lite Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [2:0]                  s_axi_awprot,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,
    
    // AXI4-Lite Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                        s_axi_wvalid,
    output reg                         s_axi_wready,
    
    // AXI4-Lite Write Response Channel
    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,
    
    // AXI4-Lite Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [2:0]                  s_axi_arprot,
    input  wire                        s_axi_arvalid,
    output reg                         s_axi_arready,
    
    // AXI4-Lite Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready,
    
    // SPI Interface
    input  wire                        miso,
    output wire                        mosi,
    output wire                        sclk,
    output wire                        cs,
    
    // Interrupt
    output wire                        irq_out
);

    // Register Map:
    // 0x00: CONTROL (bit 0: start, bit 1: enable_irq)
    // 0x04: STATUS (bit 0: ready, bit 1: busy, bit 2: done, bit 3: irq_flag)
    // 0x08: TX_DATA
    // 0x0C: RX_DATA
    // 0x10: CLK_DIV
    
    localparam ADDR_CONTROL = 5'h00;
    localparam ADDR_STATUS  = 5'h04;
    localparam ADDR_TX_DATA = 5'h08;
    localparam ADDR_RX_DATA = 5'h0C;
    localparam ADDR_CLK_DIV = 5'h10;
    
    // AXI FSM States
    localparam AXI_WRITE_IDLE = 2'b00;
    localparam AXI_WRITE_DATA = 2'b01;
    localparam AXI_WRITE_RESP = 2'b10;
    
    localparam AXI_READ_IDLE = 2'b00;
    localparam AXI_READ_DATA = 2'b01;
    
    // Internal registers
    reg        control_start;
    reg        control_enable_irq;
    reg [7:0]  tx_data_reg;
    reg [15:0] clk_div_reg;
    reg        irq_flag;
    
    // AXI FSM registers
    reg [1:0] axi_write_state;
    reg [1:0] axi_read_state;
    reg [AXI_ADDR_WIDTH-1:0] write_addr;
    reg [AXI_ADDR_WIDTH-1:0] read_addr;
    
    // SPI core signals
    wire       spi_ready;
    wire       spi_busy;
    wire       spi_done;
    wire       spi_irq;
    wire [7:0] spi_rx_data;
    
    // Reset logic
    wire reset = ~axi_aresetn;
    
    // SPI Master instantiation
    spi_master #(
        .DEFAULT_CLK_DIV(DEFAULT_CLK_DIV)
    ) spi_core (
        .clk        (axi_aclk),
        .reset      (reset),
        .start      (control_start),
        .tx_data    (tx_data_reg),
        .clk_div_in (clk_div_reg),
        .rx_data    (spi_rx_data),
        .ready      (spi_ready),
        .busy       (spi_busy),
        .done       (spi_done),
        .irq        (spi_irq),
        .miso       (miso),
        .mosi       (mosi),
        .sclk       (sclk),
        .cs         (cs)
    );
    
    // Interrupt logic
    always @(posedge axi_aclk or posedge reset) begin
        if (reset) begin
            irq_flag <= 1'b0;
        end else begin
            // Priority to clear over set
            if (axi_write_state == AXI_WRITE_DATA && 
                write_addr[4:0] == ADDR_STATUS && 
                s_axi_wstrb[0] &&  // Only if writing to byte 0
                s_axi_wdata[3] == 1'b0) begin
                // Clear IRQ flag when writing 0 to status[3]
                irq_flag <= 1'b0;
            end else if (spi_irq) begin
                irq_flag <= 1'b1;
            end
        end
    end
    
    assign irq_out = irq_flag & control_enable_irq;
    
    // AXI Write Logic
    always @(posedge axi_aclk or posedge reset) begin
        if (reset) begin
            axi_write_state  <= AXI_WRITE_IDLE;
            s_axi_awready    <= 1'b0;
            s_axi_wready     <= 1'b0;
            s_axi_bvalid     <= 1'b0;
            s_axi_bresp      <= 2'b00;
            write_addr       <= 0;
            control_start    <= 1'b0;
            control_enable_irq <= 1'b0;
            tx_data_reg      <= 8'h00;
            clk_div_reg      <= DEFAULT_CLK_DIV;
        end else begin
            // Auto-clear start bit
            control_start <= 1'b0;
            
            case (axi_write_state)
                AXI_WRITE_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    s_axi_bresp  <= 2'b00;  // Reset response
                    if (s_axi_awvalid) begin
                        s_axi_awready   <= 1'b1;
                        write_addr      <= s_axi_awaddr;
                        axi_write_state <= AXI_WRITE_DATA;
                    end
                end
                
                AXI_WRITE_DATA: begin
                    s_axi_awready <= 1'b0;
                    if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b1;
                        axi_write_state <= AXI_WRITE_RESP;
                        
                        // Register writes with wstrb handling
                        case (write_addr[4:0])
                            ADDR_CONTROL: begin
                                if (s_axi_wstrb[0]) begin
                                    control_start      <= s_axi_wdata[0];
                                    control_enable_irq <= s_axi_wdata[1];
                                end
                            end
                            ADDR_TX_DATA: begin
                                if (s_axi_wstrb[0]) tx_data_reg <= s_axi_wdata[7:0];
                            end
                            ADDR_CLK_DIV: begin
                                if (!spi_busy) begin // Only allow write when not busy
                                    if (s_axi_wstrb[0]) clk_div_reg[7:0]  <= s_axi_wdata[7:0];
                                    if (s_axi_wstrb[1]) clk_div_reg[15:8] <= s_axi_wdata[15:8];
                                end else begin
                                    s_axi_bresp <= 2'b10; // SLVERR - cannot write while busy
                                end
                            end
                            default: begin
                                s_axi_bresp <= 2'b10; // SLVERR
                            end
                        endcase
                    end
                end
                
                AXI_WRITE_RESP: begin
                    s_axi_wready <= 1'b0;
                    if (!s_axi_bvalid) begin
                        s_axi_bvalid <= 1'b1;
                    end else if (s_axi_bready) begin
                        s_axi_bvalid    <= 1'b0;
                        axi_write_state <= AXI_WRITE_IDLE;
                    end
                end
            endcase
        end
    end
    
    // AXI Read Logic
    always @(posedge axi_aclk or posedge reset) begin
        if (reset) begin
            axi_read_state <= AXI_READ_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= 32'h0;
            s_axi_rresp    <= 2'b00;
            read_addr      <= 0;
        end else begin
            case (axi_read_state)
                AXI_READ_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    if (s_axi_arvalid) begin
                        s_axi_arready   <= 1'b1;
                        read_addr       <= s_axi_araddr;
                        axi_read_state  <= AXI_READ_DATA;
                    end
                end
                
                AXI_READ_DATA: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b1;
                    
                    // Default values
                    s_axi_rresp <= 2'b00; // OKAY
                    s_axi_rdata <= 32'h0;
                    
                    // Register reads
                    case (read_addr[4:0])
                        ADDR_CONTROL: begin
                            s_axi_rdata <= {30'h0, control_enable_irq, control_start};
                        end
                        ADDR_STATUS: begin
                            s_axi_rdata <= {28'h0, irq_flag, spi_done, spi_busy, spi_ready};
                        end
                        ADDR_TX_DATA: begin
                            s_axi_rdata <= {24'h0, tx_data_reg};
                        end
                        ADDR_RX_DATA: begin
                            s_axi_rdata <= {24'h0, spi_rx_data};
                        end
                        ADDR_CLK_DIV: begin
                            s_axi_rdata <= {16'h0, clk_div_reg};
                        end
                        default: begin
                            s_axi_rresp <= 2'b10; // SLVERR
                        end
                    endcase
                    
                    if (s_axi_rready) begin
                        s_axi_rvalid   <= 1'b0;
                        axi_read_state <= AXI_READ_IDLE;
                    end
                end
            endcase
        end
    end

endmodule