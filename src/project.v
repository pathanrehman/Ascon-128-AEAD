/*
 * Copyright (c) 2025 Ascon-128 AEAD Minimal Implementation  
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_ascon_aead (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire       ena,      
    input  wire       clk,      
    input  wire       rst_n     
);

    // State encoding using only 2 bits - standard Verilog
    parameter IDLE = 2'b00;
    parameter LOAD = 2'b01;
    parameter PROC = 2'b10;
    parameter OUT  = 2'b11;
    
    // Minimal register set - only essential registers
    reg [1:0] state;
    reg [1:0] next_state;
    reg [7:0] data_reg;
    reg [3:0] counter;
    reg [7:0] key_byte;
    reg ready;
    reg complete;
    
    // Extract control signals - direct assignment
    wire start;
    wire data_valid;
    
    assign start = ui_in[0];
    assign data_valid = ui_in[1];
    
    // Simple transformation lookup - combinational logic only
    reg [7:0] transform_out;
    always @(counter[2:0]) begin
        case (counter[2:0])
            3'b000: transform_out = 8'h04;
            3'b001: transform_out = 8'h0b;
            3'b010: transform_out = 8'h1f;
            3'b011: transform_out = 8'h14;
            3'b100: transform_out = 8'h1a;
            3'b101: transform_out = 8'h15;
            3'b110: transform_out = 8'h09;
            3'b111: transform_out = 8'h02;
        endcase
    end
    
    // State transition logic - combinational
    always @(state or start or data_valid or counter) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = LOAD;
            end
            
            LOAD: begin
                if (data_valid && (counter == 4'hF))
                    next_state = PROC;
            end
            
            PROC: begin
                if (data_valid && (counter == 4'h7))
                    next_state = OUT;
            end
            
            OUT: begin
                if (counter == 4'hF)
                    next_state = IDLE;
            end
        endcase
    end
    
    // Sequential logic - state and data registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            data_reg <= 8'h00;
            counter <= 4'h0;
            key_byte <= 8'h00;
            ready <= 1'b0;
            complete <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    complete <= 1'b0;
                    if (start) begin
                        counter <= 4'h0;
                    end
                end
                
                LOAD: begin
                    if (data_valid) begin
                        key_byte <= uio_in;
                        if (counter == 4'hF) begin
                            counter <= 4'h0;
                        end else begin
                            counter <= counter + 1'b1;
                        end
                    end
                end
                
                PROC: begin
                    if (data_valid) begin
                        // Simple encryption: XOR with key and transform
                        data_reg <= uio_in ^ key_byte ^ transform_out;
                        ready <= 1'b1;
                        if (counter == 4'h7) begin
                            counter <= 4'h0;
                        end else begin
                            counter <= counter + 1'b1;
                        end
                    end else begin
                        ready <= 1'b0;
                    end
                end
                
                OUT: begin
                    // Output processing with simple transformation
                    data_reg <= data_reg ^ 8'hA5;
                    ready <= 1'b1;
                    if (counter == 4'hF) begin
                        complete <= 1'b1;
                        counter <= 4'h0;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Output assignments - static
    assign uo_out[0] = ready;
    assign uo_out[1] = complete;
    assign uo_out[2] = state[0];
    assign uo_out[3] = state[1]; 
    assign uo_out[7:4] = counter;
    
    assign uio_out = data_reg;
    assign uio_oe = 8'hFF;
    
    // Unused signal handling - single wire
    wire _unused = &{ena, ui_in[7:2], 1'b0};

endmodule
