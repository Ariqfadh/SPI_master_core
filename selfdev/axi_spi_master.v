`timescale 1ns/1ps

module axi4lite_wrapper_spi #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    // AXI Clock and Reset
    input  wire ACLK,
    input  wire ARESETN,

    // AXI4-Lite Write Channels
    input  wire [AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire AWVALID,
    output wire AWREADY,
    input  wire [AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [(AXI_DATA_WIDTH/8)-1:0] WSTRB,
    input  wire WVALID,
    output wire WREADY,
    output wire [1:0] BRESP,
    output wire BVALID,
    input  wire BREADY,

    // AXI4-Lite Read Channels
    input  wire [AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire ARVALID,
    output wire ARREADY,
    output wire [AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0] RRESP,
    output wire RVALID,
    input  wire RREADY,
    
    // SPI Physical Ports
    output wire sclk,
    output wire mosi,
    input  wire miso,
    output wire cs
);

    // Register Map Definition
    parameter ADDR_CTRL    = 6'h00; // Control Register (WO)
    parameter ADDR_STAT    = 6'h04; // Status Register (RO/W1C)
    parameter ADDR_TX      = 6'h08; // Transmit Data Register (WO)
    parameter ADDR_RX      = 6'h0C; // Receive Data Register (RO)
    parameter ADDR_CLK_DIV = 6'h10; // Clock Divider Register (RW)

    // ----------------------------------------------------------------
    // Internal Signals and Registers
    // ----------------------------------------------------------------
    
    // AXI internal logic signals
    reg [AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                      axi_awready;
    reg                      axi_wready;
    reg [1:0]                axi_bresp;
    reg                      axi_bvalid;
    
    reg [AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                      axi_arready;
    reg [AXI_DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]                axi_rresp;
    reg                      axi_rvalid;

    // Separate write address and data received flags
    reg aw_received;
    reg w_received;
    reg [AXI_ADDR_WIDTH-1:0] latched_awaddr;
    reg [AXI_DATA_WIDTH-1:0] latched_wdata;
    reg [(AXI_DATA_WIDTH/8)-1:0] latched_wstrb;

    // Slave registers accessible via AXI
    reg [AXI_DATA_WIDTH-1:0] reg_ctrl;
    reg [7:0]                reg_tx;
    reg [7:0]                reg_rx;
    reg [15:0]               reg_clk_div;
    
    // Status flags
    reg                      reg_done_sticky;
    reg                      reg_irq_sticky;

    // FIX #1: Proper start pulse generation
    reg                      spi_start_req;
    reg                      spi_start_pulse;

    // Metastability protection for miso
    reg miso_sync1;
    reg miso_sync2;

    // Signals to connect to SPI core
    wire        spi_ready;
    wire        spi_busy;
    wire        spi_done;
    wire        spi_irq;
    wire [7:0]  spi_rx_data;
    reg         spi_start;
    wire        reset_n;

    assign reset_n = ARESETN;

    // Assign outputs
    assign AWREADY = axi_awready;
    assign WREADY  = axi_wready;
    assign BVALID  = axi_bvalid;
    assign BRESP   = axi_bresp;
    assign ARREADY = axi_arready;
    assign RVALID  = axi_rvalid;
    assign RRESP   = axi_rresp;
    assign RDATA   = axi_rdata;

    // ----------------------------------------------------------------
    // Metastability Protection - Two-stage synchronizer for miso
    // ----------------------------------------------------------------
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            miso_sync1 <= 1'b0;
            miso_sync2 <= 1'b0;
        end else begin
            miso_sync1 <= miso;
            miso_sync2 <= miso_sync1;
        end
    end

    // ----------------------------------------------------------------
    // SPI Master Core Instantiation
    // ----------------------------------------------------------------
    spi_master #(
        .DEFAULT_CLK_DIV(4)
    ) spi_core_inst (
        .clk        (ACLK),
        .reset      (~ARESETN),
        .start      (spi_start),
        .tx_data    (reg_tx),
        .clk_div_in (reg_clk_div),
        .rx_data    (spi_rx_data),
        .ready      (spi_ready),
        .busy       (spi_busy),
        .done       (spi_done),
        .irq        (spi_irq),
        .miso       (miso_sync2),
        .mosi       (mosi),
        .sclk       (sclk),
        .cs         (cs)
    );
    
    // ----------------------------------------------------------------
    // PROPER SPI START PULSE GENERATION
    // ----------------------------------------------------------------
    
    // Capture start request
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            spi_start_req <= 1'b0;
        end else begin
            // Debug: tampilkan kondisi untuk start
            if (write_enable && valid_write_addr && 
                (latched_awaddr[5:2] == ADDR_CTRL[5:2]) &&
                latched_wdata[0] && latched_wstrb[0]) begin
                spi_start_req <= 1'b1;
                $display("[%0t] AXI_WRAPPER: spi_start_req SET (AWADDR=0x%0h, WDATA=0x%0h, WSTRB=0x%0h)", $time, latched_awaddr, latched_wdata, latched_wstrb);
            end else if (spi_start_pulse) begin
                spi_start_req <= 1'b0;
            end
        end
    end
    
    // Generate single-cycle start pulse
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            spi_start_pulse <= 1'b0;
            spi_start <= 1'b0;
        end else begin
            spi_start_pulse <= spi_start_req && !spi_busy;
            spi_start <= spi_start_pulse;  // Direct assignment for simplicity
            if (spi_start_pulse)
                $display("[%0t] AXI_WRAPPER: spi_start_pulse ACTIVE", $time);
        end
    end

    // ----------------------------------------------------------------
    // AXI Write Logic
    // ----------------------------------------------------------------
    
    // AWREADY logic
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_awready <= 1'b0;
            aw_received <= 1'b0;
            latched_awaddr <= 0;
        end else begin
            if (AWVALID && !aw_received) begin
                axi_awready <= 1'b1;
                aw_received <= 1'b1;
                latched_awaddr <= AWADDR;
            end else begin
                axi_awready <= 1'b0;
                if (w_received && aw_received && !axi_bvalid) begin
                    aw_received <= 1'b0;
                end
            end
        end
    end

    // WREADY logic
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_wready <= 1'b0;
            w_received <= 1'b0;
            latched_wdata <= 0;
            latched_wstrb <= 0;
        end else begin
            if (WVALID && !w_received) begin
                axi_wready <= 1'b1;
                w_received <= 1'b1;
                latched_wdata <= WDATA;  
                latched_wstrb <= WSTRB; 
            end else begin
                axi_wready <= 1'b0;
                if (w_received && aw_received && !axi_bvalid) begin
                    w_received <= 1'b0;
                end
            end
        end
    end

    wire valid_write_addr;
    assign valid_write_addr = (latched_awaddr[5:2] == ADDR_CTRL[5:2]) ||
                              (latched_awaddr[5:2] == ADDR_STAT[5:2]) ||
                              (latched_awaddr[5:2] == ADDR_TX[5:2]) ||
                              (latched_awaddr[5:2] == ADDR_CLK_DIV[5:2]);

    wire valid_read_addr;
    assign valid_read_addr = (axi_araddr[5:2] == ADDR_STAT[5:2]) ||
                             (axi_araddr[5:2] == ADDR_RX[5:2]) ||
                             (axi_araddr[5:2] == ADDR_CLK_DIV[5:2]);

    wire write_enable = aw_received && w_received && !axi_bvalid;
    
    function [31:0] apply_wstrb;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0]  strb;
        integer i;
        begin
            apply_wstrb = old_data;
            for (i = 0; i < 4; i = i + 1) begin
                if (strb[i]) begin
                    apply_wstrb[i*8 +: 8] = new_data[i*8 +: 8];
                end
            end
        end
    endfunction
    
    // FIX #2: REGISTER WRITE LOGIC - Allow writes even when not ready
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            reg_ctrl    <= 32'h0;
            reg_tx      <= 8'h0;
            reg_clk_div <= 16'd4;  
        end else begin
            if (write_enable && valid_write_addr) begin  
                case (latched_awaddr[5:2])
                    ADDR_CTRL[5:2]: begin
                        reg_ctrl <= apply_wstrb(reg_ctrl, latched_wdata, latched_wstrb);
                        $display("[%0t] AXI: CTRL Write, Data=0x%08h, WSTRB=0x%1h", $time, latched_wdata, latched_wstrb);
                    end
                    ADDR_TX[5:2]: begin
                        if (latched_wstrb[0]) begin
                            reg_tx <= latched_wdata[7:0];
                            $display("[%0t] AXI: TX Write, Data=0x%02h", $time, latched_wdata[7:0]);
                        end
                    end
                    ADDR_CLK_DIV[5:2]: begin
                        if (latched_wstrb[0]) begin
                            reg_clk_div[7:0]  <= latched_wdata[7:0];
                            $display("[%0t] AXI: CLK_DIV Write, Data[7:0]=0x%02h", $time, latched_wdata[7:0]);
                        end
                        if (latched_wstrb[1]) begin
                            reg_clk_div[15:8] <= latched_wdata[15:8];
                            $display("[%0t] AXI: CLK_DIV Write, Data[15:8]=0x%02h", $time, latched_wdata[15:8]);
                        end
                    end
                    ADDR_STAT[5:2]: begin
                        if (latched_wstrb[0]) begin  
                            if (latched_wdata[2]) reg_done_sticky <= 1'b0;
                            if (latched_wdata[3]) reg_irq_sticky <= 1'b0;
                            $display("[%0t] AXI: STAT Write, Data=0x%08h, WSTRB=0x%1h", $time, latched_wdata, latched_wstrb);
                        end
                    end
                endcase
            end
        end
    end
    
    // BVALID and BRESP logic
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b0;
        end else begin
            if (write_enable && !axi_bvalid) begin
                axi_bvalid <= 1'b1;
                axi_bresp <= valid_write_addr ? 2'b00 : 2'b10;
            end else if (BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end
    
    // ----------------------------------------------------------------
    // AXI Read Logic
    // ----------------------------------------------------------------
    
    // ARREADY logic
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_arready <= 1'b0;
        end else begin
            if (~axi_arready && ARVALID) begin
                axi_arready <= 1'b1;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    // Store read address
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_araddr <= 0;
        end else begin
            if (~axi_arready && ARVALID) begin
                axi_araddr <= ARADDR;
            end
        end
    end
    
    // RVALID and RDATA logic
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b0;
        end else begin
            if (axi_arready && ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp <= valid_read_addr ? 2'b00 : 2'b10;
                
                case (axi_araddr[5:2])
                    ADDR_STAT[5:2]: begin
                        // FIX #3: STATUS REGISTER - Match testbench expectations
                        axi_rdata <= {28'h0, 
                                     reg_irq_sticky,   // Bit 3: IRQ (sticky)
                                     reg_done_sticky,  // Bit 2: Done (sticky)  
                                     spi_ready,        // Bit 1: Ready (real-time)
                                     spi_busy};        // Bit 0: Busy (real-time)
                    end
                    ADDR_RX[5:2]:      axi_rdata <= {24'h0, reg_rx};
                    ADDR_CLK_DIV[5:2]: axi_rdata <= {16'h0, reg_clk_div};
                    default:           axi_rdata <= 32'h0;
                endcase
            end else if (RREADY && axi_rvalid) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // SPI Status Management
    // ----------------------------------------------------------------
    
    // Update sticky status flags
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            reg_done_sticky <= 1'b0;
            reg_irq_sticky <= 1'b0;
        end else begin
            // Set sticky bits when events occur
            if (spi_done) begin
                reg_done_sticky <= 1'b1;
            end
            if (spi_irq) begin
                reg_irq_sticky <= 1'b1;
            end
            
            // Clear on write to status register (W1C)
            if (write_enable && valid_write_addr && (latched_awaddr[5:2] == ADDR_STAT[5:2])) begin
                if (latched_wstrb[0]) begin
                    if (latched_wdata[2]) reg_done_sticky <= 1'b0;
                    if (latched_wdata[3]) reg_irq_sticky <= 1'b0;
                end
            end
        end
    end
    
    // Latch the received data from SPI core when done
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            reg_rx <= 8'h0;
        end else if (spi_done) begin
            reg_rx <= spi_rx_data;
            $display("[%0t] AXI: RX Updated, Data=0x%02h", $time, spi_rx_data);
        end
    end

    always @(posedge ACLK) begin
        if (spi_start) begin
            $display("[%0t] SPI_MASTER: Start pulse generated, TX=0x%02h", $time, reg_tx);
        end
        if (spi_done) begin
            $display("[%0t] SPI_MASTER: Transfer done, RX=0x%02h", $time, spi_rx_data);
        end
    end

endmodule