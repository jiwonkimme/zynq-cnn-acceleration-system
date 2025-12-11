/*
================================================================================
* Module Name:   mac_ctrl (Local Controller & Datapath Wrapper)
* Project:       Zynq CNN Acceleration System (LeNet-1)
* Architecture:  4x5 Weight-Stationary Systolic Array (WSSA)
*
* [ Control Strategy & FSM Description ]
*
* 1. Overview
* This controller implements a "Window-Set Based" tiling strategy to optimize
* throughput for 5x5 Convolution layers. It cooperates with PS software which
* pre-orders input/weight data to simplify PL logic.
*
* 2. Key Definitions
* - Window Set: A batch of 5 sliding windows processed in parallel.
* - Column Mapping: Each of the 5 columns in WSSA corresponds to one window
* in the current Window Set.
* - Row Mapping: Each of the 4 rows corresponds to an Output Channel.
*
* 3. Operation Flow (FSM States)
*
* [IDLE]
* - Wait for START signal from PS.
*
* [LOAD_WEIGHT] (Phase 1)
* - Load 5 weights (Index 0~4) into the array columns.
* - These weights correspond to the first part of the kernel for 4 channels.
*
* [COMPUTE] (Phase 2 - Main Loop)
* - Stream input data for the current Window Set (5 windows).
* - Cycle-by-cycle operations:
* a. READ: Fetch partial sums from Output BRAM (True Dual Port).
* b. MAC: Multiply input with loaded weights and add to partial sum.
* c. WRITE: Store updated partial sums back to Output BRAM.
* - This "Read-Modify-Write" loop accumulates results across the depth (N).
*
* [NEXT_WEIGHT_TILE] (Phase 3)
* - If input depth N > 5, load the next chunk of weights (e.g., Index 5~9).
* - Repeat COMPUTE to accumulate further.
*
* [STORE & DONE]
* - Once the full kernel (e.g., 5x5=25) is processed for the Window Set:
* - The Output BRAM contains valid 32-bit results for:
* [4 Channels] x [5 Windows] = 20 Results.
* - Signal DONE to PS.
* - PS reads 640 bits (20 * 32-bit) via AXI burst.
*
* 4. Memory Interface Strategy
* - Input/Weight BRAM: Simple Dual Port (PS Write / PL Read).
* - Output BRAM: True Dual Port (TDP) is required for the accumulation loop
* (PL reads current sum, adds, and writes back).
*
================================================================================
*/

/*
=====================================================================
    mac_ctrl.v
    - Shift Register for MAC Input Data Columns
    
    Algorithm Overview:
    for(i=0, WINDOW_SIZE-1; i++) {
        Weight_LOAD(BASE_ADDR + i * OFFSET_ADDR); // Load 5 weights for 4 channels
        for (j=0, MAX_COUNT-1; j++) { // Process all rows
            for(k=0, WINDOW_SIZE-1; k++) { // For each row, process 5 inputs
                if(k == 0) {
                    Input_LOAD(BASE_ADDR + j * OFFSET_ADDR); // Bulk load 5 pixels (40 bits)
                } else {
                    Input_SHIFT(Next_Pixel); // Shift in next pixel (8 bits)
                }
                PartialSum_READ(); // Read current partial sums from Output BRAM
                MAC_Compute();     // MAC operation with current inputs and weights
                PartialSum_WRITE(); // Write back updated partial sums to Output BRAM
            }
        }
    }
    Ouput_to_PS();
=====================================================================
*/

`timescale 1ns / 1ps

module mac_ctrl #(
    parameter WINDOW_WIDTH      = 5,    // Kernel width x width
    parameter WINDOW_HEIGHT     = 5,    // Kernel width x height
    parameter WINDOW_SET        = 24,   // Number of windows per window set
    parameter INPUT_DATA_WIDTH  = 8,    // Pixel width
    parameter INPUT_BUS_WIDTH   = 64,   // for upper 5 * 8 = 40 bits
    parameter OUTPUT_DATA_WIDTH = 32,   // Pixel width
    parameter OUTPUT_BUS_WIDTH  = 128,  // 32 * 4 = 128 bits
    parameter MAC_LATENCY       = 10     // LATENCY = IDLE (1) + SHIFT REGISTER (1) + INPUT LOADING (3) + OUTPUT DELAY (5) = 10-CYCLE
)(
    // Global Signal
    input  wire         clk,
    input  wire         rstn,
    
    // Control Interface
    input  wire         i_start,            // Start trigger
    input  wire         i_weight_load,      // Weight Load Enable
    output wire         o_weight_load_done, // Weight Load Done
    input  wire         i_input_load,       // Input Load Enable
    output wire         o_window_row_done,   // Window Row Done
    output wire         o_window_set_done,  // Window Set Done
    input  wire         i_overwrite,        // Overwrite signal for MAC Array
    output reg          o_compute,          // Compute Done from MAC Array
    output wire         o_compute_row_done,
    
    // Data Interface
    input  wire [INPUT_BUS_WIDTH-1:0]   i_bulk_data,    // Initial 5 pixels (Bulk load)
    input  wire [OUTPUT_BUS_WIDTH-1:0]  i_read_data,    // Partial Sum Read Data
    output wire [OUTPUT_BUS_WIDTH-1:0]  o_mac_output   //
);  
    
//======================================================================
// 1. Input BRAM -> Shift Register -> MAC Array
//======================================================================
    wire        [INPUT_BUS_WIDTH-1:0]                   shift_reg_input;
    wire        [INPUT_DATA_WIDTH*WINDOW_WIDTH-1:0]     i_mac_input;   // Data to Array
    wire        [INPUT_DATA_WIDTH*WINDOW_WIDTH-1:0]     i_mac_weight;   // Data to Array

    assign shift_reg_input  = (i_input_load) ? i_bulk_data : 0;
    assign i_mac_weight     = (i_weight_load) ? i_bulk_data : 0;

    mac_shift_register #(
        .WINDOW_WIDTH   (WINDOW_WIDTH),
        .WINDOW_HEIGHT  (WINDOW_HEIGHT),
        .DATA_WIDTH     (INPUT_DATA_WIDTH),
        .WINDOW_SET     (WINDOW_SET)
    ) u_mac_shift_register (
        .clk            (clk),
        .rstn           (rstn),
        .i_run          (i_input_load),
        .i_input_0      (shift_reg_input[39:32]),
        .i_input_1      (shift_reg_input[31:24]),
        .i_input_2      (shift_reg_input[23:16]),
        .i_input_3      (shift_reg_input[15:8]),
        .i_input_4      (shift_reg_input[7:0]),
        .o_mac_input    (i_mac_input),
        .o_window_row_done  (o_window_row_done),
        .o_window_set_done  (o_window_set_done)
    );

    mac_4x5_array u_mac_4x5_array (
        .clk            (clk),
        .rstn           (rstn),
        .en_x_i         (i_input_load),
        .en_w_i         ({5{i_weight_load}}),
        .stop_mac       (1'b0),
        .used_row       (1'b1),
        .overwrite_sig  (i_overwrite),
        .RDATA_O        (i_read_data),
        .x_i            (i_mac_input),
        .w_i            (i_mac_weight),
        .RESULT         (o_mac_output)
    );

//======================================================================
// FSM & Control Logic
//======================================================================
    parameter       IDLE                    = 3'b001,
                    LOAD_WEIGHT             = 3'b010,
                    COMPUTE                 = 3'b100;

    //parameter       PIXEL_COUNT_WIDTH       = $clog2(WINDOW_SET);

    wire            compute_start;
    wire            compute_done;

    reg     [2:0]   state, next_state;
    reg     [2:0]   row_count;
    reg     [3:0]   start_delay_cnt;

    reg     [MAC_LATENCY-1:0]   done_delay_sr;

    //reg     [PIXEL_COUNT_WIDTH-1:0]   compute_count;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            state   <= IDLE;
        end else begin
            state   <= next_state;
        end
    end

    always @(*) begin
        case (state)
            IDLE :          next_state = ((i_start) && (i_weight_load)) ?   LOAD_WEIGHT : IDLE;
            LOAD_WEIGHT :   next_state = (o_weight_load_done)           ?   COMPUTE     : LOAD_WEIGHT;
            COMPUTE :       next_state = (compute_done)                 ?   IDLE        : COMPUTE;
            default:        next_state = IDLE;
        endcase
    end

    assign  o_weight_load_done  = ((state == LOAD_WEIGHT) && (row_count == 3'd3)) ? 1'b1 : 1'b0; // After loading 5 weights

    // o_window_row_done 신호를 MAC_LATENCY 만큼 뒤로 미룸
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            done_delay_sr <= 0;
        end else if (state == COMPUTE) begin
            // Shift Left: LSB로 입력, MSB로 출력
            done_delay_sr <= {done_delay_sr[MAC_LATENCY-2:0], o_window_row_done};
        end else begin
            done_delay_sr <= 0;
        end
    end

    assign  compute_start   = (start_delay_cnt == MAC_LATENCY - 1)  ? 1'b1 : 1'b0; 
    //assign  compute_done    = ((row_count == 3'd4) && (compute_count == WINDOW_SET - 1)) ? 1'b1 : 1'b0; // After processing all windows
    assign  compute_done    = ((row_count == 3'd4) && o_compute_row_done) ? 1'b1 : 1'b0; // After processing all windows

    assign  o_compute_row_done    = done_delay_sr[MAC_LATENCY-1];

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            // Reset Logic
            row_count           <= 3'd0;
            //compute_count       <= {PIXEL_COUNT_WIDTH{1'b0}};
            o_compute           <= 1'b0;
            start_delay_cnt       <= 4'd0;
        end else begin
            case (state)
                IDLE : begin
                    // Reset Logic
                    row_count           <= 3'd0;
                    //compute_count       <= {PIXEL_COUNT_WIDTH{1'b0}};
                    o_compute           <= 1'b0;
                    start_delay_cnt       <= 4'd0;
                end
                LOAD_WEIGHT : begin
                    // Weight Loading Logic
                    if(o_weight_load_done) begin
                        row_count           <= 3'd0;
                    end else begin
                        row_count           <= row_count + 3'd1;
                    end
                end
                COMPUTE : begin
                    // A. Start Delay Handling (처음 유효 데이터 나올 때까지 대기)
                    if (start_delay_cnt < MAC_LATENCY-1) begin // Input Loading (3) + Output Loading (5)
                        start_delay_cnt <= start_delay_cnt + 1;
                        o_compute       <= 1'b0;
                    end else begin
                        // Latency 지나면 Valid High 유지
                        o_compute       <= 1'b1; 
                    end

                    // B. Row & Done Handling (지연된 신호 기준)
                    if (o_compute_row_done) begin
                        if (row_count == 3'd4) begin
                            // [All Finished]
                            o_compute       <= 1'b0;
                            row_count       <= 3'd0;
                            start_delay_cnt <= 4'd0;
                        end else begin
                            // [Row Finished] Next Row
                            row_count <= row_count + 3'd1;
                        end
                    end
                    /*
                    if(compute_done) begin
                        o_compute       <= 1'b0;
                        row_count       <= 3'd0;
                        start_delay_cnt <= 4'd0;
                        compute_count   <= {PIXEL_COUNT_WIDTH{1'b0}};
                    end else if(compute_start) begin
                        o_compute       <= 1'b1;
                        compute_count   <= compute_count + 1;
                        if(o_window_row_done) begin
                            row_count       <= row_count + 3'd1;
                            compute_count   <= {PIXEL_COUNT_WIDTH{1'b0}};
                        end 
                    end else begin
                        o_compute       <= 1'b0;
                        start_delay_cnt <= start_delay_cnt + 1;
                    end
                    */
                end
                default: begin
                    // Reset Logic
                    row_count           <= 3'd0;
                    // compute_count       <= {PIXEL_COUNT_WIDTH{1'b0}};
                    o_compute           <= 1'b0;
                    start_delay_cnt       <= 4'd0;
                end
            endcase
        end
    end
//======================================================================
endmodule