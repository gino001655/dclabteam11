module Rsa256Wrapper (
    input         avm_rst,
    input         avm_clk,
    output  [4:0] avm_address,
    output        avm_read,
    input  [31:0] avm_readdata,
    output        avm_write,
    output [31:0] avm_writedata,
    input         avm_waitrequest,
    input         i_sw_17
);

localparam RX_BASE     = 0*4;
localparam TX_BASE     = 1*4;
localparam STATUS_BASE = 2*4;
localparam TX_OK_BIT   = 6;
localparam RX_OK_BIT   = 7;

localparam S_WAIT_PUBKEY = 0;
localparam S_GET_KEY = 1;
localparam S_GET_DATA = 2;
localparam S_GET_SIGNATURE = 3;
localparam S_WAIT_CALCULATE = 4;
localparam S_SEND_DATA = 5;
localparam S_REJECT = 6;
localparam S_IDLE = 7;
localparam S_SEND_MODE_RESP = 8;

logic [255:0] n_r, n_w, d_r, d_w, enc_r, enc_w, dec_r, dec_w;
logic [255:0] e_r, e_w, n_pub_r, n_pub_w, sig_r, sig_w;
logic [3:0]   state_r, state_w;
logic [6:0]   bytes_counter_r, bytes_counter_w;
logic [4:0]   avm_address_r, avm_address_w;
logic avm_read_r, avm_read_w, avm_write_r, avm_write_w;

logic pubkey_enrolled_r, pubkey_enrolled_w;

logic rsa_start_r, rsa_start_w;
logic rsa_finished;
logic verify_finished;
logic [255:0] rsa_dec;
logic [255:0] rsa_recovered_enc;

logic sw_17_r;
wire soft_rst = avm_rst | (sw_17_r ^ i_sw_17); 

assign avm_address = avm_address_r;
assign avm_read = avm_read_r;
assign avm_write = avm_write_r;
assign avm_writedata = dec_r[247-:8];

Rsa256Core rsa256_core_decrypt(
    .i_clk(avm_clk),
    .i_rst(soft_rst),
    .i_start(rsa_start_r),
    .i_a(enc_r),
    .i_d(d_r),
    .i_n(n_r),
    .o_a_pow_d(rsa_dec),
    .o_finished(rsa_finished)
);

Rsa256Core rsa256_core_verify(
    .i_clk(avm_clk),
    .i_rst(soft_rst),
    .i_start(rsa_start_r),
    .i_a(sig_r),
    .i_d(e_r),
    .i_n(n_pub_r),
    .o_a_pow_d(rsa_recovered_enc),
    .o_finished(verify_finished)
);

task StartRead;
    input [4:0] addr;
    begin
        avm_read_w = 1;
        avm_write_w = 0;
        avm_address_w = addr;
    end
endtask
task StartWrite;
    input [4:0] addr;
    begin
        avm_read_w = 0;
        avm_write_w = 1;
        avm_address_w = addr;
    end
endtask

always_comb begin
    n_w = n_r;
    d_w = d_r;
    enc_w = enc_r;
    dec_w = dec_r;
    e_w = e_r;
    n_pub_w = n_pub_r;
    sig_w = sig_r;
    pubkey_enrolled_w = pubkey_enrolled_r;

    avm_address_w = avm_address_r;
    avm_read_w = avm_read_r;
    avm_write_w = avm_write_r;
    state_w = state_r;
    bytes_counter_w = bytes_counter_r;
    rsa_start_w = rsa_start_r;

    if (state_r == S_WAIT_CALCULATE) begin
        rsa_start_w = 0;
        avm_read_w = 0;
        avm_write_w = 0;
        avm_address_w = STATUS_BASE;
        
        if (rsa_finished && (verify_finished || !i_sw_17)) begin
            if (!i_sw_17 || rsa_recovered_enc == enc_r) begin
                dec_w = rsa_dec;
                state_w = S_SEND_DATA;
                bytes_counter_w = 30; // 31 bytes total
            end else begin
                dec_w = {"Nice try Diddy.Nice try Diddy.N", 8'd0}; 
                state_w = S_REJECT;
                bytes_counter_w = 30; // 31 bytes to send
            end
            avm_read_w = 1;
            avm_write_w = 0;
            avm_address_w = STATUS_BASE;
        end
    end else begin
        if (avm_waitrequest == 0) begin
            if (avm_address_r == STATUS_BASE) begin
                if (state_r == S_WAIT_PUBKEY || state_r == S_GET_KEY || state_r == S_GET_DATA || state_r == S_GET_SIGNATURE || state_r == S_IDLE) begin
                    if (avm_readdata[RX_OK_BIT]) begin
                        StartRead(RX_BASE);
                    end
                end else if (state_r == S_SEND_DATA || state_r == S_REJECT || state_r == S_SEND_MODE_RESP) begin
                    if (avm_readdata[TX_OK_BIT]) begin
                        StartWrite(TX_BASE);
                    end
                end
            end else if (avm_address_r == RX_BASE) begin
                if (state_r == S_IDLE) begin
                    if (avm_readdata[7:0] == 8'hAA) begin
                        // Query Mode
                        dec_w = 256'b0;
                        if (i_sw_17) begin
                            dec_w[247-:8] = pubkey_enrolled_r ? 8'h02 : 8'h01;
                        end else begin
                            dec_w[247-:8] = 8'h00;
                        end
                        state_w = S_SEND_MODE_RESP;
                        bytes_counter_w = 0;
                        StartRead(STATUS_BASE);
                    end else if (avm_readdata[7:0] == 8'hBB) begin
                        // Start New Session (Enroll Pubkey)
                        if (i_sw_17 && !pubkey_enrolled_r) begin
                            state_w = S_WAIT_PUBKEY;
                            bytes_counter_w = 63;
                            pubkey_enrolled_w = 1;
                        end else begin
                            state_w = S_GET_KEY;
                            bytes_counter_w = 63;
                        end
                        StartRead(STATUS_BASE);
                    end else if (avm_readdata[7:0] == 8'hCC) begin
                        // Continue next chunk
                        state_w = S_GET_KEY;
                        bytes_counter_w = 63;
                        StartRead(STATUS_BASE);
                    end else begin
                        // Fallback for strict old python
                        if (i_sw_17) begin
                            n_pub_w = avm_readdata[7:0];
                            state_w = S_WAIT_PUBKEY;
                            bytes_counter_w = 62;
                            pubkey_enrolled_w = 1;
                        end else begin
                            n_w = avm_readdata[7:0];
                            state_w = S_GET_KEY;
                            bytes_counter_w = 62;
                        end
                        StartRead(STATUS_BASE);
                    end
                end else if (state_r == S_WAIT_PUBKEY) begin
                    if (bytes_counter_r >= 32) begin
                        n_pub_w = (n_pub_r << 8) | avm_readdata[7:0];
                    end else begin
                        e_w = (e_r << 8) | avm_readdata[7:0];
                    end
                    if (bytes_counter_r == 0) begin
                        state_w = S_GET_KEY;
                        bytes_counter_w = 63;
                        StartRead(STATUS_BASE);
                    end else begin
                        bytes_counter_w = bytes_counter_r - 1;
                        StartRead(STATUS_BASE);
                    end
                end else if (state_r == S_GET_KEY) begin
                    if (bytes_counter_r >= 32) begin
                        n_w = (n_r << 8) | avm_readdata[7:0];
                    end else begin
                        d_w = (d_r << 8) | avm_readdata[7:0];
                    end
                    if (bytes_counter_r == 0) begin
                        state_w = S_GET_DATA;
                        bytes_counter_w = 31;
                        StartRead(STATUS_BASE);
                    end else begin
                        bytes_counter_w = bytes_counter_r - 1;
                        StartRead(STATUS_BASE);
                    end
                end else if (state_r == S_GET_DATA) begin
                    enc_w = (enc_r << 8) | avm_readdata[7:0];
                    if (bytes_counter_r == 0) begin
                        if(i_sw_17) begin
                            state_w = S_GET_SIGNATURE; 
                            bytes_counter_w = 31;
                            StartRead(STATUS_BASE);
                        end else begin
                            state_w = S_WAIT_CALCULATE; 
                            rsa_start_w = 1;
                        end
                    end else begin
                        bytes_counter_w = bytes_counter_r - 1;
                        StartRead(STATUS_BASE);
                    end
                end else if (state_r == S_GET_SIGNATURE) begin
                    sig_w = (sig_r << 8) | avm_readdata[7:0];
                    if (bytes_counter_r == 0) begin
                        state_w = S_WAIT_CALCULATE; 
                        rsa_start_w = 1;
                    end else begin
                        bytes_counter_w = bytes_counter_r - 1;
                        StartRead(STATUS_BASE);
                    end
                end
            end else if (avm_address_r == TX_BASE) begin
                if (state_r == S_SEND_MODE_RESP) begin
                    state_w = S_IDLE;
                    StartRead(STATUS_BASE);
                end else begin
                    dec_w = dec_r << 8;
                    if (bytes_counter_r == 0) begin
                        state_w = S_IDLE; 
                        n_w = 256'b0; 
                        d_w = 256'b0;
                        enc_w = 256'b0;
                        sig_w = 256'b0;
                    end else begin
                        bytes_counter_w = bytes_counter_r - 1;
                    end
                    StartRead(STATUS_BASE);
                end
            end
        end
    end
end

always_ff @(posedge avm_clk or posedge avm_rst) begin
    if (avm_rst) begin
        sw_17_r <= 0;
        n_r <= 0;
        d_r <= 0;
        enc_r <= 0;
        dec_r <= 0;
        e_r <= 0;
        n_pub_r <= 0;
        sig_r <= 0;
        pubkey_enrolled_r <= 0;
        avm_address_r <= STATUS_BASE;
        avm_read_r <= 1;
        avm_write_r <= 0;
        state_r <= S_IDLE;
        bytes_counter_r <= 63;
        rsa_start_r <= 0;
    end else begin
        sw_17_r <= i_sw_17;
        
        // Synchronous soft reset on toggle
        if (sw_17_r ^ i_sw_17) begin
            n_r <= 0;
            d_r <= 0;
            enc_r <= 0;
            dec_r <= 0;
            e_r <= 0;
            n_pub_r <= 0;
            sig_r <= 0;
            pubkey_enrolled_r <= 0;
            avm_address_r <= STATUS_BASE;
            avm_read_r <= 1;
            avm_write_r <= 0;
            state_r <= S_IDLE; 
            bytes_counter_r <= 63;
            rsa_start_r <= 0;
        end else begin
            n_r <= n_w;
            d_r <= d_w;
            enc_r <= enc_w;
            dec_r <= dec_w;
            e_r <= e_w;
            n_pub_r <= n_pub_w;
            sig_r <= sig_w;
            pubkey_enrolled_r <= pubkey_enrolled_w;
            avm_address_r <= avm_address_w;
            avm_read_r <= avm_read_w;
            avm_write_r <= avm_write_w;
            state_r <= state_w;
            bytes_counter_r <= bytes_counter_w;
            rsa_start_r <= rsa_start_w;
        end
    end
end

endmodule
