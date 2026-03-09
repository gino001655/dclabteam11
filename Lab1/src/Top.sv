module Top (
	input        i_clk,
	input        i_rst_n,
	input        i_start,
	output [3:0] o_random_out
);

// ===== States =====
parameter S_IDLE = 1'b0;
parameter S_RUN  = 1'b1;

// ===== Parameters for 50MHz Clock (DE2-115) =====
// Base delay: 0.05s, Step: 0.015s increase, Max delay: 0.3s
localparam SPEED_INIT = 26'd2_500_000;
localparam SPEED_STEP = 26'd750_000;
localparam SPEED_MAX  = 26'd15_000_000;

// ===== Registers & Wires =====
logic [15:0] lfsr_r, lfsr_w;    // For Random Number Generation
logic state_r, state_w;
logic [25:0] count_r, count_w;  // Timer counter
logic [25:0] speed_r, speed_w;  // Current frequency delay
logic [3:0]  out_r, out_w;      // Output buffer

// ===== Output Assignments =====
assign o_random_out = out_r;

// ===== Combinational Circuits =====
always_comb begin
    // Default Values
    lfsr_w  = {lfsr_r[14:0], lfsr_r[15] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10]};
    state_w = state_r;
    count_w = count_r;
    speed_w = speed_r;
    out_w   = out_r;

    // FSM
    case(state_r)
        S_IDLE: begin
            if (i_start) begin
                state_w = S_RUN;
                speed_w = SPEED_INIT;
                count_w = 0;
                out_w   = lfsr_r[3:0]; // Initial jump
            end
        end

        S_RUN: begin
            if (i_start) begin // Bonus: restart random process instantly
                speed_w = SPEED_INIT;
                count_w = 0;
            end else begin
                count_w = count_r + 1;
                if (count_r >= speed_r) begin
                    count_w = 0;
                    out_w   = lfsr_r[3:0];
                    
                    if (speed_r >= SPEED_MAX) begin
                        state_w = S_IDLE; // Stop at this random number
                    end else begin
                        speed_w = speed_r + SPEED_STEP; // Slow down
                    end
                end
            end
        end
    endcase
end

// ===== Sequential Circuits =====
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        lfsr_r  <= 16'hACE1;  // Non-zero seed
        state_r <= S_IDLE;
        count_r <= '0;
        speed_r <= '0;
        out_r   <= '0;
    end
    else begin
        lfsr_r  <= lfsr_w;
        state_r <= state_w;
        count_r <= count_w;
        speed_r <= speed_w;
        out_r   <= out_w;
    end
end

endmodule
