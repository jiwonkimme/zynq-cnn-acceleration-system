module max_pool_ctrl(
    input   wire        clk,
    input   wire        rstn,
    
    // [Input] Control & Data from Previous Layer (Relu/Quant)
    input   wire        i_frame_start,
    input   wire        i_mode,
    input   wire        i_valid,      
    input   wire [31:0] i_data,       
    
    // [Output] Status
    output  reg         o_done_pool,  // (Optional)
    output  wire        o_ready,      // Ready to receive new batch
    
    // [Output] BRAM Write Interface (BRAM은 밖에 있음!)
    output  reg         o_bram_en_reg,
    output  reg         o_bram_we_reg,
    output  reg  [7:0]  o_bram_addr_reg,
    output  reg  [31:0] final_w_data
);

    //==========================================================================
    // Internal Wires
    //==========================================================================
    wire        pool_valid;
    wire [31:0] pool_data;
    wire        pool_ready;

    assign o_ready = pool_ready; 

    //==========================================================================
    // 1. Frame Done Signal Generation Logic
    //==========================================================================
    // Mode 0 (Pool1): 12 * 12 = 144
    // Mode 1 (Pool2): 4 * 4 = 16
    localparam FRAME_SIZE_M0 = 144;
    localparam FRAME_SIZE_M1 = 16;

    reg [7:0] done_cnt; // 144까지 세야 하므로 8비트(Max 255) 필요
    
    // 현재 모드에 따른 목표값 선택
    wire [7:0] target_frame_size = (i_mode == 1'b0) ? FRAME_SIZE_M0 : FRAME_SIZE_M1;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            done_cnt    <= 0;
            o_done_pool <= 0;
        end else begin
            o_done_pool <= 0; // Pulse는 기본적으로 0

            if (i_frame_start) begin
                done_cnt <= 0; // 새 프레임 시작 시 초기화
            end 
            else if (pool_valid) begin
                // 유효한 출력이 나올 때마다 카운팅
                if (done_cnt == target_frame_size - 1) begin
                    // 전체 프레임의 마지막 픽셀인 경우
                    o_done_pool <= 1; // 1-Cycle Pulse 발생!
                    done_cnt    <= 0; // 0으로 리셋 (다음 프레임 대기)
                end else begin
                    done_cnt    <= done_cnt + 1;    
                end
            end
        end
    end

    wire [31:0] o_bram_data;
    reg [31:0]  prev_data [3:0];
    reg [1:0]   w_cnt, col_cnt, ch_cnt;
    wire o_bram_we;
    wire o_bram_en;
    wire [7:0] o_bram_addr;
    reg [3:0] ifmap_row_cnt;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            o_bram_we_reg <= 1'b0;
            o_bram_addr_reg <= 8'b0;
        end else begin
            o_bram_we_reg <= (o_bram_we||(w_cnt == 2'd3));
            o_bram_en_reg <= (o_bram_en||(w_cnt == 2'd3));
            if(i_mode == 1'b0) begin
                o_bram_addr_reg <= pool1_calc_addr;
            end else begin
                o_bram_addr_reg <= o_bram_addr;
            end
        end
    end

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            col_cnt         <=  2'd0;
            ch_cnt          <=  2'd0;

            prev_data[0]    <=  32'd0;  // ch0
            prev_data[1]    <=  32'd0;  // ch1
            prev_data[2]    <=  32'd0;  // ch2
            prev_data[3]    <=  32'd0;  // ch3
        end else if(i_mode == 1'b0) begin
            if(o_bram_we||w_cnt == 2'd3) begin //o_bram_we는 data 저장하는거로만 쓰고, case 문은 4-cycle pipeline FSM 추가.
                prev_data[ch_cnt]   <=  o_bram_data;
                if(ch_cnt == 2'd3) begin
                    ch_cnt  <=  2'd0;
                    if(col_cnt == 2'd2) begin
                        col_cnt <=  2'd0;
                    end else begin
                        col_cnt <=  col_cnt + 2'd1;
                    end
                end else begin
                    ch_cnt  <=  ch_cnt + 2'd1;
                end
            end 
        end
    end

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            final_w_data    <=  32'd0;
            w_cnt           <=  2'd0;
            ifmap_row_cnt   <=  4'd0;
        end else begin
            if(ch_cnt ==2'd3) begin
                if(w_cnt == 2'd3) begin
                    w_cnt   <=  2'd0;
                    ifmap_row_cnt <=  ifmap_row_cnt + 4'd1;
                end else begin
                    w_cnt   <=  w_cnt + 2'd1;
                end 
            end
            if(i_mode == 1'b0 && ifmap_row_cnt < 4'd12) begin    
                case(w_cnt)
                    0: final_w_data <=  {24'd0, o_bram_data[31:24]};
                    1: final_w_data <=  {prev_data[ch_cnt][23:0], o_bram_data[31:24]};
                    2: final_w_data <=  {prev_data[ch_cnt][23:0], o_bram_data[31:24]};
                    3: final_w_data <=  {prev_data[ch_cnt][31:8], 8'd0};
                    default : final_w_data  <=  o_bram_data;
                endcase
            end else begin
                final_w_data    <=  o_bram_data;
            end
        end
    end

    // Pool1 Address Calculation
    reg [7:0] pool1_calc_addr;
    
    always @(*) begin
        // 채널별 Base Address (0, 48, 96, 144)
        // + Row Offset (한 줄에 4 Word씩 차지하므로 row * 4)
        // + Current Word Offset (0, 1, 2, 3)
        case (ch_cnt)
            2'd0: pool1_calc_addr = (8'd0   + (ifmap_row_cnt << 2) + w_cnt);
            2'd1: pool1_calc_addr = (8'd48  + (ifmap_row_cnt << 2) + w_cnt);
            2'd2: pool1_calc_addr = (8'd96  + (ifmap_row_cnt << 2) + w_cnt);
            2'd3: pool1_calc_addr = (8'd144 + (ifmap_row_cnt << 2) + w_cnt);
            default: pool1_calc_addr = 0;
        endcase
    end

    //==========================================================================
    // 1. Max Pooling Core
    //==========================================================================
    max_pooling_2x2_core u_max_pool (
        .clk        (clk),
        .rstn       (rstn),
        .i_mode     (i_mode),

        .i_valid    (i_valid), 
        .i_data     (i_data),

        .o_valid    (pool_valid), 
        .o_data     (pool_data), 
        .o_ready    (pool_ready)
    );

    //==========================================================================
    // 2. Pool to BRAM Controller (Addr/Data Gen)
    //==========================================================================
    // BRAM에 쓸 주소와 데이터를 만들어내는 로직
    pool_to_bram u_pool_to_bram (
        .clk        (clk),
        .rstn       (rstn),
        .i_valid    (pool_valid),
        .i_data     (pool_data),
        .i_frame_rst(i_frame_start),
        
        // BRAM 제어 신호를 밖으로 토스!
        .o_bram_en  (o_bram_en),    
        .o_bram_we  (o_bram_we),
        .o_bram_addr(o_bram_addr),
        .o_bram_data(o_bram_data)
    );

endmodule