/*
================================================================================
  Module Name:    mac_shift_register
  Description:    Zero-Latency Start Shift Register for 2D Convolution Input Buffer
  
  ------------------------------------------------------------------------------
  [General Description]
  This module acts as a specialized input data buffer for a Weight-Stationary 
  Systolic Array (WSSA). It generates a sliding window output vector by 
  operating in a "Load-then-Shift" manner without FSM overhead.

  [Key Features & Optimizations]
  1. Zero-Latency Start: 
     - Eliminates the traditional IDLE state to maximize throughput.
     - The first valid operation (Bulk Load) occurs immediately on the 
       same cycle `i_run` is asserted high.
       
  2. PPA Optimized (Implicit Clock Gating):
     - When `i_run` is low, the logic holds its state (no explicit reset in `else`).
     - This allows synthesis tools to infer Clock Enable (CE) logic on registers, 
       significantly reducing dynamic power consumption during inactive periods.

  3. Hierarchical Counting:
     - pixel_count: Tracks the column index within a window set (0 ~ WINDOW_SET-1).
     - row_count  : Tracks the logical row index processed (0 ~ WINDOW_HEIGHT-1).

  ------------------------------------------------------------------------------
  [Operation Flow]
  1. Active State (i_run == 1):
     - IF (pixel_count == 0): "Bulk Load"
       -> Parallel loads all 5 input rows (`i_input_0`~`4`) into internal registers.
     - ELSE: "Shift & Inject"
       -> Shifts registers left and injects `i_input_4` into LSB.
       -> Increments `pixel_count`.
     
  2. Done Conditions:
     - `window_row_done`: Asserted at the last pixel of each row.
     - `window_set_done`: Asserted when all rows in a set are completed.
     - Counters automatically reset upon completion of a set, enabling 
       back-to-back operation without extra delay.

  3. Inactive State (i_run == 0):
     - Holds current state and values (Stall/Pause).
  
  ------------------------------------------------------------------------------
  [Parameters]
  - WINDOW_WIDTH  : Kernel Width (default: 5)
  - WINDOW_HEIGHT : Kernel Height / Row Batches (default: 5)
  - WINDOW_SET    : Length of one input row stream (default: 24)
  - DATA_WIDTH    : Bit-width of pixel data (default: 8)
================================================================================
*/

module mac_shift_register #(
    parameter WINDOW_WIDTH  = 5,    // Kernel width
    parameter WINDOW_HEIGHT = 5,    // Number of Rows to process
    parameter DATA_WIDTH    = 8,    // Pixel width
    parameter WINDOW_SET    = 24    // Windows per row
)(
    input   wire                                    clk,
    input   wire                                    rstn,
    input   wire                                    i_run,       // Active High Enable Signal
    input   wire    [DATA_WIDTH-1:0]                i_input_0,
    input   wire    [DATA_WIDTH-1:0]                i_input_1,
    input   wire    [DATA_WIDTH-1:0]                i_input_2,
    input   wire    [DATA_WIDTH-1:0]                i_input_3,
    input   wire    [DATA_WIDTH-1:0]                i_input_4,
    output  reg     [DATA_WIDTH*WINDOW_WIDTH-1:0]   o_mac_input,
    output  reg                                     o_window_row_done,
    output  reg                                     o_window_set_done
);

    // Derived Parameters
    localparam ROW_COUNT_WIDTH   = $clog2(WINDOW_HEIGHT);
    localparam PIXEL_COUNT_WIDTH = $clog2(WINDOW_SET);

    // Registers
    reg     [DATA_WIDTH-1:0]        i_col [0:WINDOW_WIDTH-1];
    reg     [PIXEL_COUNT_WIDTH-1:0] pixel_count;
    reg     [ROW_COUNT_WIDTH-1:0]   row_count;

    // Internal Flags
    wire    is_bulk_load;   // First pixel of a row -> Load all 5 inputs
    wire    is_row_done;    // Last pixel of a row
    wire    is_all_done;    // All rows completed

    wire    [DATA_WIDTH*WINDOW_WIDTH-1:0]   mac_input;
    wire                                    window_row_done;
    wire                                    window_set_done;

    // -------------------------------------------------------------------------
    // Control Logic
    // -------------------------------------------------------------------------
    
    // Check if we are at the start of a new row (Bulk Load condition)
    assign is_bulk_load = (pixel_count == {PIXEL_COUNT_WIDTH{1'b0}});

    // Check if current row is finished
    assign is_row_done  = (pixel_count == WINDOW_SET - 1);

    // Check if the entire Window Set (all rows) is finished
    // (Note: Valid only when i_run is active)
    assign is_all_done  = (row_count == WINDOW_HEIGHT - 1) && is_row_done;

    // -------------------------------------------------------------------------
    // Main Sequential Logic
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            // Asynchronous Reset
            {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= 0;
            pixel_count <= 0;
            row_count   <= 0;
        end 
        else if (i_run) begin
            // -----------------------------------------------------
            // 1. Data Path Operation (Load vs Shift)
            // -----------------------------------------------------
            if (is_bulk_load) begin
                // [Bulk Load] Load 5 new pixels at once (Start of Row)
                {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} 
                    <= {i_input_0, i_input_1, i_input_2, i_input_3, i_input_4};
            end 
            else begin
                // [Shift] Shift Left & Inject New Pixel at LSB
                // i_input_4 is used as the 'new pixel' source for shifting
                {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} 
                    <= {i_col[1], i_col[2], i_col[3], i_col[4], i_input_4};
            end

            // -----------------------------------------------------
            // 2. Counter Management
            // -----------------------------------------------------
            if (is_all_done) begin
                // [Done] Reset counters immediately for next run
                pixel_count <= 0;
                row_count   <= 0;
            end 
            else if (is_row_done) begin
                // [Row Done] Reset pixel counter, Increment row
                pixel_count <= 0;
                row_count   <= row_count + 1;
            end 
            else begin
                // [Normal] Increment pixel counter
                pixel_count <= pixel_count + 1;
            end
        end
        else begin
            // (Optional) If i_run is Low, hold values or reset?
            // Current: Hold values (Pause). 
            // If explicit reset needed when i_run=0, add logic here.
            // But usually 'done' logic above handles the reset for next run.
        end
    end

    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    // Pack 5 columns into flattened output vector
    assign mac_input = {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]};
    
    // Output control signals (Pulse High on the last cycle of operation)
    assign window_row_done = (pixel_count == WINDOW_SET - 1 - 1) && i_run;
    assign window_set_done = (row_count == WINDOW_HEIGHT - 1) && (pixel_count == WINDOW_SET - 1 - 1) && i_run;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            o_mac_input <= {DATA_WIDTH*WINDOW_WIDTH{1'b0}};
            o_window_row_done <= 1'b0;
            o_window_set_done <= 1'b0;
        end else begin
            o_mac_input <= mac_input;
            o_window_row_done <= window_row_done;
            o_window_set_done <= window_set_done;
        end
    end
endmodule