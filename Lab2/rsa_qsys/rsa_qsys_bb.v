
module rsa_qsys (
	clk_clk,
	reset_reset_n,
	uart_0_external_connection_rxd,
	uart_0_external_connection_txd,
	sw_mode_beginbursttransfer);	

	input		clk_clk;
	input		reset_reset_n;
	input		uart_0_external_connection_rxd;
	output		uart_0_external_connection_txd;
	input		sw_mode_beginbursttransfer;
endmodule
