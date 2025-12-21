`timescale 1ns / 1ps

module max_pooling_2x2_core # (
    // 48 inputs (2 rows * 24 cols) -> 12 outputs (1 row * 12 cols)
    parameter INPUT_COUNT  = 48,
    parameter OUTPUT_COUNT = 12,
    parameter ROW_WIDTH    = 24 // Assumed width to make 2x2 valid for 48 inputs
) (
    input   wire        clk,
    input   wire        rstn,
    // POOL1 <-> POOL2
    input   wire        i_mode,
    // Input Interface (from Relu_Quant)
    input   wire        i_valid,
    input   wire [31:0] i_data,  // 4 Channel INT8 (Packed)
    
    // Output Interface
    output  reg         o_valid,
    output  reg  [31:0] o_data,  // 4 Channel INT8 (Pooled)
    output  wire        o_ready  // Ready to receive new batch
);

    //==========================================================================
    // 1. Configuration Parameters (Hardcoded for each mode)
    //==========================================================================
    // Mode 0: CONV1 Result (48 -> 12)
    localparam M0_IN_CNT  = 48;
    localparam M0_OUT_CNT = 12;
    localparam M0_WIDTH   = 24; 

    // Mode 1: CONV2 Result (16 -> 4)
    localparam M1_IN_CNT  = 16;
    localparam M1_OUT_CNT = 4;
    localparam M1_WIDTH   = 8;  

    // Max Buffer Size (가장 큰 경우에 맞춤)
    localparam MAX_BUFFER_SIZE = 48;

    //==========================================================================
    // 2. Dynamic Selection Signals (Mux based on i_mode)
    //==========================================================================
    wire [5:0] target_in_cnt;
    wire [3:0] target_out_cnt;
    wire [4:0] target_row_width;

    assign target_in_cnt    = (i_mode == 1'b0) ? M0_IN_CNT  : M1_IN_CNT;
    assign target_out_cnt   = (i_mode == 1'b0) ? M0_OUT_CNT : M1_OUT_CNT;
    assign target_row_width = (i_mode == 1'b0) ? M0_WIDTH   : M1_WIDTH;

    //==========================================================================
    // 3. State & Counters & Pipeline Registers
    //==========================================================================
    localparam S_IDLE    = 3'b001;
    localparam S_RX      = 3'b010;
    localparam S_PROCESS = 3'b100;

    reg [2:0] state;
    reg [5:0] rx_cnt; // Max 48을 커버하기 위해 6비트
    reg [3:0] tx_cnt; // Max 12를 커버하기 위해 4비트

    // Internal Buffer (Max Size)
    reg [31:0] data_buffer [0:MAX_BUFFER_SIZE-1];

    // [New] Pipeline Registers for Timing Closure
    // 메모리 읽기와 Max 계산 사이를 끊어주는 레지스터
    reg [31:0] r_p_tl, r_p_tr, r_p_bl, r_p_br;
    reg        r_valid_stage; // 파이프라인에 유효한 데이터가 있는지 표시

    //==========================================================================
    // Helper Function
    //==========================================================================
    function [7:0] get_max_int8 (
        input signed [7:0] v0, v1, v2, v3
    );
        reg signed [7:0] m1, m2;
        begin
            m1 = (v0 > v1) ? v0 : v1;
            m2 = (v2 > v3) ? v2 : v3;
            get_max_int8 = (m1 > m2) ? m1 : m2;
        end
    endfunction

    //==========================================================================
    // 4. Index Calculation (Combinational)
    //==========================================================================
    // [Safe Indexing]
    wire is_safe = (tx_cnt < target_out_cnt);
    wire [5:0] base_idx = {tx_cnt, 1'b0}; // 2 * k
    
    wire [5:0] idx_tl = is_safe ? (base_idx) : 6'd0;
    wire [5:0] idx_tr = is_safe ? (base_idx + 6'd1) : 6'd0;
    wire [5:0] idx_bl = is_safe ? (base_idx + target_row_width) : 6'd0;
    wire [5:0] idx_br = is_safe ? (base_idx + target_row_width + 6'd1) : 6'd0;

    //==========================================================================
    // 5. Max Calculation Logic (Uses Pipeline Registers)
    //==========================================================================
    wire [7:0] max_ch0 = get_max_int8(r_p_tl[7:0],   r_p_tr[7:0],   r_p_bl[7:0],   r_p_br[7:0]);
    wire [7:0] max_ch1 = get_max_int8(r_p_tl[15:8],  r_p_tr[15:8],  r_p_bl[15:8],  r_p_br[15:8]);
    wire [7:0] max_ch2 = get_max_int8(r_p_tl[23:16], r_p_tr[23:16], r_p_bl[23:16], r_p_br[23:16]);
    wire [7:0] max_ch3 = get_max_int8(r_p_tl[31:24], r_p_tr[31:24], r_p_bl[31:24], r_p_br[31:24]);

    //==========================================================================
    // 6. Main FSM (Modified for Pipelining)
    //==========================================================================
    assign o_ready = (state == S_IDLE) || (state == S_RX);

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state   <= S_IDLE;
            rx_cnt  <= 0;
            tx_cnt  <= 0;
            o_valid <= 0;
            o_data  <= 0;
            // Pipeline Reset
            r_valid_stage <= 0;
            r_p_tl <= 0; r_p_tr <= 0; r_p_bl <= 0; r_p_br <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    o_valid <= 0;
                    r_valid_stage <= 0;
                    if (i_valid) begin
                        data_buffer[0] <= i_data;
                        rx_cnt <= 1;
                        state  <= S_RX;
                    end
                end

                S_RX: begin
                    if (i_valid) begin
                        data_buffer[rx_cnt] <= i_data;
                        
                        if (rx_cnt == target_in_cnt - 1) begin
                            rx_cnt <= 0;
                            state  <= S_PROCESS;
                            tx_cnt <= 0; 
                        end else begin
                            rx_cnt <= rx_cnt + 1;
                        end
                    end
                end

                S_PROCESS: begin
                    // ---------------------------------------------------------
                    // [Stage 1] Fetch & Latch (Buffer Read)
                    // ---------------------------------------------------------
                    if (tx_cnt < target_out_cnt) begin
                        // Buffer -> Register 로딩 (Critical Path 분리점)
                        r_p_tl <= data_buffer[idx_tl];
                        r_p_tr <= data_buffer[idx_tr];
                        r_p_bl <= data_buffer[idx_bl];
                        r_p_br <= data_buffer[idx_br];
                        
                        r_valid_stage <= 1'b1; // 파이프라인 유효함
                        tx_cnt <= tx_cnt + 1;
                    end else begin
                        // 더 읽을 데이터 없음
                        r_valid_stage <= 1'b0; 
                        
                        // [종료 조건]
                        // 읽기도 끝났고(tx_cnt 완료), 
                        // 파이프라인에 남은 마지막 데이터(r_valid_stage) 처리도 끝났을 때
                        if (r_valid_stage == 0) begin
                            tx_cnt <= 0;
                            state  <= S_IDLE;
                        end
                    end

                    // ---------------------------------------------------------
                    // [Stage 2] Calculate & Output
                    // ---------------------------------------------------------
                    if (r_valid_stage) begin
                        // 레지스터 값(r_p_xx)을 이용하여 Max 계산 수행
                        o_valid <= 1'b1;
                        o_data  <= {max_ch3, max_ch2, max_ch1, max_ch0};
                    end else begin
                        o_valid <= 1'b0;
                        o_data  <= 0;
                    end
                end
            endcase
        end
    end

endmodule