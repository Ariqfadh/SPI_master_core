`timescale 1ns/1ps

module axi_spi_master_tb;

    parameter CLK_PERIOD = 10;
    
    // Signals
    reg         clk;
    reg         resetn;
    reg [31:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg [31:0]  wdata;
    reg [3:0]   wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg [31:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;
    reg         miso;
    wire        mosi;
    wire        sclk;
    wire        cs;
    wire        irq;
    
    // DUT
    axi_spi_master dut (
        .axi_aclk(clk),
        .axi_aresetn(resetn),
        .s_axi_awaddr(awaddr),
        .s_axi_awprot(3'b000),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arprot(3'b000),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .miso(miso),
        .mosi(mosi),
        .sclk(sclk),
        .cs(cs),
        .irq_out(irq)
    );
    
    // Clock
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // Simple loopback
    always @(posedge sclk) begin
        if (!cs) miso <= mosi;
    end
    
    initial begin
        // Init
        clk = 0;
        resetn = 0;
        awaddr = 0;
        awvalid = 0;
        wdata = 0;
        wstrb = 0;
        wvalid = 0;
        bready = 1;
        araddr = 0;
        arvalid = 0;
        rready = 1;
        miso = 0;
        
        #100 resetn = 1;
        #50;
        
        $display("=== AXI SPI Master Testbench ===");
        
        // Write to TX_DATA (0x08)
        $display("[INFO] Writing TX data: 0x55");
        
        // AXI Write Address Phase
        @(posedge clk);
        awaddr = 32'h08;
        awvalid = 1;
        
        $display("[DEBUG] Waiting for awready...");
        wait(awready);
        @(posedge clk);
        awvalid = 0;
        $display("[DEBUG] Address phase complete");
        
        // AXI Write Data Phase
        wdata = 32'h55;
        wvalid = 1;
        wstrb = 4'hF;
        
        $display("[DEBUG] Waiting for wready...");
        wait(wready);
        @(posedge clk);
        wvalid = 0;
        $display("[DEBUG] Data phase complete");
        
        // AXI Write Response Phase
        $display("[DEBUG] Waiting for bvalid...");
        wait(bvalid);
        @(posedge clk);
        $display("[INFO] TX Data written successfully");
        
        // Start transfer (write to CONTROL 0x00)
        $display("[INFO] Starting SPI transfer");
        
        // Address phase
        @(posedge clk);
        awaddr = 32'h00;
        awvalid = 1;
        wait(awready);
        @(posedge clk);
        awvalid = 0;
        
        // Data phase
        wdata = 32'h01; // start bit
        wvalid = 1;
        wait(wready);
        @(posedge clk);
        wvalid = 0;
        
        // Response phase
        wait(bvalid);
        @(posedge clk);
        $display("[INFO] Transfer started");
        
        // Wait for SPI completion
        $display("[INFO] Waiting for SPI completion...");
        #5000;
        
        // Read status (0x04)
        araddr = 32'h04;
        arvalid = 1;
        
        wait(arready);
        @(posedge clk);
        arvalid = 0;
        
        wait(rvalid);
        $display("[INFO] Status register: 0x%08h", rdata);
        
        // Read RX data (0x0C)
        @(posedge clk);
        araddr = 32'h0C;
        arvalid = 1;
        
        wait(arready);
        @(posedge clk);
        arvalid = 0;
        
        wait(rvalid);
        $display("[INFO] RX Data: 0x%08h", rdata);
        
        if (rdata[7:0] == 8'h55) begin
            $display("[PASS] Loopback test successful!");
        end else begin
            $display("[FAIL] Loopback test failed - expected 0x55, got 0x%02h", rdata[7:0]);
        end
        
        // Test another pattern
        $display("\n=== Testing pattern 0xAA ===");
        
        // Write TX data
        @(posedge clk);
        awaddr = 32'h08;
        awvalid = 1;
        wdata = 32'hAA;
        wvalid = 1;
        wstrb = 4'hF;
        
        wait(awready && wready);
        @(posedge clk);
        awvalid = 0;
        wvalid = 0;
        wait(bvalid);
        
        // Start transfer
        @(posedge clk);
        awaddr = 32'h00;
        awvalid = 1;
        wdata = 32'h01;
        wvalid = 1;
        
        wait(awready && wready);
        @(posedge clk);
        awvalid = 0;
        wvalid = 0;
        wait(bvalid);
        
        // Wait and read result
        #5000;
        
        araddr = 32'h0C;
        arvalid = 1;
        wait(arready);
        @(posedge clk);
        arvalid = 0;
        wait(rvalid);
        
        $display("[INFO] RX Data: 0x%08h", rdata);
        if (rdata[7:0] == 8'hAA) begin
            $display("[PASS] Second test successful!");
        end else begin
            $display("[FAIL] Second test failed");
        end
        
        #1000;
        $display("\n=== Test completed ===");
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000; // Shorter timeout for debugging
        $display("[ERROR] Testbench timeout!");
        $display("[DEBUG] Current signals:");
        $display("  awready = %b", awready);
        $display("  wready = %b", wready);  
        $display("  bvalid = %b", bvalid);
        $display("  arready = %b", arready);
        $display("  rvalid = %b", rvalid);
        $finish;
    end
    
    // Dump waveforms
    initial begin
        $dumpfile("axi_spi_master_tb.vcd");
        $dumpvars(0, axi_spi_master_tb);
    end

endmodule