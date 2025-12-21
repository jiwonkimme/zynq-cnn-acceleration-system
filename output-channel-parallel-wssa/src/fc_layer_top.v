`timescale 1ns / 1ps

module fc_layer_top #(
    parameter INPUT_LEN  = 192, // 입력 데이터 길이
    parameter OUTPUT_LEN = 10,  // 출력 클래스 개수
    parameter DATA_WIDTH = 8
)(
    input  wire        clk,
    input  wire        rstn,
    
    // [System Interface]
    input  wire        i_start,      // 시작 신호
    output wire        o_done,       // 전체 완료 신호
    output wire        o_ready,      // Ready 신호
    
    // [Memory Interface] (외부 BRAM/ROM 연결용)
    output wire [7:0]  o_in_addr,    // Input BRAM Address
    input  wire [7:0]  i_in_data,    // Input BRAM Data (Unsigned)
    
    output wire [10:0] o_w_addr,     // Weight ROM Address
    input  wire [7:0]  i_w_data,     // Weight ROM Data (Signed)
    
    // [Result Output]
    output wire        o_valid,      // 결과 1개 유효 (총 10번 뜸)
    output wire [31:0] o_result      // 최종 결과값 (Accumulated)
);

    //==========================================================================
    // Internal Wires (Ctrl <-> Core Connection)
    //==========================================================================
    wire        core_clear; // Accumulator 리셋 신호
    wire        core_valid; // 연산 Enable 신호
    
    //==========================================================================
    // 1. Controller Instance (Brain)
    //==========================================================================
    fc_ctrl #(
        .INPUT_LEN (INPUT_LEN),
        .OUTPUT_LEN(OUTPUT_LEN)
    ) u_ctrl (
        .clk            (clk),
        .rstn           (rstn),
        
        // System
        .i_start        (i_start),
        .o_done         (o_done),
        .o_ready        (o_ready),
        
        // Memory Address Gen
        .o_in_addr      (o_in_addr),
        .o_w_addr       (o_w_addr),
        
        // Control Signals to Core
        .o_core_clear   (core_clear),
        .o_core_valid   (core_valid),
        
        // Output Handshake
        // Ctrl이 "계산 끝났어"라고 할 때가 결과가 유효한 시점입니다.
        .o_out_valid    (o_valid) 
    );

    //==========================================================================
    // 2. Core Instance (Muscle)
    //==========================================================================
    fc_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (32)
    ) u_core (
        .clk        (clk),
        .rstn       (rstn),
        
        // Control from Ctrl
        .i_clear    (core_clear),
        .i_valid    (core_valid),
        
        // Data from Memory
        .i_data     (i_in_data),
        .i_weight   (i_w_data),
        
        // Result Output
        .o_result   (o_result)
    );

endmodule