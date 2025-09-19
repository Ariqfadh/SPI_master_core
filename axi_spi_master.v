`timescale 1 ns / 1 ps

module axi_spi_master #
(
  parameter integer C_S_AXI_DATA_WIDTH = 32,
  parameter integer C_S_AXI_ADDR_WIDTH = 4
)
(
  // AXI4-Lite signals
  input  wire                               S_AXI_ACLK,
  input  wire                               S_AXI_ARESETN,
  input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]    S_AXI_AWADDR,
  input  wire                               S_AXI_AWVALID,
  output reg                                S_AXI_AWREADY,
  input  wire [C_S_AXI_DATA_WIDTH-1 : 0]    S_AXI_WDATA,
  input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]  S_AXI_WSTRB,
  input  wire                               S_AXI_WVALID,
  output reg                                S_AXI_WREADY,
  output reg [1 : 0]                        S_AXI_BRESP,
  output reg                                S_AXI_BVALID,
  input  wire                               S_AXI_BREADY,
  input  wire [C_S_AXI_ADDR_WIDTH-1 : 0]    S_AXI_ARADDR,
  input  wire                               S_AXI_ARVALID,
  output reg                                S_AXI_ARREADY,
  output reg [C_S_AXI_DATA_WIDTH-1 : 0]     S_AXI_RDATA,
  output reg [1 : 0]                        S_AXI_RRESP,
  output reg                                S_AXI_RVALID,
  input  wire                               S_AXI_RREADY,

  // SPI pins
  output wire spi_mosi,
  input  wire spi_miso,
  output wire spi_sclk,
  output wire spi_cs
);

  //-------------------------------------------------------
  // Register Map
  // 0x00 : TXDATA (write-only, lower 8 bits)
  // 0x04 : RXDATA (read-only, lower 8 bits)
  // 0x08 : CLKDIV (write/read, lower 16 bits)
  // 0x0C : STATUS (bit0=ready, bit1=busy, bit2=done, bit3=irq)
  //-------------------------------------------------------

  reg [7:0]  tx_reg;
  reg [7:0]  rx_reg;
  reg [15:0] clkdiv_reg;

  reg        start_pulse;

  wire [7:0] core_rx;
  wire       core_ready, core_busy, core_done, core_irq;

  //-------------------------------------------------------
  // SPI Master instance
  //-------------------------------------------------------
  spi_master spi_inst (
    .clk       (S_AXI_ACLK),
    .reset     (~S_AXI_ARESETN),

    .start     (start_pulse),
    .tx_data   (tx_reg),
    .clk_div_in(clkdiv_reg),
    .rx_data   (core_rx),
    .ready     (core_ready),
    .busy      (core_busy),
    .done      (core_done),
    .irq       (core_irq),

    .miso      (spi_miso),
    .mosi      (spi_mosi),
    .sclk      (spi_sclk),
    .cs        (spi_cs)
  );

  //-------------------------------------------------------
  // AXI4-Lite Slave Logic
  //-------------------------------------------------------
  reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
  reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;

  // Write Address
  always @(posedge S_AXI_ACLK) begin
    if(~S_AXI_ARESETN) begin
      S_AXI_AWREADY <= 0;
      axi_awaddr <= 0;
    end else begin
      if(~S_AXI_AWREADY && S_AXI_AWVALID && S_AXI_WVALID) begin
        S_AXI_AWREADY <= 1;
        axi_awaddr    <= S_AXI_AWADDR;
      end else begin
        S_AXI_AWREADY <= 0;
      end
    end
  end

  // Write Data
  always @(posedge S_AXI_ACLK) begin
    if(~S_AXI_ARESETN) begin
      S_AXI_WREADY <= 0;
      tx_reg       <= 0;
      clkdiv_reg   <= 4;
      start_pulse  <= 0;
    end else begin
      S_AXI_WREADY <= 0;
      start_pulse  <= 0;
      if(~S_AXI_WREADY && S_AXI_WVALID && S_AXI_AWVALID) begin
        S_AXI_WREADY <= 1;
        case(axi_awaddr[3:2])
          2'b00: begin
            tx_reg      <= S_AXI_WDATA[7:0];
            start_pulse <= 1; 
          end
          2'b10: clkdiv_reg <= S_AXI_WDATA[15:0];
          default: ;
        endcase
      end
    end
  end

  // Write Response
  always @(posedge S_AXI_ACLK) begin
    if(~S_AXI_ARESETN) begin
      S_AXI_BVALID <= 0;
      S_AXI_BRESP  <= 2'b00;
    end else begin
      if(S_AXI_AWREADY && S_AXI_AWVALID && ~S_AXI_BVALID && S_AXI_WREADY && S_AXI_WVALID) begin
        S_AXI_BVALID <= 1;
        S_AXI_BRESP  <= 2'b00;
      end else if(S_AXI_BREADY && S_AXI_BVALID) begin
        S_AXI_BVALID <= 0;
      end
    end
  end

  // Read Address
  always @(posedge S_AXI_ACLK) begin
    if(~S_AXI_ARESETN) begin
      S_AXI_ARREADY <= 0;
      axi_araddr    <= 0;
    end else begin
      if(~S_AXI_ARREADY && S_AXI_ARVALID) begin
        S_AXI_ARREADY <= 1;
        axi_araddr    <= S_AXI_ARADDR;
      end else begin
        S_AXI_ARREADY <= 0;
      end
    end
  end

  // Read Data
  always @(posedge S_AXI_ACLK) begin
    if(~S_AXI_ARESETN) begin
      S_AXI_RVALID <= 0;
      S_AXI_RRESP  <= 0;
      S_AXI_RDATA  <= 0;
    end else begin
      if(S_AXI_ARREADY && S_AXI_ARVALID && ~S_AXI_RVALID) begin
        S_AXI_RVALID <= 1;
        S_AXI_RRESP  <= 2'b00;
        case(axi_araddr[3:2])
          2'b00: S_AXI_RDATA <= {24'h0, tx_reg};
          2'b01: S_AXI_RDATA <= {24'h0, core_rx};
          2'b10: S_AXI_RDATA <= {16'h0, clkdiv_reg};
          2'b11: S_AXI_RDATA <= {28'h0, core_irq, core_done, core_busy, core_ready};
          default: S_AXI_RDATA <= 0;
        endcase
      end else if(S_AXI_RVALID && S_AXI_RREADY) begin
        S_AXI_RVALID <= 0;
      end
    end
  end

endmodule
