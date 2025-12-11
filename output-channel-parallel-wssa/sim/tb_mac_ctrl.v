`timescale 1ns / 1ps

module tb_mac_ctrl;

    //==========================================================================
    // 1. Parameter Declaration (Must match DUT)
    //==========================================================================
    parameter WINDOW_WIDTH      = 5;
    parameter WINDOW_HEIGHT     = 5;
    parameter WINDOW_SET        = 24;

    parameter TEST_LENGTH       = 120; // 총 검증할 데이터 개수 (5 Sets)

    parameter INPUT_DATA_WIDTH  = 8;
    parameter INPUT_BUS_WIDTH   = 64;  // Uses lower 40 bits (5 bytes)
    parameter OUTPUT_DATA_WIDTH = 32;
    parameter OUTPUT_BUS_WIDTH  = 128; // 4 rows * 32 bits
    
    parameter CLK_PERIOD        = 10;  // 100MHz Clock

    //==========================================================================
    // 2. Signal Declaration
    //==========================================================================
    // Inputs (Reg)
    reg clk;
    reg rstn;
    
    // Control Inputs
    reg i_start;
    reg i_weight_load;
    reg i_input_load;
    reg i_overwrite;
    
    // Data Inputs
    reg [INPUT_BUS_WIDTH-1:0]  i_bulk_data; // Input/Weight (Packed 5 bytes)
    reg [OUTPUT_BUS_WIDTH-1:0] i_read_data; // Partial Sum from BRAM
    
    // Outputs (Wire)
    wire o_weight_load_done;
    wire o_window_set_done;
    wire o_window_row_done;
    wire o_compute;
    wire o_compute_row_done;
    wire [OUTPUT_BUS_WIDTH-1:0] o_mac_output;

    wire [INPUT_DATA_WIDTH-1:0] i_input [4:0];
    assign i_input [0] = i_bulk_data [7:0];
    assign i_input [1] = i_bulk_data [15:8];
    assign i_input [2] = i_bulk_data [23:16];
    assign i_input [3] = i_bulk_data [31:24];
    assign i_input [4] = i_bulk_data [39:32];

    reg [4:0] compute_cnt;

    reg [127:0] golden_mem [TEST_LENGTH-1:0];
    reg [127:0] expected_val;
    integer err_cnt;
    integer v_cnt, r_cnt; // Verification Counter

    // Loop Variables
    integer i;
    integer cnt; // 패턴 생성용 카운터 (0~23)
    integer input_cnt; // 전체 입력 개수 카운터 (0~119)

    //==========================================================================
    // 3. DUT Instantiation
    //==========================================================================
    mac_ctrl #(
        .WINDOW_WIDTH       (WINDOW_WIDTH),
        .WINDOW_HEIGHT      (WINDOW_HEIGHT),
        .WINDOW_SET         (WINDOW_SET),
        .INPUT_DATA_WIDTH   (INPUT_DATA_WIDTH),
        .INPUT_BUS_WIDTH    (INPUT_BUS_WIDTH),
        .OUTPUT_DATA_WIDTH  (OUTPUT_DATA_WIDTH),
        .OUTPUT_BUS_WIDTH   (OUTPUT_BUS_WIDTH)
    ) u_dut (
        // Global
        .clk                (clk),
        .rstn               (rstn),
        
        // Control Interface
        .i_start            (i_start),
        .i_weight_load      (i_weight_load),
        .o_weight_load_done (o_weight_load_done),
        .i_input_load       (i_input_load),
        .o_window_set_done  (o_window_set_done),
        .o_window_row_done  (o_window_row_done),
        .i_overwrite        (i_overwrite),
        .o_compute          (o_compute),
        .o_compute_row_done (o_compute_row_done),
        
        // Data Interface
        .i_bulk_data        (i_bulk_data),
        .i_read_data        (i_read_data),
        .o_mac_output       (o_mac_output)
    );

    //==========================================================================
    // 4. Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // 5. Test Stimulus
    //==========================================================================
    initial begin
        // [Initialization]
        cnt = 0;
        rstn = 0;
        i_start = 0;
        i_weight_load = 0;
        i_input_load = 0;
        i_overwrite = 0;
        i_bulk_data = 0;
        i_read_data = 0; // 초기 Partial Sum은 0이라고 가정

        // [Reset Release]
        #(CLK_PERIOD * 5);
        rstn = 1;
        #(CLK_PERIOD * 5);

        //----------------------------------------------------------------------
        // Phase 1: Start & Load Weights
        //----------------------------------------------------------------------
        $display("[TB] Simulation Start: Phase 1 - Weight Loading");
        
        i_start = 1;
        #(CLK_PERIOD);
        i_weight_load = 1;


        i_bulk_data = {24'h0, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07}; 
        #(CLK_PERIOD);
        // 4 Row에 대해 Weight 5개씩 로딩 (총 4 사이클)
        for (i=0; i<4; i=i+1) begin
            if(i_weight_load) begin
                if(o_weight_load_done) begin
                    #(CLK_PERIOD);
                    i_weight_load =0;
                end else begin
                    // Example Data: 0x0102030405 (packed 5 bytes)
                    i_bulk_data = i_bulk_data - {24'h0, 8'h01, 8'h01, 8'h01, 8'h01, 8'h01};
                    #(CLK_PERIOD);
                end
            end
        end
        
        // Wait for DUT to assert o_weight_load_done
        $display("[TB] Weight Load Done Signal Detected!");

        //#(CLK_PERIOD);

        //----------------------------------------------------------------------
        // Phase 2: Compute (Stream Inputs)
        //----------------------------------------------------------------------
        $display("[TB] Phase 2 - Compute Start");

        
        i_bulk_data = {24'h0, 8'h00, 8'h01, 8'h02, 8'h03, 8'h04};
        i_input_load = 1;
        i_overwrite = 0; // 0: Accumulate Mode (Add with i_read_data)
        cnt = 0; 
        compute_cnt = 0;

        fork
            // [Process 1] Data Feeder (데이터를 계속 갱신하며 밀어넣음)
            begin
                while(i_input_load) begin
                    #(CLK_PERIOD);
                    if (cnt < 23) begin
                        i_bulk_data = i_bulk_data + {24'h0, 8'h01, 8'h01, 8'h01, 8'h01, 8'h01};
                        cnt = cnt + 1;
                    end else begin
                        i_bulk_data = i_bulk_data + {24'h0, 8'h05, 8'h05, 8'h05, 8'h05, 8'h05};
                        cnt = 0;
                    end 
                end
            end

            // [Process 2] Monitor (완료 신호 감시)
            begin
                // Window Set Done이 뜰 때까지 대기
                wait(o_window_set_done == 1'b1);
                $display("[TB] Window Set Done Signal Detected!");
                
                // 감지 즉시 다음 클럭에 input load를 껴서 Feeder를 멈춤
                //@(posedge clk);
                #(CLK_PERIOD);
                @(negedge clk);
                i_input_load = 0; 
            end

            begin
                wait(o_compute == 1'b1);

                while(o_compute) begin
                    @(posedge clk);
                    if(o_compute_row_done) begin
                        compute_cnt = 0;
                        $display("[TB] Row Compute Finished at Time %t", $time);
                    end else begin
                        compute_cnt = compute_cnt + 1;
                    end
                end
            end

            // [Process 3] Output Monitor & Golden Model Verification
            begin
                // 1. Golden Data Memory 선언 (Depth=24, Width=128bit)
                err_cnt = 0;
                v_cnt = 0;
                r_cnt = 0;

                // 2. Load Hex File
                // 시뮬레이션 실행 전 파일 경로를 정확히 확인하세요!
                $readmemh("golden_result.hex", golden_mem);
                $display("[TB] Loaded Golden Model from 'golden_result.hex'");

                // 3. Wait for Compute Start
                wait(o_compute == 1'b1);
                
                $display("\n============================================================");
                $display(" [TB] Start Verification (File Comparison Mode)");
                $display("============================================================\n");

                // 4. Comparison Loop
                while(o_compute) begin
                    @(negedge clk);
                    #1; // Sampling Delay

                    // A. Fetch Expected Data
                    if (r_cnt < 5) begin
                        expected_val = golden_mem[v_cnt + WINDOW_SET * r_cnt];
                    end else begin
                        expected_val = 128'hXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX; // Out of bound
                    end

                    // B. Compare (128-bit Full Compare)
                    if (o_mac_output !== expected_val) begin
                        $display("[FAIL] Time: %0t | Col: %2d", $time, v_cnt);
                        $display("       Exp: %h", expected_val);
                        $display("       Act: %h", o_mac_output);
                        
                        // (Optional) Row별 상세 디버깅
                        if(o_mac_output[31:0]   !== expected_val[31:0])   $display("       -> Row 0 Mismatch!");
                        if(o_mac_output[63:32]  !== expected_val[63:32])  $display("       -> Row 1 Mismatch!");
                        if(o_mac_output[95:64]  !== expected_val[95:64])  $display("       -> Row 2 Mismatch!");
                        if(o_mac_output[127:96] !== expected_val[127:96]) $display("       -> Row 3 Mismatch!");
                        
                        err_cnt = err_cnt + 1;
                    end else begin
                        // Pass Log (간략하게)
                        $display("[PASS] Time: %0t | Col: %2d | Data Match: %h", $time, v_cnt, o_mac_output);
                    end

                    // C. Counter Update
                    if(v_cnt == WINDOW_SET - 1) begin
                        $display("------------------------------------------------------------");
                        $display(" [TB] Window Set Finished. Total Errors: %0d", err_cnt);
                        if(err_cnt == 0) $display(" [TB] >>> TEST PASSED (All Data Match) <<<");
                        else             $display(" [TB] >>> TEST FAILED <<<");
                        $display("------------------------------------------------------------\n");
                        v_cnt = 0; 
                        r_cnt = r_cnt + 1;
                    end else begin
                        v_cnt = v_cnt + 1;
                    end
                end
            end
        join

        // Compute가 완전히 끝날 때까지 대기 (Falling Edge)
        wait(o_compute == 1'b0); 
        $display("[TB] Compute Done Signal Detected!");

        #(CLK_PERIOD * 10);
        $display("[TB] Simulation Finished");
        $finish;
    end

endmodule