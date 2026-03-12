module Top (
	input        i_clk,
	input        i_rst_n,
	input        i_start,
	input  [3:0] i_p1_guess,
	input  [3:0] i_p2_guess,
	output [3:0] o_random_out,
	output [3:0] o_p1_out,
	output [3:0] o_p2_out,
	output       o_p1_blink,
	output       o_p2_blink,
	output [3:0] o_random_capture,
	output [3:0] o_random_prev
);

// ===== States =====
parameter S_IDLE = 2'd0;
parameter S_RUN  = 2'd1;
parameter S_DONE = 2'd2;

// ===== Parameters for 50MHz Clock (DE2-115) =====
// Base delay: 0.05s, Step: 0.015s increase, Max delay: 0.3s
localparam SPEED_INIT = 26'd2_500_000;
localparam SPEED_STEP = 26'd750_000;
localparam SPEED_MAX  = 26'd15_000_000;
// Blink frequency: ~0.5s toggle
localparam BLINK_MAX  = 26'd25_000_000;

// ===== Registers & Wires =====
logic [15:0] lfsr_r, lfsr_w;    // For Random Number Generation
logic [1:0]  state_r, state_w;
logic [25:0] count_r, count_w;  // Timer counter
logic [25:0] speed_r, speed_w;  // Current frequency delay
logic [3:0]  out_r, out_w;      // Output buffer
logic [3:0]  capture_r, capture_w; // Captured random number
logic [3:0]  prev_r, prev_w;       // Previous random number

logic [3:0]  p1_guess_r, p1_guess_w;
logic [3:0]  p2_guess_r, p2_guess_w;
logic [25:0] blink_cnt_r, blink_cnt_w;
logic        blink_state_r, blink_state_w;
logic        p1_blink_r, p1_blink_w;
logic        p2_blink_r, p2_blink_w;

logic [4:0]  dist1, dist2;

// ===== Output Assignments =====
assign o_random_out = out_r;
assign o_p1_out     = p1_guess_r;
assign o_p2_out     = p2_guess_r;
assign o_p1_blink   = p1_blink_r;
assign o_p2_blink   = p2_blink_r;
assign o_random_capture = capture_r;
assign o_random_prev = prev_r;

// ===== Combinational Circuits =====
always_comb begin
    // Default Values
    lfsr_w        = {lfsr_r[14:0], lfsr_r[15] ^ lfsr_r[13] ^ lfsr_r[12] ^ lfsr_r[10]};
    state_w       = state_r;
    count_w       = count_r;
    speed_w       = speed_r;
    out_w         = out_r;
    capture_w     = capture_r;
    prev_w        = prev_r;
    
    p1_guess_w    = p1_guess_r;
    p2_guess_w    = p2_guess_r;
    blink_cnt_w   = blink_cnt_r;
    blink_state_w = blink_state_r;
    p1_blink_w    = p1_blink_r;
    p2_blink_w    = p2_blink_r;

    // Distance calculation (using 5 bits to avoid underflow/overflow issues)
    dist1 = (out_r > p1_guess_r) ? (out_r - p1_guess_r) : (p1_guess_r - out_r);
    dist2 = (out_r > p2_guess_r) ? (out_r - p2_guess_r) : (p2_guess_r - out_r);

    // FSM
    case(state_r)
        S_IDLE: begin
            // Read players' guesses constantly until game starts
            p1_guess_w = i_p1_guess;
            p2_guess_w = i_p2_guess;
            p1_blink_w = 1'b0;
            p2_blink_w = 1'b0;
            blink_state_w = 1'b1;
            blink_cnt_w = '0;

            if (i_start) begin
                state_w = S_RUN;
                speed_w = SPEED_INIT;
                count_w = 0;
                out_w   = lfsr_r[3:0]; // Initial jump
                prev_w  = out_r;       // Bonus: 記憶前次亂數結果
            end
        end

        S_RUN: begin
            if (i_start) begin // Restart random process instantly & 擷取中途亂數
                speed_w   = SPEED_INIT;
                count_w   = 0;
                capture_w = out_r;      // Bonus: 記錄擷取的亂數
            end else begin
                count_w = count_r + 1;
                if (count_r >= speed_r) begin
                    count_w = 0;
                    out_w   = lfsr_r[3:0];
                    
                    if (speed_r >= SPEED_MAX) begin
                        state_w = S_DONE; // Stop at this random number
                    end else begin
                        speed_w = speed_r + SPEED_STEP; // Slow down
                    end
                end
            end
        end

        S_DONE: begin
            // Blinking logic counter
            if (blink_cnt_r >= BLINK_MAX) begin
                blink_cnt_w = '0;
                blink_state_w = ~blink_state_r;
            end else begin
                blink_cnt_w = blink_cnt_r + 1;
            end

            // Determine winner(s)
            if (dist1 < dist2) begin
                p1_blink_w = blink_state_r;
                p2_blink_w = 1'b0;
            end else if (dist2 < dist1) begin
                p2_blink_w = blink_state_r;
                p1_blink_w = 1'b0;
            end else begin
                p1_blink_w = blink_state_r;
                p2_blink_w = blink_state_r;
            end

            if (i_start) begin
                state_w = S_IDLE; // Reset game
            end
        end
    endcase
end

// ===== Sequential Circuits =====
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        lfsr_r        <= 16'hACE1;  // Non-zero seed
        state_r       <= S_IDLE;
        count_r       <= '0;
        speed_r       <= '0;
        out_r         <= '0;
        capture_r     <= '0;
        prev_r        <= '0;
        p1_guess_r    <= '0;
        p2_guess_r    <= '0;
        blink_cnt_r   <= '0;
        blink_state_r <= 1'b0;
        p1_blink_r    <= 1'b0;
        p2_blink_r    <= 1'b0;
    end
    else begin
        lfsr_r        <= lfsr_w;
        state_r       <= state_w;
        count_r       <= count_w;
        speed_r       <= speed_w;
        out_r         <= out_w;
        capture_r     <= capture_w;
        prev_r        <= prev_w;
        p1_guess_r    <= p1_guess_w;
        p2_guess_r    <= p2_guess_w;
        blink_cnt_r   <= blink_cnt_w;
        blink_state_r <= blink_state_w;
        p1_blink_r    <= p1_blink_w;
        p2_blink_r    <= p2_blink_w;
    end
end

endmodule
