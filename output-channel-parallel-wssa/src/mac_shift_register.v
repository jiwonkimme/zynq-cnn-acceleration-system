/*
================================================================================
  Module Name:    mac_shift_register_24w
  Description:    Parameterized Shift Register Buffer for 2D Convolution (Sliding Window)
  
  ------------------------------------------------------------------------------
  [Functional Overview]
  This module acts as an input data buffer for MAC units performing 2D convolution.
  It generates a sliding window output by operating in a "Load-then-Shift" manner.
  Unlike the single-window version, this module is designed to process a continuous 
  set of windows (defined by WINDOW_SET) across multiple logical rows.

  [Operation Sequence]
  The module utilizes two counters: `pixel_count` (Column) and `row_count` (Row).
  
    1. Bulk Load (pixel_count == 0):
       - Simultaneously loads 5 rows of input data (`i_input_0` ~ `i_input_4`).
       - Initializes the shift register for the start of a new window sequence.
       
    2. Shift Operation (pixel_count == 1 ~ WINDOW_SET-1):
       - Shifts the register values to the left (Next Pixel).
       - Injects new data (`i_input_4`) into the LSB to update the window.
       - Generates valid sliding windows for MAC operations continuously.

    3. Row & Set Management:
       - The operation repeats for `WINDOW_SET` cycles (default: 24 windows).
       - After completing one set, `row_count` increments, and the process repeats.
       - The module finishes when `WINDOW_HEIGHT` number of sets are processed.

  [FSM Control]
  - IDLE : Waiting for `i_run` trigger.
  - SHIFT: Active state performing Load/Shift operations.
           Transitions back to IDLE only when `window_set_done` is asserted.

  ------------------------------------------------------------------------------
  [Parameters]
  - WINDOW_WIDTH  : Kernel width (Default: 5)
  - WINDOW_HEIGHT : Kernel height / Number of Row sets to process (Default: 5)
  - WINDOW_SET    : Number of sliding windows per row (Default: 24)
  - DATA_WIDTH    : Pixel bit-width (Default: 8)

  [I/O Description]
  - i_run         : Level-sensitive start signal.
  - i_input_0~4   : Parallel input data for 5 rows.
  - o_mac_input   : Flattened vector containing the current N-pixel window.
================================================================================
*/

module mac_shift_register #(
    parameter WINDOW_WIDTH  = 5,    // Kernel width x height
    parameter WINDOW_HEIGHT = 5,    // Kernel width x height
    parameter DATA_WIDTH    = 8,    // Pixel data width
    parameter WINDOW_SET    = 24    // Number of windows per window set
)(
    input   wire                                    clk,
    input   wire                                    rstn,
    input   wire                                    i_run,
    input   wire    [DATA_WIDTH-1:0]                i_input_0,
    input   wire    [DATA_WIDTH-1:0]                i_input_1,
    input   wire    [DATA_WIDTH-1:0]                i_input_2,
    input   wire    [DATA_WIDTH-1:0]                i_input_3,
    input   wire    [DATA_WIDTH-1:0]                i_input_4,
    output  wire    [DATA_WIDTH*WINDOW_WIDTH-1:0]   o_mac_input,
    output  wire                                    o_input_load_done
);
    parameter ROW_COUNT_WIDTH   = $clog2(WINDOW_HEIGHT);
    parameter PIXEL_COUNT_WIDTH = $clog2(WINDOW_SET);

    // Shift Register for Input Data Columns
    reg     [DATA_WIDTH-1:0]        i_col [0:WINDOW_WIDTH-1]; // 5 shift registers for 5 columns
    reg     [PIXEL_COUNT_WIDTH-1:0] pixel_count;
    reg     [ROW_COUNT_WIDTH-1:0]   row_count;

    wire                            row_first_load;
    wire                            row_done;
    wire                            window_set_done;


    parameter IDLE      = 1'b0,
              SHIFT     = 1'b1;

    reg state, next_state;

    // FSM State Transition
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    assign row_first_load   = (pixel_count == {PIXEL_COUNT_WIDTH{1'b0}})                        ? 1'b1 : 1'b0;
    assign row_done         = (pixel_count == WINDOW_SET-1)                                     ? 1'b1 : 1'b0; // 1 row of 24 windows in a window set    
    assign window_set_done  = (row_count == WINDOW_HEIGHT-1) && row_done                        ? 1'b1 : 1'b0; // After 5 windows
    
    // Next State Logic
    always @(*) begin
        case(state)
            IDLE: next_state    = (i_run && !window_set_done)           ? SHIFT : IDLE;
            SHIFT: next_state   = (window_set_done)                     ? IDLE : SHIFT;
            default: next_state = IDLE;
        endcase
    end

    wire    [7:0] i_new_data;
    assign  i_new_data  = i_input_4;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= 40'd0;
            pixel_count  <= {PIXEL_COUNT_WIDTH{1'b0}};
            row_count    <= {ROW_COUNT_WIDTH{1'b0}};
        end else begin
            case(state)
                IDLE: begin
                    // 초기화
                    {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= 40'd0;
                    pixel_count  <= {PIXEL_COUNT_WIDTH{1'b0}};
                    row_count    <= {ROW_COUNT_WIDTH{1'b0}};
                end
                SHIFT: begin
                    // ------------------------------------------------
                    // A. Data Operation (Load at 0, Shift otherwise)
                    // ------------------------------------------------
                    if(row_first_load) begin
                        // Shift Register
                        // Next Window Set (Bulk Load)
                        {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= {i_input_0, i_input_1, i_input_2, i_input_3, i_input_4};
                    end else begin
                        {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= {i_col[1], i_col[2], i_col[3], i_col[4], i_new_data}; 
                    end

                    // ------------------------------------------------
                    // B. Counter Update Logic
                    // ------------------------------------------------
                    if(row_done) begin
                        pixel_count <= {PIXEL_COUNT_WIDTH{1'b0}};
                        if(!window_set_done) begin
                            row_count    <= row_count + 1;
                        end
                    end else begin
                        pixel_count      <= pixel_count + 1;
                    end
                end
            endcase
        end
    end

    assign o_mac_input = {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]};
    assign o_input_load_done = window_set_done;
endmodule