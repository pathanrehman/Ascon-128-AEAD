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
    
    // Control states - using parameters instead of enum
    localparam [3:0] IDLE        = 4'b0000;
    localparam [3:0] LOAD_KEY    = 4'b0001;
    localparam [3:0] LOAD_NONCE  = 4'b0010;
    localparam [3:0] INIT        = 4'b0011;
    localparam [3:0] PROC_AAD    = 4'b0100;
    localparam [3:0] PROC_PT     = 4'b0101;
    localparam [3:0] FINALIZE    = 4'b0110;
    localparam [3:0] OUTPUT_CT   = 4'b0111;
    localparam [3:0] OUTPUT_TAG  = 4'b1000;
    localparam [3:0] DONE        = 4'b1001;
    
    // Registers - using reg instead of logic
    reg [3:0] current_state, next_state;
    reg [STATE_WIDTH-1:0] ascon_state;
    reg [KEY_WIDTH-1:0] key_reg;
    reg [NONCE_WIDTH-1:0] nonce_reg;
    reg [TAG_WIDTH-1:0] tag_reg;
    reg [7:0] input_buffer_0, input_buffer_1, input_buffer_2, input_buffer_3;
    reg [7:0] input_buffer_4, input_buffer_5, input_buffer_6, input_buffer_7;
    reg [7:0] input_buffer_8, input_buffer_9, input_buffer_10, input_buffer_11;
    reg [7:0] input_buffer_12, input_buffer_13, input_buffer_14, input_buffer_15;
    reg [3:0] buffer_count;
    reg [7:0] output_data;
    reg data_ready;
    reg operation_complete;
    
    // Ascon IV for AEAD128
    localparam [63:0] ASCON_IV = 64'h80400c0600000000;
    
    // Input/Output control signals
    wire start_operation;
    wire [1:0] operation_mode;
    wire input_valid;
    
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
    
    // Helper function to get input buffer value
    function [7:0] get_input_buffer;
        input [3:0] index;
        begin
            case (index)
                4'h0: get_input_buffer = input_buffer_0;
                4'h1: get_input_buffer = input_buffer_1;
                4'h2: get_input_buffer = input_buffer_2;
                4'h3: get_input_buffer = input_buffer_3;
                4'h4: get_input_buffer = input_buffer_4;
                4'h5: get_input_buffer = input_buffer_5;
                4'h6: get_input_buffer = input_buffer_6;
                4'h7: get_input_buffer = input_buffer_7;
                4'h8: get_input_buffer = input_buffer_8;
                4'h9: get_input_buffer = input_buffer_9;
                4'ha: get_input_buffer = input_buffer_10;
                4'hb: get_input_buffer = input_buffer_11;
                4'hc: get_input_buffer = input_buffer_12;
                4'hd: get_input_buffer = input_buffer_13;
                4'he: get_input_buffer = input_buffer_14;
                4'hf: get_input_buffer = input_buffer_15;
            endcase
        end
    endfunction
    
    // State machine - using always @(posedge clk) instead of always_ff
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            ascon_state <= {STATE_WIDTH{1'b0}};
            key_reg <= {KEY_WIDTH{1'b0}};
            nonce_reg <= {NONCE_WIDTH{1'b0}};
            tag_reg <= {TAG_WIDTH{1'b0}};
            buffer_count <= 4'h0;
            output_data <= 8'h0;
            data_ready <= 1'b0;
            operation_complete <= 1'b0;
            // Initialize all input buffers
            input_buffer_0 <= 8'h0;
            input_buffer_1 <= 8'h0;
            input_buffer_2 <= 8'h0;
            input_buffer_3 <= 8'h0;
            input_buffer_4 <= 8'h0;
            input_buffer_5 <= 8'h0;
            input_buffer_6 <= 8'h0;
            input_buffer_7 <= 8'h0;
            input_buffer_8 <= 8'h0;
            input_buffer_9 <= 8'h0;
            input_buffer_10 <= 8'h0;
            input_buffer_11 <= 8'h0;
            input_buffer_12 <= 8'h0;
            input_buffer_13 <= 8'h0;
            input_buffer_14 <= 8'h0;
            input_buffer_15 <= 8'h0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                IDLE: begin
                    if (start_operation) begin
                        buffer_count <= 4'h0;
                        operation_complete <= 1'b0;
                        data_ready <= 1'b0;
                    end
                end
                
                LOAD_KEY: begin
                    if (input_valid) begin
                        case (buffer_count)
                            4'h0: input_buffer_0 <= uio_in;
                            4'h1: input_buffer_1 <= uio_in;
                            4'h2: input_buffer_2 <= uio_in;
                            4'h3: input_buffer_3 <= uio_in;
                            4'h4: input_buffer_4 <= uio_in;
                            4'h5: input_buffer_5 <= uio_in;
                            4'h6: input_buffer_6 <= uio_in;
                            4'h7: input_buffer_7 <= uio_in;
                            4'h8: input_buffer_8 <= uio_in;
                            4'h9: input_buffer_9 <= uio_in;
                            4'ha: input_buffer_10 <= uio_in;
                            4'hb: input_buffer_11 <= uio_in;
                            4'hc: input_buffer_12 <= uio_in;
                            4'hd: input_buffer_13 <= uio_in;
                            4'he: input_buffer_14 <= uio_in;
                            4'hf: input_buffer_15 <= uio_in;
                        endcase
                        
                        buffer_count <= buffer_count + 1;
                        
                        // Assemble 128-bit key from 16 bytes
                        if (buffer_count == 4'hf) begin
                            key_reg <= {input_buffer_15, input_buffer_14, input_buffer_13, input_buffer_12,
                                       input_buffer_11, input_buffer_10, input_buffer_9, input_buffer_8,
                                       input_buffer_7, input_buffer_6, input_buffer_5, input_buffer_4,
                                       input_buffer_3, input_buffer_2, input_buffer_1, uio_in};
                            buffer_count <= 4'h0;
                        end
                    end
                end
                
                LOAD_NONCE: begin
                    if (input_valid) begin
                        case (buffer_count)
                            4'h0: input_buffer_0 <= uio_in;
                            4'h1: input_buffer_1 <= uio_in;
                            4'h2: input_buffer_2 <= uio_in;
                            4'h3: input_buffer_3 <= uio_in;
                            4'h4: input_buffer_4 <= uio_in;
                            4'h5: input_buffer_5 <= uio_in;
                            4'h6: input_buffer_6 <= uio_in;
                            4'h7: input_buffer_7 <= uio_in;
                            4'h8: input_buffer_8 <= uio_in;
                            4'h9: input_buffer_9 <= uio_in;
                            4'ha: input_buffer_10 <= uio_in;
                            4'hb: input_buffer_11 <= uio_in;
                            4'hc: input_buffer_12 <= uio_in;
                            4'hd: input_buffer_13 <= uio_in;
                            4'he: input_buffer_14 <= uio_in;
                            4'hf: input_buffer_15 <= uio_in;
                        endcase
                        
                        buffer_count <= buffer_count + 1;
                        
                        // Assemble 128-bit nonce from 16 bytes
                        if (buffer_count == 4'hf) begin
                            nonce_reg <= {input_buffer_15, input_buffer_14, input_buffer_13, input_buffer_12,
                                         input_buffer_11, input_buffer_10, input_buffer_9, input_buffer_8,
                                         input_buffer_7, input_buffer_6, input_buffer_5, input_buffer_4,
                                         input_buffer_3, input_buffer_2, input_buffer_1, uio_in};
                            buffer_count <= 4'h0;
                        end
                    end
                end
                
                INIT: begin
                    // Initialize Ascon state: IV || Key || Nonce
                    ascon_state <= {ASCON_IV, key_reg, nonce_reg};
                end
                
                PROC_AAD: begin
                    data_ready <= 1'b1;
                end
                
                PROC_PT: begin
                    if (input_valid) begin
                        case (buffer_count)
                            4'h0: input_buffer_0 <= uio_in;
                            4'h1: input_buffer_1 <= uio_in;
                            4'h2: input_buffer_2 <= uio_in;
                            4'h3: input_buffer_3 <= uio_in;
                            4'h4: input_buffer_4 <= uio_in;
                            4'h5: input_buffer_5 <= uio_in;
                            4'h6: input_buffer_6 <= uio_in;
                            4'h7: input_buffer_7 <= uio_in;
                        endcase
                        
                        buffer_count <= buffer_count + 1;
                        
                        if (buffer_count == 4'h7) begin
                            output_data <= input_buffer_0 ^ ascon_state[7:0];
                            buffer_count <= 4'h0;
                            data_ready <= 1'b1;
                        end
                    end
                end
                
                FINALIZE: begin
                    tag_reg <= ascon_state[127:0] ^ key_reg;
                end
                
                OUTPUT_CT: begin
                    data_ready <= 1'b1;
                end
                
                OUTPUT_TAG: begin
                    output_data <= tag_reg[7:0];
                    tag_reg <= {8'h00, tag_reg[127:8]};
                    data_ready <= 1'b1;
                end
                
                DONE: begin
                    operation_complete <= 1'b1;
                    data_ready <= 1'b0;
                end
            endcase
        end
    end
    
    // Next state logic - using always @(*) instead of always_comb
    always @(*) begin
        next_state = current_state;
        
        case (current_state)
            IDLE: begin
                if (start_operation)
                    next_state = LOAD_KEY;
            end
            
            LOAD_KEY: begin
                if (buffer_count == 4'hf && input_valid)
                    next_state = LOAD_NONCE;
            end
            
            LOAD_NONCE: begin
                if (buffer_count == 4'hf && input_valid)
                    next_state = INIT;
            end
            
            INIT: begin
                next_state = PROC_AAD;
            end
            
            PROC_AAD: begin
                next_state = PROC_PT;
            end
            
            PROC_PT: begin
                if (buffer_count == 4'h7 && input_valid)
                    next_state = FINALIZE;
            end
            
            FINALIZE: begin
                next_state = OUTPUT_CT;
            end
            
            OUTPUT_CT: begin
                next_state = OUTPUT_TAG;
            end
            
            OUTPUT_TAG: begin
                if (tag_reg[127:8] == 120'h0)
                    next_state = DONE;
            end
            
            DONE: begin
                if (!start_operation)
                    next_state = IDLE;
            end
        endcase
    end
    
    // List unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule
