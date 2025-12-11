/*
================================================================================
  Module Name:    mac_ctrl
  Description:    Local Controller & Datapath Wrapper for 4x5 WSSA
  
  ------------------------------------------------------------------------------
  [General Description]
  This module serves as the main controller for the 4x5 Weight-Stationary 
  Systolic Array (WSSA). It orchestrates the entire convolution process by 
  managing the data flow of weights and inputs, and synchronizing the 
  MAC operation timing.

  [Key Features]
  1. Window-Set Based Control:
     - Processes input data in batches of 'WINDOW_SET' (default: 24) to 
       optimize data reuse and throughput for 5x5 convolution.
       
  2. Latency-Aware Synchronization:
     - Includes a built-in delay line (`done_delay_sr`) to compensate for the 
       MAC array's pipeline latency (`MAC_LATENCY`).
     - Aligns the Input Done signal (`window_row_done`) with the Output Valid 
       signal (`o_compute`), ensuring precise output data tracking.

  3. Zero-Latency Input Buffer Integration:
     - Wraps `mac_shift_register` to feed data immediately without FSM idle cycles.

  ------------------------------------------------------------------------------
  [FSM State Description]
  1. IDLE:
     - Waits for `i_start` and `i_weight_load` trigger. Resets internal counters.
     
  2. LOAD_WEIGHT (Phase 1):
     - Loads kernel weights into the Systolic Array columns row-by-row.
     - Transitions to COMPUTE state when 4 rows (4 channels) are fully loaded.
     
  3. COMPUTE (Phase 2):
     - Streams input data into the Shift Register.
     - Waits for `MAC_LATENCY` cycles for the pipeline to fill (`start_delay_cnt`).
     - Generates `o_compute` (Valid) signal while valid data is being produced.
     - Uses delayed signals to track row completion and transitions back to IDLE
       after processing all rows and window sets.

  ------------------------------------------------------------------------------
  [Parameters]
  - WINDOW_WIDTH/HEIGHT : Kernel dimensions (5x5).
  - WINDOW_SET          : Number of sliding windows per batch (24).
  - MAC_LATENCY         : Total pipeline depth (Input -> Valid Output). 
                          Default 10 (Idle 1 + Shift 1 + Load 3 + Delay 5).
================================================================================
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
    parameter MAC_LATENCY       = 12     // LATENCY = IDLE (1) + SHIFT REGISTER (1) + INPUT LOADING (3) + OUTPUT DELAY (5) = 10-CYCLE
)(
    // Global Signal
    input  wire         clk,
    input  wire         rstn,
    
    // Control Interface
    input  wire         i_start,            // Start trigger
    input  wire         i_weight_load,      // Weight Load Enable
    output reg          o_weight_load_done, // Weight Load Done
    input  wire         i_input_load,       // Input Load Enable
    output wire         o_window_row_done,   // Window Row Done
    output wire         o_window_set_done,  // Window Set Done
    input  wire         i_overwrite,        // Overwrite signal for MAC Array
    output reg          o_compute,          // Compute Done from MAC Array
    output reg          o_compute_row_done,
    
    // Data Interface
    input  wire [INPUT_BUS_WIDTH-1:0]   i_bulk_data,    // Initial 5 pixels (Bulk load)
    input  wire [OUTPUT_BUS_WIDTH-1:0]  i_read_data,    // Partial Sum Read Data
    output reg  [OUTPUT_BUS_WIDTH-1:0]  o_mac_output   //
);  

//======================================================================
// 1. Input BRAM -> Shift Register -> MAC Array
//======================================================================
    wire        [INPUT_BUS_WIDTH-1:0]                   shift_reg_input;
    wire        [INPUT_DATA_WIDTH*WINDOW_WIDTH-1:0]     i_mac_input;   // Data to Array
    wire        [INPUT_DATA_WIDTH*WINDOW_WIDTH-1:0]     i_mac_weight;   // Data to Array

    wire weight_load_done, compute_row_done;
    wire [OUTPUT_BUS_WIDTH-1:0] mac_output;

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

    reg i_input_load_reg;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            i_input_load_reg <= 1'b0;
        end else begin
            i_input_load_reg <= i_input_load; 
        end
    end

    mac_4x5_array u_mac_4x5_array (
        .clk            (clk),
        .rstn           (rstn),
        .en_x_i         (i_input_load_reg),
        .en_w_i         ({5{i_weight_load}}),
        .stop_mac       (1'b0),
        .used_row       (1'b1),
        .overwrite_sig  (i_overwrite),
        .RDATA_O        (i_read_data),
        .x_i            (i_mac_input),
        .w_i            (i_mac_weight),
        .RESULT         (mac_output)
    );

//======================================================================
// FSM & Control Logic
//======================================================================
    parameter       IDLE                    = 3'b001,
                    LOAD_WEIGHT             = 3'b010,
                    COMPUTE                 = 3'b100;

    wire            compute_start;
    wire            compute_done;

    reg     [2:0]   state, next_state;
    reg     [2:0]   row_count;
    reg     [3:0]   start_delay_cnt;

    reg     [MAC_LATENCY-1:0]   done_delay_sr;

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
            LOAD_WEIGHT :   next_state = (weight_load_done)             ?   COMPUTE     : LOAD_WEIGHT;
            COMPUTE :       next_state = (compute_done)                 ?   IDLE        : COMPUTE;
            default:        next_state = IDLE;
        endcase
    end

    assign  weight_load_done  = ((state == LOAD_WEIGHT) && (row_count == 3'd3 - 3'd1)) ? 1'b1 : 1'b0; // After loading 5 weights

    // window_row_done 신호를 MAC_LATENCY 만큼 뒤로 미룸
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

    assign  compute_row_done    = done_delay_sr[MAC_LATENCY-1-1];
    assign  compute_start       = (start_delay_cnt == MAC_LATENCY - 1)  ? 1'b1 : 1'b0; 
    assign  compute_done        = ((row_count == 3'd4) && compute_row_done) ? 1'b1 : 1'b0; // After processing all windows

    parameter START_LATENCY = 1;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            // Reset Logic
            row_count           <= 3'd0;
            o_compute           <= 1'b0;
            start_delay_cnt       <= 4'd0;
        end else begin
            case (state)
                IDLE : begin
                    // Reset Logic
                    row_count           <= 3'd0;
                    o_compute           <= 1'b0;
                    start_delay_cnt       <= 4'd0;
                end
                LOAD_WEIGHT : begin
                    // Weight Loading Logic
                    if(weight_load_done) begin
                        row_count           <= 3'd0;
                    end else begin
                        row_count           <= row_count + 3'd1;
                    end
                end
                COMPUTE : begin
                    // A. Start Delay Handling (처음 유효 데이터 나올 때까지 대기)
                    if (start_delay_cnt < START_LATENCY + MAC_LATENCY-1) begin // Input Loading (3) + Output Loading (5)
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
                end
                default: begin
                    // Reset Logic
                    row_count           <= 3'd0;
                    o_compute           <= 1'b0;
                    start_delay_cnt       <= 4'd0;
                end
            endcase
        end
    end
//======================================================================

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            o_compute_row_done <= 1'b0;
            o_weight_load_done <= 1'b0;
            o_mac_output <= {OUTPUT_BUS_WIDTH{1'b0}};
        end else begin
            o_compute_row_done <= compute_row_done;
            o_weight_load_done <= weight_load_done;
            o_mac_output <= mac_output;
        end
    end
endmodule