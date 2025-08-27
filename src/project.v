/*
 * Copyright (c) 2025 Ascon-128 AEAD Implementation
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_ascon_aead (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Ascon-128 AEAD Core Parameters
    localparam STATE_WIDTH = 320;   // 5 x 64-bit words
    localparam KEY_WIDTH = 128;
    localparam NONCE_WIDTH = 128;
    localparam TAG_WIDTH = 128;
    localparam RATE = 64;           // Data rate in bits
    
    // Control states
    typedef enum logic [3:0] {
        IDLE        = 4'b0000,
        LOAD_KEY    = 4'b0001,
        LOAD_NONCE  = 4'b0010,
        INIT        = 4'b0011,
        PROC_AAD    = 4'b0100,
        PROC_PT     = 4'b0101,
        FINALIZE    = 4'b0110,
        OUTPUT_CT   = 4'b0111,
        OUTPUT_TAG  = 4'b1000,
        DONE        = 4'b1001
    } state_t;
    
    // Registers
    state_t current_state, next_state;
    logic [STATE_WIDTH-1:0] ascon_state;
    logic [KEY_WIDTH-1:0] key_reg;
    logic [NONCE_WIDTH-1:0] nonce_reg;
    logic [TAG_WIDTH-1:0] tag_reg;
    logic [7:0] input_buffer [15:0];  // Input buffer for data assembly
    logic [3:0] buffer_count;
    logic [7:0] output_data;
    logic data_ready;
    logic operation_complete;
    
    // Ascon round constants (first 12 constants for p12, first 8 for p8)
    localparam logic [7:0] ROUND_CONSTANTS [11:0] = '{
        8'hf0, 8'he1, 8'hd2, 8'hc3, 8'hb4, 8'ha5,
        8'h96, 8'h87, 8'h78, 8'h69, 8'h5a, 8'h4b
    };
    
    // Ascon IV for AEAD128
    localparam logic [63:0] ASCON_IV = 64'h80400c0600000000;
    
    // Input/Output control signals
    logic start_operation;
    logic [1:0] operation_mode;  // 00: encrypt, 01: decrypt
    logic input_valid;
    logic output_valid;
    
    // Extract control signals from inputs
    assign start_operation = ui_in[0];
    assign operation_mode = ui_in[2:1];
    assign input_valid = ui_in[3];
    
    // Output assignments
    assign uo_out[0] = data_ready;
    assign uo_out[1] = operation_complete;
    assign uo_out[7:2] = output_data[5:0];
    assign uio_out = output_data;
    assign uio_oe = 8'hFF;  // All IOs as outputs
    
    // State machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            ascon_state <= '0;
            key_reg <= '0;
            nonce_reg <= '0;
            tag_reg <= '0;
            buffer_count <= '0;
            output_data <= '0;
            data_ready <= '0;
            operation_complete <= '0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (start_operation) begin
                        buffer_count <= '0;
                        operation_complete <= '0;
                        data_ready <= '0;
                    end
                end
                
                LOAD_KEY: begin
                    if (input_valid) begin
                        input_buffer[buffer_count] <= uio_in;
                        buffer_count <= buffer_count + 1;
                        
                        // Assemble 128-bit key from 16 bytes
                        if (buffer_count == 15) begin
                            key_reg <= {input_buffer[15], input_buffer[14], input_buffer[13], input_buffer[12],
                                       input_buffer[11], input_buffer[10], input_buffer[9], input_buffer[8],
                                       input_buffer[7], input_buffer[6], input_buffer[5], input_buffer[4],
                                       input_buffer[3], input_buffer[2], input_buffer[1], uio_in};
                            buffer_count <= '0;
                        end
                    end
                end
                
                LOAD_NONCE: begin
                    if (input_valid) begin
                        input_buffer[buffer_count] <= uio_in;
                        buffer_count <= buffer_count + 1;
                        
                        // Assemble 128-bit nonce from 16 bytes
                        if (buffer_count == 15) begin
                            nonce_reg <= {input_buffer[15], input_buffer[14], input_buffer[13], input_buffer[12],
                                         input_buffer[11], input_buffer[10], input_buffer[9], input_buffer[8],
                                         input_buffer[7], input_buffer[6], input_buffer[5], input_buffer[4],
                                         input_buffer[3], input_buffer[2], input_buffer[1], uio_in};
                            buffer_count <= '0;
                        end
                    end
                end
                
                INIT: begin
                    // Initialize Ascon state: IV || Key || Nonce
                    ascon_state <= {ASCON_IV, key_reg, nonce_reg};
                    // In real implementation, would run p12 permutation here
                    // Then XOR with key: state = state XOR (0^192 || key)
                end
                
                PROC_AAD: begin
                    // Process Associated Authenticated Data
                    // For simplicity, assuming no AAD in this basic implementation
                    data_ready <= 1'b1;
                end
                
                PROC_PT: begin
                    // Process plaintext/ciphertext
                    if (input_valid) begin
                        input_buffer[buffer_count] <= uio_in;
                        buffer_count <= buffer_count + 1;
                        
                        // Process in 8-byte (64-bit) blocks for rate
                        if (buffer_count == 7) begin
                            // XOR input with state and extract output
                            // This is a simplified version - real implementation needs
                            // proper rate/capacity separation and permutation calls
                            output_data <= input_buffer[0] ^ ascon_state[7:0];
                            buffer_count <= '0;
                            data_ready <= 1'b1;
                        end
                    end
                end
                
                FINALIZE: begin
                    // Finalization phase
                    // XOR key, run p12, generate tag
                    tag_reg <= ascon_state[127:0] ^ key_reg;  // Simplified tag generation
                end
                
                OUTPUT_CT: begin
                    // Output ciphertext bytes
                    data_ready <= 1'b1;
                end
                
                OUTPUT_TAG: begin
                    // Output authentication tag
                    output_data <= tag_reg[7:0];  // Output tag byte by byte
                    tag_reg <= {8'h00, tag_reg[127:8]};  // Shift for next byte
                    data_ready <= 1'b1;
                end
                
                DONE: begin
                    operation_complete <= 1'b1;
                    data_ready <= 1'b0;
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_operation)
                    next_state = LOAD_KEY;
            end
            
            LOAD_KEY: begin
                if (buffer_count == 15 && input_valid)
                    next_state = LOAD_NONCE;
            end
            
            LOAD_NONCE: begin
                if (buffer_count == 15 && input_valid)
                    next_state = INIT;
            end
            
            INIT: begin
                next_state = PROC_AAD;
            end
            
            PROC_AAD: begin
                next_state = PROC_PT;
            end
            
            PROC_PT: begin
                // Simplified - in real implementation would check for end of input
                if (buffer_count == 7 && input_valid)
                    next_state = FINALIZE;
            end
            
            FINALIZE: begin
                next_state = OUTPUT_CT;
            end
            
            OUTPUT_CT: begin
                next_state = OUTPUT_TAG;
            end
            
            OUTPUT_TAG: begin
                // Output all 16 bytes of tag
                if (tag_reg[127:8] == 120'h0)
                    next_state = DONE;
            end
            
            DONE: begin
                if (!start_operation)
                    next_state = IDLE;
            end
        endcase
    end
    
    // Ascon S-box (5-bit substitution)
    function automatic logic [4:0] ascon_sbox(input logic [4:0] in);
        case (in)
            5'h00: ascon_sbox = 5'h04;
            5'h01: ascon_sbox = 5'h0b;
            5'h02: ascon_sbox = 5'h1f;
            5'h03: ascon_sbox = 5'h14;
            5'h04: ascon_sbox = 5'h1a;
            5'h05: ascon_sbox = 5'h15;
            5'h06: ascon_sbox = 5'h09;
            5'h07: ascon_sbox = 5'h02;
            5'h08: ascon_sbox = 5'h1b;
            5'h09: ascon_sbox = 5'h05;
            5'h0a: ascon_sbox = 5'h08;
            5'h0b: ascon_sbox = 5'h12;
            5'h0c: ascon_sbox = 5'h1d;
            5'h0d: ascon_sbox = 5'h03;
            5'h0e: ascon_sbox = 5'h06;
            5'h0f: ascon_sbox = 5'h1c;
            5'h10: ascon_sbox = 5'h1e;
            5'h11: ascon_sbox = 5'h13;
            5'h12: ascon_sbox = 5'h07;
            5'h13: ascon_sbox = 5'h0e;
            5'h14: ascon_sbox = 5'h00;
            5'h15: ascon_sbox = 5'h0d;
            5'h16: ascon_sbox = 5'h11;
            5'h17: ascon_sbox = 5'h18;
            5'h18: ascon_sbox = 5'h10;
            5'h19: ascon_sbox = 5'h0c;
            5'h1a: ascon_sbox = 5'h01;
            5'h1b: ascon_sbox = 5'h19;
            5'h1c: ascon_sbox = 5'h16;
            5'h1d: ascon_sbox = 5'h0a;
            5'h1e: ascon_sbox = 5'h0f;
            5'h1f: ascon_sbox = 5'h17;
        endcase
    endfunction
    
    // Linear layer rotation amounts for each 64-bit word
    function automatic logic [63:0] rotate_word(input logic [63:0] word, input int rotation);
        rotate_word = {word[63-rotation:0], word[63:64-rotation]};
    endfunction
    
    // List unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule
