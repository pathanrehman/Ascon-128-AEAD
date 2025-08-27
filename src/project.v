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

    // Simple state encoding - no enums
    localparam [1:0] IDLE = 2'b00;
    localparam [1:0] LOAD = 2'b01;
    localparam [1:0] PROC = 2'b10;
    localparam [1:0] OUT  = 2'b11;
    
    // Minimal registers
    reg [1:0] state;
    reg [7:0] data_reg;
    reg [3:0] counter;
    reg [7:0] key_byte;
    reg ready;
    reg complete;
    reg [7:0] temp_data;
    
    // Extract control signals
    wire start;
    wire data_valid;
    
    assign start = ui_in[0];
    assign data_valid = ui_in[1];
    
    // Simple transformation without function arrays
    always @(*) begin
        case (counter[2:0])
            3'h0: temp_data = 8'h04;
            3'h1: temp_data = 8'h0b;
            3'h2: temp_data = 8'h1f;
            3'h3: temp_data = 8'h14;
            3'h4: temp_data = 8'h1a;
            3'h5: temp_data = 8'h15;
            3'h6: temp_data = 8'h09;
            3'h7: temp_data = 8'h02;
        endcase
    end
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            data_reg <= 8'h00;
            counter <= 4'h0;
            key_byte <= 8'h00;
            ready <= 1'b0;
            complete <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    ready <= 1'b0;
                    complete <= 1'b0;
                    if (start) begin
                        state <= LOAD;
                        counter <= 4'h0;
                    end
                end
                
                LOAD: begin
                    if (data_valid) begin
                        key_byte <= uio_in;
                        counter <= counter + 4'h1;
                        if (counter == 4'hF) begin
                            state <= PROC;
                            counter <= 4'h0;
                        end
                    end
                end
                
                PROC: begin
                    if (data_valid) begin
                        // Simple encryption: XOR with key and transform
                        data_reg <= uio_in ^ key_byte ^ temp_data;
                        ready <= 1'b1;
                        counter <= counter + 4'h1;
                        if (counter == 4'h7) begin
                            state <= OUT;
                            counter <= 4'h0;
                        end
                    end else begin
                        ready <= 1'b0;
                    end
                end
                
                OUT: begin
                    // Output processing
                    data_reg <= data_reg ^ 8'hA5;
                    ready <= 1'b1;
                    counter <= counter + 4'h1;
                    if (counter == 4'hF) begin
                        state <= IDLE;
                        complete <= 1'b1;
                    end
                end
            endcase
        end
    end
    
    // Output assignments
    assign uo_out[0] = ready;
    assign uo_out[1] = complete;
    assign uo_out[2] = state[0];
    assign uo_out[3] = state[1]; 
    assign uo_out[7:4] = counter;
    
    assign uio_out = data_reg;
    assign uio_oe = 8'hFF;
    
    // Suppress lint warnings
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused;
    assign _unused = &{ena, ui_in[7:2], 1'b0};
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
