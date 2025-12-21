`timescale 1ns / 1ps

module fc_core #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                  clk,
    input  wire                  rstn,
    
    // [Control Signals]
    input  wire                  i_clear, 
    input  wire                  i_valid, 
    
    // [Data Input]
    input  wire [DATA_WIDTH-1:0] i_data,   
    input  wire [DATA_WIDTH-1:0] i_weight, 
    
    // [Data Output]
    output wire [ACC_WIDTH-1:0]  o_result
);

    //==========================================================================
    // 1. Pipeline Registers (Input Stage)
    //==========================================================================
    reg signed [DATA_WIDTH:0]   r_data;   // 1bit 확장 (Unsigned -> Signed 변환용)
    reg signed [DATA_WIDTH-1:0] r_weight; // Signed 그대로
    
    reg                         r_valid;
    reg                         r_clear;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_data   <= 0;
            r_weight <= 0;
            r_valid  <= 0;
            r_clear  <= 0;
        end else begin
            r_data   <= $signed({1'b0, i_data});
            r_weight <= $signed(i_weight);
            
            // Control Signal Pipelining
            r_valid  <= i_valid;
            r_clear  <= i_clear;
        end
    end

    //==========================================================================
    // 2. MAC Logic (Execute Stage)
    //==========================================================================
    reg signed [ACC_WIDTH-1:0] accumulator;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            accumulator <= 0;
        end else begin
            if (r_clear) begin
                accumulator <= 0;
                if (r_valid) begin
                     accumulator <= r_data * r_weight;
                end
            end 
            else if (r_valid) begin
                accumulator <= accumulator + (r_data * r_weight);
            end
        end
    end

    assign o_result = accumulator;

endmodule