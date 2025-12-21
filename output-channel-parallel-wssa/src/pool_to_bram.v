`timescale 1ns / 1ps

module pool_to_bram (
    input  wire         clk,
    input  wire         rstn,
    input  wire         i_frame_rst, 
    
    // [Input] From Max Pooling (Packed 32-bit)
    input  wire         i_valid,
    input  wire [31:0]  i_data,      // {Ch3, Ch2, Ch1, Ch0}

    // [Output] To External BRAM
    output reg          o_bram_en,
    output reg          o_bram_we,
    output reg  [7:0]   o_bram_addr,
    output reg  [31:0]  o_bram_data
);

    //==========================================================================
    // Configuration
    //==========================================================================
    // Mode 0(12x12)을 위해 48간격 확보. Mode 1(4x4)때는 낭비지만 주소 계산 단순화됨.
    localparam CH_OFFSET = 8'd48;

    //==========================================================================
    // Internal Pipeline
    //==========================================================================
    reg [31:0] p0, p1, p2; 
    reg [1:0]  collect_cnt;

    // Holding Buffer
    reg [31:0] hold_p0, hold_p1, hold_p2, hold_p3;
    
    // Write Control Signals
    reg        write_phase;  
    reg [1:0]  write_step;   // 0~3 (Channel Select)
    reg [7:0]  base_wr_addr; // 4-pixel chunk index

    //==========================================================================
    // Transpose Logic (Slicing)
    //==========================================================================
    wire [7:0] p0_ch0 = hold_p0[31:24], p0_ch1 = hold_p0[23:16], p0_ch2 = hold_p0[15:8], p0_ch3 = hold_p0[7:0];
    wire [7:0] p1_ch0 = hold_p1[31:24], p1_ch1 = hold_p1[23:16], p1_ch2 = hold_p1[15:8], p1_ch3 = hold_p1[7:0];
    wire [7:0] p2_ch0 = hold_p2[31:24], p2_ch1 = hold_p2[23:16], p2_ch2 = hold_p2[15:8], p2_ch3 = hold_p2[7:0];
    wire [7:0] p3_ch0 = hold_p3[31:24], p3_ch1 = hold_p3[23:16], p3_ch2 = hold_p3[15:8], p3_ch3 = hold_p3[7:0];

    // Data Mux (Simple Packing: P0-P1-P2-P3)
    reg [31:0] next_w_data;
    always @(*) begin
        case(write_step)
            0: next_w_data = {p0_ch0, p1_ch0, p2_ch0, p3_ch0}; // Ch0 Data
            1: next_w_data = {p0_ch1, p1_ch1, p2_ch1, p3_ch1}; // Ch1 Data
            2: next_w_data = {p0_ch2, p1_ch2, p2_ch2, p3_ch2}; // Ch2 Data
            3: next_w_data = {p0_ch3, p1_ch3, p2_ch3, p3_ch3}; // Ch3 Data
            default: next_w_data = 32'd0;
        endcase
    end

    // Address Calculation (Fixed Offset)
    wire [7:0] next_w_addr = (write_step * CH_OFFSET) + base_wr_addr;

    //==========================================================================
    // Main FSM
    //==========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            collect_cnt  <= 0;
            write_step   <= 0;
            write_phase  <= 0;
            base_wr_addr <= 0;
            o_bram_en    <= 0;
            o_bram_we    <= 0;
            o_bram_addr  <= 0;
            o_bram_data  <= 0;
        end else begin
            // Default Output
            o_bram_en <= 1'b0;
            o_bram_we <= 1'b0;

            if (i_frame_rst) begin
                base_wr_addr <= 0;
                collect_cnt  <= 0;
                write_phase  <= 0;
                write_step   <= 0;
            end 
            else begin
                // [Step A] Input Collection
                if (i_valid) begin
                    case (collect_cnt)
                        0: p0 <= i_data;
                        1: p1 <= i_data;
                        2: p2 <= i_data;
                        3: begin
                            hold_p0 <= p0; hold_p1 <= p1; hold_p2 <= p2; hold_p3 <= i_data;
                            write_phase <= 1; // Start Writing
                            write_step  <= 0;
                            collect_cnt <= 0;
                        end
                    endcase
                    collect_cnt <= collect_cnt + 1;
                end

                // [Step B] Write Sequence (4 Cycles)
                if (write_phase) begin
                    o_bram_en   <= 1'b1;
                    o_bram_we   <= 1'b1;
                    o_bram_addr <= next_w_addr;
                    o_bram_data <= next_w_data;

                    if (write_step == 3) begin
                        write_step   <= 0;
                        base_wr_addr <= base_wr_addr + 1;
                        // 입력이 끊겼다면 쓰기 종료
                        if (!i_valid) write_phase <= 0; 
                    end 
                    else begin
                        write_step <= write_step + 1;
                    end
                end
            end
        end
    end

endmodule