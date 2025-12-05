//////////////////////////////////////////////////////////////////////////////////
// Module Name:    mac_1x1_unit
// Project Name:   Zynq CNN Acceleration System
// Description:    
//    - A single Multiply-Accumulate (MAC) Processing Element (PE).
//    - Multiplies 8-bit Input Feature Map (Unsigned) with 8-bit Weight (Signed).
//    - Accumulates the result into a 32-bit Partial Sum.
//    - Passes input features (x_i) and weights (w_i) to adjacent units.
//
// Modifications for CNN Inference:
//    1. [Data Type Fix] Changed input 'x_i' to Unsigned 8-bit (0~255) to match CNN input spec.
//       - Logic updated: 'WEIGHT * $signed({1'b0, x_i})' for correct mixed-sign arithmetic.
//    2. [Bit-width Expansion] Expanded Accumulator (SUM, before/after_sum) from 16-bit to 32-bit.
//       - Prevents overflow during deep convolution layer accumulation (e.g., 5x5x12 filters).
//////////////////////////////////////////////////////////////////////////////////

module mac_1x1_unit(
    input wire                  CLK,
    input wire                  RSTN,
    input wire                  en_x_i,
    input wire                  en_w_i,

    input wire                  stop_mac,
    input wire                  used_row,

    input wire           [7:0]  x_i,        // Unsigned 입력
    input wire  signed   [7:0]  w_i,        // Signed 가중치
    input wire  signed   [31:0] before_sum, 

    output wire                 stop_mac_o,
    output wire                 used_row_o,
    output reg           [7:0]  x_o,
    output reg  signed   [7:0]  w_o,
    output wire signed   [31:0] after_sum   
);

    reg                 stop_mac_reg;
    reg                 used_row_reg;
    reg signed   [7:0]  WEIGHT;

    reg signed   [31:0] SUM;
    wire signed  [15:0] MUL;

    // WEIGHT + stop_mac + used_row
    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            WEIGHT          <=  8'd0;
            stop_mac_reg    <=  1'b0;
            used_row_reg    <=  1'b0;
        end else if(en_w_i) begin
            WEIGHT          <=  w_i;
            used_row_reg    <=  used_row;
        end else begin
            WEIGHT          <=  WEIGHT;
            stop_mac_reg    <=  stop_mac;
            used_row_reg    <=  used_row_reg;
        end
    end

    // SUM
    // Weight Loading & used_row X & stop_mac O -> MAC operation X
    // x_i(Unsigned) 앞에 0을 붙여 양수 Signed로 만든 뒤 곱함
    assign  MUL         =   WEIGHT * $signed({1'b0, x_i});
    
    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            SUM         <=  32'd0;
        end else if(en_w_i||stop_mac_reg||~used_row_reg) begin
            SUM         <=  32'd0;
        end else begin
            SUM         <=  before_sum + MUL;
        end
    end

    // I/O interface
    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            x_o             <=  8'd0;
            w_o             <=  8'd0;
        end else begin
            x_o             <=  x_i;
            w_o             <=  w_i;
        end
    end

    assign  after_sum   =   SUM;
    assign  stop_mac_o  =   stop_mac_reg;
    assign  used_row_o  =   used_row_reg;
endmodule