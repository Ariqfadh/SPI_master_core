`timescale 1ns/1ps

module spi_master_tb;

  reg clk;
  reg reset;
  reg start;
  reg miso;
  reg [7:0] tx_data;
  reg [15:0] clk_div_in;
  wire [7:0] rx_data;
  wire ready, busy, done, irq;
  wire mosi, sclk, cs;

  // DUT instantiation
  spi_master #(
    .DEFAULT_CLK_DIV(4)
  ) dut (
    .clk        (clk),
    .reset      (reset),
    .start      (start),
    .tx_data    (tx_data),
    .clk_div_in (clk_div_in),
    .rx_data    (rx_data),
    .ready      (ready),
    .busy       (busy),
    .done       (done),
    .irq        (irq),
    .miso       (miso),
    .mosi       (mosi),
    .sclk       (sclk),
    .cs         (cs)
  );

  // Clock generator: 100 MHz
  always #5 clk = ~clk;

  // Loopback MISO from MOSI
  always @(negedge sclk) begin
    if (!cs)
      miso <= mosi;
  end

  initial begin
    $dumpfile("spi_master_tb.vcd");
    $dumpvars(0, spi_master_tb);

    // Init
    clk        = 0;
    reset      = 1;
    start      = 0;
    tx_data    = 8'h00;
    clk_div_in = 16'd0;
    miso       = 0;

    #20 reset = 0;

    // Send first byte
    #20;
    tx_data = 8'hA5;
    start   = 1;
    #10 start = 0;

    wait(done);
    $display("Sent: 0x%0h, Received: 0x%0h", tx_data, rx_data);

    if (tx_data == rx_data)
      $display(" Test Passed");
    else
      $display(" Test Failed");

    #50;

    //Other type
    tx_data = 8'h3C;
    start   = 1;
    #10 start = 0;

    wait(done);
    $display("Sent: 0x%0h, Received: 0x%0h", tx_data, rx_data);
        if (tx_data == rx_data)
      $display("Test Passed");
    else
      $display("Test Failed");

    #50;
    $finish;
  end

endmodule
