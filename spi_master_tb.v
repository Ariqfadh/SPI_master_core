`timescale 1ns/1ps

module spi_master_tb;

  reg clk;
  reg reset;
  reg start;
  reg miso;
  reg [7:0] tx_data;
  wire [7:0] rx_data;
  wire busy, done;
  wire mosi, sclk, cs;

  // DUT instantiation
  spi_master #(
    .clk_div(4)
  ) dut (
    .clk     (clk),
    .reset   (reset),
    .start   (start),
    .tx_data (tx_data),
    .rx_data (rx_data),
    .busy    (busy),
    .done    (done),
    .miso    (miso),
    .mosi    (mosi),
    .sclk    (sclk),
    .cs      (cs)
  );

  always #5 clk = ~clk;  // 100 MHz

  // Loop back test
  always @(negedge sclk) begin
    if (!cs)
      miso <= mosi;
  end

  initial begin
    $dumpfile("spi_master_tb.vcd");
    $dumpvars(0, spi_master_tb);

    // Init
    clk   = 0;
    reset = 1;
    start = 0;
    tx_data = 8'h00;
    miso = 0;

    #20 reset = 0;

    // Kirim data
    #20;
    tx_data = 8'hA5;   // data test
    start   = 1;
    #10;
    start   = 0;

    wait(done);
    $display("Data terkirim: 0x%0h, Data diterima: 0x%0h", tx_data, rx_data);

    #50;
    $finish;
  end

endmodule
