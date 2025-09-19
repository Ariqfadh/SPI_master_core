`timescale 1ns / 1ps

module tb_axi_spi_wrapper;

  // Clock & reset
  reg ACLK;
  reg ARESETN;

  // AXI4-Lite signals
  reg  [31:0] S_AXI_AWADDR;
  reg         S_AXI_AWVALID;
  wire        S_AXI_AWREADY;

  reg  [31:0] S_AXI_WDATA;
  reg  [3:0]  S_AXI_WSTRB;
  reg         S_AXI_WVALID;
  wire        S_AXI_WREADY;

  wire [1:0]  S_AXI_BRESP;
  wire        S_AXI_BVALID;
  reg         S_AXI_BREADY;

  reg  [31:0] S_AXI_ARADDR;
  reg         S_AXI_ARVALID;
  wire        S_AXI_ARREADY;

  wire [31:0] S_AXI_RDATA;
  wire [1:0]  S_AXI_RRESP;
  wire        S_AXI_RVALID;
  reg         S_AXI_RREADY;

  reg [31:0] rdata;
  // SPI signals
  wire MOSI;
  reg  MISO;
  wire SCK;
  wire CS;

  // Clock generation
  initial ACLK = 0;
  always #5 ACLK = ~ACLK; // 100 MHz

  // Instantiate wrapper
  axi_spi_master DUT (
    .ACLK(ACLK),
    .ARESETN(ARESETN),
    .S_AXI_AWADDR(S_AXI_AWADDR),
    .S_AXI_AWVALID(S_AXI_AWVALID),
    .S_AXI_AWREADY(S_AXI_AWREADY),
    .S_AXI_WDATA(S_AXI_WDATA),
    .S_AXI_WSTRB(S_AXI_WSTRB),
    .S_AXI_WVALID(S_AXI_WVALID),
    .S_AXI_WREADY(S_AXI_WREADY),
    .S_AXI_BRESP(S_AXI_BRESP),
    .S_AXI_BVALID(S_AXI_BVALID),
    .S_AXI_BREADY(S_AXI_BREADY),
    .S_AXI_ARADDR(S_AXI_ARADDR),
    .S_AXI_ARVALID(S_AXI_ARVALID),
    .S_AXI_ARREADY(S_AXI_ARREADY),
    .S_AXI_RDATA(S_AXI_RDATA),
    .S_AXI_RRESP(S_AXI_RRESP),
    .S_AXI_RVALID(S_AXI_RVALID),
    .S_AXI_RREADY(S_AXI_RREADY),
    .MOSI(MOSI),
    .MISO(MISO),
    .SCK(SCK),
    .CS(CS)
  );

  // Reset logic
  initial begin
    ARESETN = 0;
    S_AXI_AWADDR = 0;
    S_AXI_AWVALID = 0;
    S_AXI_WDATA = 0;
    S_AXI_WSTRB = 4'b1111;
    S_AXI_WVALID = 0;
    S_AXI_BREADY = 0;
    S_AXI_ARADDR = 0;
    S_AXI_ARVALID = 0;
    S_AXI_RREADY = 0;
    MISO = 0;

    #100;
    ARESETN = 1;
  end

  // AXI Write task
  task axi_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      @(posedge ACLK);
      S_AXI_AWADDR  <= addr;
      S_AXI_AWVALID <= 1;
      S_AXI_WDATA   <= data;
      S_AXI_WVALID  <= 1;
      S_AXI_BREADY  <= 1;
      wait(S_AXI_AWREADY && S_AXI_WREADY);
      @(posedge ACLK);
      S_AXI_AWVALID <= 0;
      S_AXI_WVALID  <= 0;
      wait(S_AXI_BVALID);
      @(posedge ACLK);
      S_AXI_BREADY <= 0;
    end
  endtask

  // AXI Read task
  task axi_read;
    input  [31:0] addr;
    output [31:0] data;
    begin
      @(posedge ACLK);
      S_AXI_ARADDR  <= addr;
      S_AXI_ARVALID <= 1;
      S_AXI_RREADY  <= 1;
      wait(S_AXI_ARREADY);
      @(posedge ACLK);
      S_AXI_ARVALID <= 0;
      wait(S_AXI_RVALID);
      data = S_AXI_RDATA;
      @(posedge ACLK);
      S_AXI_RREADY <= 0;
    end
  endtask

  // Main stimulus
  initial begin
    @(posedge ARESETN);
    #20;

    // Write contoh data ke register transmit 
    axi_write(32'h00000000, 32'hA5);

    // Read balik dari register status/data
    axi_read(32'h00000004, rdata);
    $display("Read Data: %h", rdata);

    // Simulasi MISO loopback
    forever begin
      @(negedge SCK);
      MISO <= MOSI; // loopback langsung
    end
  end

  // Monitor SPI activity
  initial begin
    $monitor("Time=%0t CS=%b SCK=%b MOSI=%b MISO=%b", $time, CS, SCK, MOSI, MISO);
  end

endmodule
