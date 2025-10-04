`timescale 1ns/1ps

module axi_spi_master_tb;

    // ----------------------------------------------------------------
    // Clock and Reset
    // ----------------------------------------------------------------
    reg ACLK;
    reg ARESETN;
    
    initial ACLK = 0;
    always #5 ACLK = ~ACLK;  // 100 MHz clock (10ns period)

    // ----------------------------------------------------------------
    // AXI Interface Signals
    // ----------------------------------------------------------------
    reg [31:0] AWADDR;
    reg        AWVALID;
    wire       AWREADY;
    reg [31:0] WDATA;
    reg [3:0]  WSTRB;
    reg        WVALID;
    wire       WREADY;
    wire [1:0] BRESP;
    wire       BVALID;
    reg        BREADY;
    
    reg [31:0] ARADDR;
    reg        ARVALID;
    wire       ARREADY;
    wire [31:0] RDATA;
    wire [1:0]  RRESP;
    wire        RVALID;
    reg         RREADY;

    // ----------------------------------------------------------------
    // SPI Physical Interface
    // ----------------------------------------------------------------
    wire sclk;
    wire mosi;
    wire miso;
    wire cs;

    // ----------------------------------------------------------------
    // Register Addresses
    // ----------------------------------------------------------------
    localparam ADDR_CTRL    = 32'h00;
    localparam ADDR_STAT    = 32'h04;
    localparam ADDR_TX      = 32'h08;
    localparam ADDR_RX      = 32'h0C;
    localparam ADDR_CLK_DIV = 32'h10;

    // ----------------------------------------------------------------
    // DUT Instantiation
    // ----------------------------------------------------------------
    axi4lite_wrapper_spi #(
        .AXI_ADDR_WIDTH(32),
        .AXI_DATA_WIDTH(32)
    ) dut (
        .ACLK(ACLK),
        .ARESETN(ARESETN),
        .AWADDR(AWADDR),
        .AWVALID(AWVALID),
        .AWREADY(AWREADY),
        .WDATA(WDATA),
        .WSTRB(WSTRB),
        .WVALID(WVALID),
        .WREADY(WREADY),
        .BRESP(BRESP),
        .BVALID(BVALID),
        .BREADY(BREADY),
        .ARADDR(ARADDR),
        .ARVALID(ARVALID),
        .ARREADY(ARREADY),
        .RDATA(RDATA),
        .RRESP(RRESP),
        .RVALID(RVALID),
        .RREADY(RREADY),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs(cs)
    );

    // ----------------------------------------------------------------
    // IMPROVED: SPI Slave Model with Configurable Response
    // ----------------------------------------------------------------
    reg [7:0] slave_shift_reg;
    reg [7:0] slave_tx_data = 8'hA5;  // Default response
    reg [2:0] slave_bit_counter;
    reg       slave_active;
    
    initial begin
        slave_shift_reg = 8'h0;
        slave_bit_counter = 3'b0;
        slave_active = 1'b0;
    end
    
    // Detect CS going active and load shift register
    always @(negedge cs) begin
        slave_shift_reg <= slave_tx_data;
        slave_bit_counter <= 3'b0;
        slave_active <= 1'b1;
        $display("[%0t] SPI Slave: CS Active, Loading TX Data = 0x%0h", $time, slave_tx_data);
    end
    
    always @(posedge cs) begin
        slave_active <= 1'b0;
    end
    
    // MISO output - drive MSB when active
    assign miso = (slave_active) ? slave_shift_reg[7] : 1'bz;

    // Sampling MOSI (master out) pada rising edge SCLK
    reg [7:0] slave_rx_reg;
    always @(posedge sclk) begin
        if (slave_active) begin
            slave_rx_reg <= {slave_rx_reg[6:0], mosi};
        end
        if (slave_active && slave_bit_counter == 3'd7) begin
            $display("[%0t] SPI Slave: Received byte = 0x%0h", $time, {slave_rx_reg[6:0], mosi});
        end
    end

    // Geser shift register (untuk output MISO) pada falling edge SCLK
    always @(negedge sclk) begin
        if (slave_active) begin
            slave_shift_reg <= {slave_shift_reg[6:0], 1'b0};
            slave_bit_counter <= slave_bit_counter + 1;
        end
    end

    task set_slave_response;
        input [7:0] data;
        begin
            slave_tx_data = data;
            $display("[%0t] SPI Slave: Response set to 0x%0h", $time, data);
        end
    endtask

    // ----------------------------------------------------------------
    // AXI Write Task (Optimized)
    // ----------------------------------------------------------------
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(posedge ACLK);
            AWADDR  <= addr;
            AWVALID <= 1'b1;
            WDATA   <= data;
            WSTRB   <= strb;
            WVALID  <= 1'b1;
            BREADY  <= 1'b1;
            
            fork
                begin
                    wait(AWREADY && AWVALID);
                    @(posedge ACLK);
                    AWVALID <= 1'b0;
                end
                begin
                    wait(WREADY && WVALID);
                    @(posedge ACLK);
                    WVALID <= 1'b0;
                end
                begin
                    wait(BVALID && BREADY);
                    @(posedge ACLK);
                    BREADY <= 1'b0;
                end
            join
            
            if (BRESP == 2'b00) begin
                $display("[%0t] AXI Write OK: Addr=0x%0h, Data=0x%0h, Strb=0x%0h", 
                         $time, addr, data, strb);
            end else begin
                $display("[%0t] AXI Write ERROR: Addr=0x%0h, BRESP=0x%0h", 
                         $time, addr, BRESP);
            end
        end
    endtask

    task axi_write_simple;
        input [31:0] addr;
        input [31:0] data;
        begin
            axi_write(addr, data, 4'hF);
        end
    endtask

    // ----------------------------------------------------------------
    // AXI Read Task (Optimized)
    // ----------------------------------------------------------------
    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge ACLK);
            ARADDR  <= addr;
            ARVALID <= 1'b1;
            RREADY  <= 1'b1;
            
            fork
                begin
                    wait(ARREADY && ARVALID);
                    @(posedge ACLK);
                    ARVALID <= 1'b0;
                end
                begin
                    wait(RVALID && RREADY);
                    data = RDATA;
                    @(posedge ACLK);
                    RREADY <= 1'b0;
                end
            join
            
            if (RRESP == 2'b00) begin
                $display("[%0t] AXI Read OK: Addr=0x%0h, Data=0x%0h", 
                         $time, addr, data);
            end else begin
                $display("[%0t] AXI Read ERROR: Addr=0x%0h, RRESP=0x%0h", 
                         $time, addr, RRESP);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Consolidated Test Stimulus (Single Initial Block)
    // ----------------------------------------------------------------
    reg [31:0] read_data;
    reg [7:0]  rx_byte;
    
    initial begin
        $display("\n========================================");
        $display("  AXI-SPI Master Testbench Start");
        $display("========================================\n");
        
        // Initialize signals
        ARESETN = 0;
        AWADDR = 0; AWVALID = 0;
        WDATA = 0; WSTRB = 0; WVALID = 0;
        BREADY = 0;
        ARADDR = 0; ARVALID = 0;
        RREADY = 0;
        
        // Reset sequence
        repeat(5) @(posedge ACLK);
        ARESETN = 1;
        $display("[%0t] Reset released\n", $time);
        
        repeat(5) @(posedge ACLK);
        
        // ============================================================
        // TEST 1: Simple 8-bit SPI Transaction
        // ============================================================
        $display("-------- TEST 1: Simple 8-bit Transaction --------");
        
        // Set clock divider
        axi_write_simple(ADDR_CLK_DIV, 32'h00000004);
        
        // Configure slave to echo the same data
        set_slave_response(8'hA5);
        
        // Write data to TX register
        axi_write_simple(ADDR_TX, 32'h000000A5);
        
        // Start SPI transaction
        axi_write_simple(ADDR_CTRL, 32'h00000001);
        
        // Poll status until not busy
        $display("[%0t] Polling STATUS register...", $time);
        read_data = 32'hFFFFFFFF;
        while (read_data[0] == 1'b1) begin
            axi_read(ADDR_STAT, read_data);
            repeat(2) @(posedge ACLK);
        end
        $display("[%0t] SPI transaction complete (busy=0)", $time);
        $display("[%0t] Status: busy=%b, ready=%b, done=%b", 
                 $time, read_data[0], read_data[1], read_data[2]);
        
        // Read RX register
        axi_read(ADDR_RX, read_data);
        
        // Verify received data
        if (read_data[7:0] == 8'hA5) begin
            $display("*** TEST 1 PASSED: RX=0x%02h matches expected 0x%02h ***\n", 
                     read_data[7:0], 8'hA5);
        end else begin
            $display("*** TEST 1 FAILED: Expected 0x%02h, Got 0x%02h ***\n", 
                     8'hA5, read_data[7:0]);
        end
        
        repeat(10) @(posedge ACLK);
        
        // ============================================================
        // TEST 2: Another Transaction with Different Data
        // ============================================================
        $display("-------- TEST 2: Second Transaction (0x5A) --------");
        
        // Configure slave with different response
        set_slave_response(8'h5A);
        
        axi_write_simple(ADDR_TX, 32'h0000005A);
        axi_write_simple(ADDR_CTRL, 32'h00000001);
        
        // Poll status
        read_data = 32'hFFFFFFFF;
        while (read_data[0] == 1'b1) begin
            axi_read(ADDR_STAT, read_data);
            repeat(2) @(posedge ACLK);
        end
        
        axi_read(ADDR_RX, read_data);
        
        if (read_data[7:0] == 8'h5A) begin
            $display("*** TEST 2 PASSED: RX=0x%02h matches expected 0x%02h ***\n", 
                     read_data[7:0], 8'h5A);
        end else begin
            $display("*** TEST 2 FAILED: Expected 0x%02h, Got 0x%02h ***\n", 
                     8'h5A, read_data[7:0]);
        end
        
        repeat(20) @(posedge ACLK);
        
        $display("========================================");
        $display("  Testbench Complete");
        $display("========================================\n");
        
        $finish;
    end
    
    // ----------------------------------------------------------------
    // Timeout Watchdog
    // ----------------------------------------------------------------
    initial begin
        #500000; // 500us timeout (increased)
        $display("\n*** ERROR: Testbench timeout! ***\n");
        $finish;
    end
    
    // ----------------------------------------------------------------
    // Waveform dump
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("axi_spi_tb.vcd");
        $dumpvars(0, axi_spi_master_tb);
    end

endmodule