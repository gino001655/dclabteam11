module Rsa256Core (
	input          i_clk,
	input          i_rst,
	input          i_start,
	input  [255:0] i_a, // cipher text y
	input  [255:0] i_d, // private key
	input  [255:0] i_n,
	output [255:0] o_a_pow_d, // plain text x
	output         o_finished
);

    logic [255:0] t_reg, t_next;
    logic [255:0] m_reg, m_next;
    logic [8:0] count_reg, count_next;
    
    logic prep1_start, prep2_start;
    logic [255:0] prep1_a, prep2_a;
    logic [255:0] prep1_out, prep2_out;
    logic prep1_finished, prep2_finished;
    
    RsaPrep prep1(
        .clk(i_clk), .rst(i_rst), .start(prep1_start),
        .a(prep1_a), .n(i_n),
        .out(prep1_out), .finished(prep1_finished)
    );
    
    RsaPrep prep2(
        .clk(i_clk), .rst(i_rst), .start(prep2_start),
        .a(prep2_a), .n(i_n),
        .out(prep2_out), .finished(prep2_finished)
    );
    
    logic mont1_start, mont2_start;
    logic [255:0] mont1_a, mont1_b, mont2_a, mont2_b;
    logic [255:0] mont1_out, mont2_out;
    logic mont1_finished, mont2_finished;
    
    RsaMont mont1(
        .clk(i_clk), .rst(i_rst), .start(mont1_start),
        .a(mont1_a), .b(mont1_b), .n(i_n),
        .out(mont1_out), .finished(mont1_finished)
    );
    
    RsaMont mont2(
        .clk(i_clk), .rst(i_rst), .start(mont2_start),
        .a(mont2_a), .b(mont2_b), .n(i_n),
        .out(mont2_out), .finished(mont2_finished)
    );

    typedef enum logic [2:0] {
        IDLE,
        PREP_WAIT,
        MONT_CALC,
        MONT_WAIT,
        MONT_LAST,
        MONT_LAST_WAIT,
        FINISH
    } state_t;

    state_t state_reg, state_next;

    assign o_a_pow_d = m_reg;
    assign o_finished = (state_reg == FINISH);

    always_comb begin
        state_next = state_reg;
        t_next = t_reg;
        m_next = m_reg;
        count_next = count_reg;
        
        prep1_start = 0;
        prep2_start = 0;
        prep1_a = i_a;
        prep2_a = 256'd1;
        
        mont1_start = 0;
        mont2_start = 0;
        mont1_a = m_reg;
        mont1_b = t_reg;
        mont2_a = t_reg;
        mont2_b = t_reg;
        
        case(state_reg)
            IDLE: begin
                if(i_start) begin
                    prep1_start = 1;
                    prep2_start = 1;
                    state_next = PREP_WAIT;
                end
            end
            PREP_WAIT: begin
                if(prep1_finished && prep2_finished) begin
                    t_next = prep1_out;
                    m_next = prep2_out;
                    count_next = 0;
                    state_next = MONT_CALC;
                end
            end
            MONT_CALC: begin
                mont1_start = 1;
                mont2_start = 1;
                state_next = MONT_WAIT;
            end
            MONT_WAIT: begin
                if(mont1_finished && mont2_finished) begin
                    t_next = mont2_out;
                    if(i_d[count_reg]) begin
                        m_next = mont1_out;
                    end
                    count_next = count_reg + 1;
                    if(count_reg == 255) begin
                        state_next = MONT_LAST;
                    end else begin
                        state_next = MONT_CALC;
                    end
                end
            end
            MONT_LAST: begin
                mont1_start = 1; // mont1_a = m_reg, mont1_b = 1
                state_next = MONT_LAST_WAIT;
            end
            MONT_LAST_WAIT: begin
                mont1_a = m_reg;
                mont1_b = 256'd1;
                if(mont1_finished) begin
                    m_next = mont1_out;
                    state_next = FINISH;
                end
            end
            FINISH: begin
                state_next = IDLE;
            end
        endcase
    end
    
    // In MONT_LAST and MONT_LAST_WAIT, we override the default mont inputs
    always_comb begin
        if (state_reg == MONT_LAST || state_reg == MONT_LAST_WAIT) begin
            mont1_a = m_reg;
            mont1_b = 256'd1;
        end else begin
            mont1_a = m_reg;
            mont1_b = t_reg;
        end
    end

    always_ff @(posedge i_clk or posedge i_rst) begin
        if(i_rst) begin
            state_reg <= IDLE;
            t_reg <= 0;
            m_reg <= 0;
            count_reg <= 0;
        end else begin
            state_reg <= state_next;
            t_reg <= t_next;
            m_reg <= m_next;
            count_reg <= count_next;
        end
    end

endmodule

module RsaPrep(
    input clk,
    input rst,
    input start,
    input [255:0] a,
    input [255:0] n,
    output logic [255:0] out,
    output logic finished
);
    logic [256:0] t_reg, t_next;
    logic [8:0] count_reg, count_next;
    logic state_reg, state_next;
    
    always_comb begin
        t_next = t_reg;
        count_next = count_reg;
        state_next = state_reg;
        finished = 0;
        out = 0;
        
        case(state_reg)
            0: begin
                if(start) begin
                    t_next = a;
                    count_next = 0;
                    state_next = 1;
                end
            end
            1: begin
                if(count_reg < 256) begin
                    logic [257:0] t_shift;
                    t_shift = t_reg << 1;
                    if(t_shift >= n) begin
                        t_next = t_shift - n;
                    end else begin
                        t_next = t_shift;
                    end
                    count_next = count_reg + 1;
                end else begin
                    finished = 1;
                    out = t_reg[255:0];
                    if(start) begin
                        t_next = a;
                        count_next = 0;
                        state_next = 1;
                    end else begin
                        state_next = 0;
                    end
                end
            end
        endcase
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            t_reg <= 0;
            count_reg <= 0;
            state_reg <= 0;
        end else begin
            t_reg <= t_next;
            count_reg <= count_next;
            state_reg <= state_next;
        end
    end
endmodule

module RsaMont(
    input clk,
    input rst,
    input start,
    input [255:0] a,
    input [255:0] b,
    input [255:0] n,
    output logic [255:0] out,
    output logic finished
);
    logic [257:0] m_reg, m_next;
    logic [8:0] count_reg, count_next;
    logic [257:0] a_reg;
    logic state_reg, state_next;
    
    always_comb begin
        m_next = m_reg;
        count_next = count_reg;
        state_next = state_reg;
        finished = 0;
        out = 0;
        
        case(state_reg)
            0: begin
                if(start) begin
                    m_next = 0;
                    count_next = 0;
                    state_next = 1;
                end
            end
            1: begin
                if(count_reg < 256) begin
                    logic [257:0] add_a;
                    logic [257:0] cur_m;
                    add_a = (b[count_reg]) ? a_reg : 0;
                    cur_m = m_reg + add_a;
                    if(cur_m[0]) begin
                        m_next = (cur_m + n) >> 1;
                    end else begin
                        m_next = cur_m >> 1;
                    end
                    count_next = count_reg + 1;
                end else begin
                    finished = 1;
                    if(m_reg >= n) out = m_reg - n;
                    else out = m_reg;
                    if(start) begin
                        m_next = 0;
                        count_next = 0;
                        state_next = 1;
                    end else begin
                        state_next = 0;
                    end
                end
            end
        endcase
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            m_reg <= 0;
            count_reg <= 0;
            state_reg <= 0;
            a_reg <= 0;
        end else begin
            if (start && (state_reg == 0 || (state_reg == 1 && count_reg >= 256))) begin
                a_reg <= a;
            end
            m_reg <= m_next;
            count_reg <= count_next;
            state_reg <= state_next;
        end
    end
endmodule
