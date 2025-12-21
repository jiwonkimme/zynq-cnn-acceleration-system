`timescale 1ns / 1ps

module fc_ctrl #(
    parameter INPUT_LEN  = 192, // 입력 데이터 길이 (12x4x4)
    parameter OUTPUT_LEN = 10   // 출력 클래스 개수
)(
    input  wire        clk,
    input  wire        rstn,
    
    // [System Control]
    input  wire        i_start,      // 전체 연산 시작 신호
    output reg         o_done,       // 모든(10개) 연산 완료 신호
    output reg         o_ready,      // 다음 연산 받을 준비 됨
    
    // [Interface to BRAM/ROM] (Address Generation)
    output reg  [7:0]  o_in_addr,    // Input BRAM Address
    output reg  [10:0] o_w_addr,     // Weight ROM Address
    
    // [Interface to FC Core] (Control Signals)
    output reg         o_core_clear, // Core 누적값 0으로 초기화
    output reg         o_core_valid, // Core에게 "지금 연산해" 신호 (Enable)
    
    // [Output Interface] (Final Result)
    output reg         o_out_valid   // 결과 1개가 완성되었음을 알림
);

    //==========================================================================
    // State Machine
    //==========================================================================
    localparam S_IDLE   = 0;
    localparam S_CLEAR  = 1; // Core 초기화 (Accumulator Reset)
    localparam S_CALC   = 2; // 주소 생성 및 연산 요청
    localparam S_OUTPUT = 3; // 결과 출력 (Handshake)
    localparam S_DONE   = 4; 

    reg [2:0] state;
    
    // Counters
    reg [7:0] cnt_in;   // 0 ~ 191 (Input Index)
    reg [3:0] cnt_out;  // 0 ~ 9   (Neuron Index)
    
    // Pipeline Delay Register (BRAM Latency 1 Cycle 대응용)
    reg       req_valid; // 주소를 요청한 순간 1이 됨

    //==========================================================================
    // Main Control Logic
    //==========================================================================
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state        <= S_IDLE;
            o_done       <= 0;
            o_ready      <= 0; // 초기에는 Busy or Ready? 보통 Reset후 Ready
            o_in_addr    <= 0;
            o_w_addr     <= 0;
            o_core_clear <= 0;
            o_core_valid <= 0;
            o_out_valid  <= 0;
            cnt_in       <= 0;
            cnt_out      <= 0;
            req_valid    <= 0;
        end else begin
            // Default Signals
            o_core_clear <= 0;
            o_out_valid  <= 0;
            // o_core_valid는 아래 파이프라인 로직에서 제어됨

            case (state)
                S_IDLE: begin
                    o_ready <= 1;
                    o_done  <= 0;
                    if (i_start) begin
                        o_ready  <= 0;
                        cnt_out  <= 0;
                        o_w_addr <= 0; // 가중치 주소 0번부터 시작
                        state    <= S_CLEAR;
                    end
                end

                // [Step 1] Core의 Accumulator를 0으로 리셋
                S_CLEAR: begin
                    o_core_clear <= 1; // Clear 신호 발생
                    cnt_in       <= 0;
                    o_in_addr    <= 0;
                    req_valid    <= 0; // 파이프라인 비우기
                    state        <= S_CALC;
                end

                // [Step 2] 주소 생성 및 연산 (Pipelined)
                S_CALC: begin
                    // A. 주소 요청 (Address Request)
                    if (cnt_in < INPUT_LEN) begin
                        o_in_addr <= cnt_in; // 0 ~ 191
                        
                        // Weight 주소는 멈추지 않고 계속 증가 (0 ~ 1919)
                        // 단, cnt_in이 0일 때(S_CLEAR 직후)는 이미 셋팅된 값을 유지해야 할 수도 있음.
                        // 여기서는 깔끔하게 매 사이클 증가 (단, 첫 진입시 주의)
                        // FSM 구조상 S_CLEAR -> S_CALC 넘어올 때 o_w_addr는 유지됨.
                        // 따라서 여기서 요청 후 증가시키면 됨.
                        o_w_addr  <= o_w_addr + 1; 
                        
                        req_valid <= 1; // "나 방금 주소 요청했다" 표시
                        cnt_in    <= cnt_in + 1;
                    end else begin
                        req_valid <= 0; // 요청 끝
                    end
                    
                    // B. 상태 전이 조건
                    // 입력 요청도 끝났고(cnt_in == 192), 
                    // 파이프라인에 남은 마지막 데이터(req_valid) 처리도 끝났을 때
                    if (cnt_in == INPUT_LEN && req_valid == 0) begin
                        state <= S_OUTPUT;
                    end
                end

                // [Step 3] 결과 출력 알림
                S_OUTPUT: begin
                    // Core의 연산은 이미 끝났고 o_result에 값이 유지되고 있음
                    o_out_valid <= 1; // "가져가세요!"
                    
                    // 다음 뉴런으로 갈지, 끝낼지 결정
                    if (cnt_out == OUTPUT_LEN - 1) begin
                        state <= S_DONE;
                    end else begin
                        cnt_out <= cnt_out + 1;
                        state   <= S_CLEAR; // 다음 뉴런을 위해 리셋하러 이동
                    end
                end

                S_DONE: begin
                    o_done  <= 1;
                    o_ready <= 1;
                    state   <= S_IDLE;
                end
            endcase
        end
    end

    //==========================================================================
    // Pipeline Delay Logic (핵심!)
    //==========================================================================
    // BRAM/ROM은 주소를 주면 '다음 클럭'에 데이터가 나옵니다.
    // 따라서 '주소를 요청했다(req_valid)'는 신호를 1클럭 지연시켜서
    // Core의 '연산해라(o_core_valid)' 신호로 넣어줘야 타이밍이 딱 맞습니다.
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            o_core_valid <= 0;
        end else begin
            // S_CALC 상태에서 요청한 req_valid를 1클럭 뒤에 Core Enable로 전달
            o_core_valid <= req_valid;
        end
    end

endmodule