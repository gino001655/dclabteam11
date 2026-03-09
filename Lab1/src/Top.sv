module Top (
	input        i_clk,
	input        i_rst_n,
	input        i_start,
	output [3:0] o_random_out
);

// ===== States =====
parameter S_IDLE = 1'b0;
parameter S_PROC = 1'b1;

// ===== Output Buffers =====
logic [3:0] o_random_out_r, o_random_out_w;

// ===== Registers & Wires =====
logic state_r, state_w;
logic [25:0] count_r, count_w; // 我要用這個來數clock posedge了幾次
logic [3:0] random_r, random_w;
logic [3:0] num_r, num_w;
logic [25:0] target_r, target_w; // 用來減速的

// ===== Output Assignments =====
assign o_random_out = o_random_out_r;

// ===== Combinational Circuits =====
always_comb begin
	// Default Values
	o_random_out_w = o_random_out_r;
	state_w        = state_r;
	count_w		   = count_r +26'd1;
	random_w 	   = {random_r[2:0], random_r[3]^random_r[2]};
	num_w		   = num_r;
	target_w       = target_r;
	// FSM
	case(state_r)
	S_IDLE: begin
		if (i_start) begin
			state_w = S_PROC;
			count_w = 26'd0;
			num_w = 4'd0;
			target_w = 26'd5000000;
		end
	end

	S_PROC: begin
		if ( num_r < 10 ) begin
			if (count_r == target_r) begin
				o_random_out_w = random_r;
				num_w = num_r + 4'd1;
				count_w = 26'd0;
				target_w = target_r + 26'd5000000;
			end
		end
		else begin
			state_w = S_IDLE;
		end
	end
	endcase

end

// ===== Sequential Circuits =====
always_ff @(posedge i_clk or negedge i_rst_n) begin
	// reset
	if (!i_rst_n) begin
		o_random_out_r <= 4'd0;
		state_r        <= S_IDLE;
		count_r		   <= 26'd0;
		random_r 	   <= 4'd15;
		num_r		   <= 4'd0;
		target_r       <= 26'd5000000;
	end
	else begin
		o_random_out_r <= o_random_out_w;
		state_r        <= state_w;
		count_r		   <= count_w;
		random_r	   <= random_w;
		num_r		   <= num_w;
		target_r       <= target_w;
	end
end

endmodule