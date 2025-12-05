/*
================================================================================
  Module Name:    mac_shift_register
  Description:    Shift Register Buffer for 2D MAC (Convolution) Operations
  
  ------------------------------------------------------------------------------
  [Functional Overview]
  This module serves as an input data buffer for a 5x5 sliding window convolution.
  It manages a 5-element shift register (`i_col`) to efficiently feed pixel data 
  to the MAC unit. It operates in a "Load-then-Shift" pattern to maximize data reuse.

  [Operation Sequence]
  The module uses a counter (`pixel_count`) running from 0 to 4:
    1. Count == 0 (Bulk Load): 
       - Loads 5 rows of input data (`i_input_0` ~ `i_input_4`) in parallel.
       - Represents the start of a new column in the input feature map.
       
    2. Count == 1~4 (Shift): 
       - Shifts the register values to the left (i_col[0] <= i_col[1]...).
       - Injects new data (`i_input_4`) into the LSB.
       - Represents the sliding window moving horizontally.

  [FSM & Control]
  - IDLE: Waits for `i_run` signal.
  - SHIFT: Executes the Load/Shift operation for `WINDOW_SET` times (5 sets).
  - DONE: Assert `o_input_load_done` when all sets are processed.

  ------------------------------------------------------------------------------
  [Parameters]
  - WINDOW_SIZE : Kernel width (Default: 5)
  - DATA_WIDTH  : Pixel bit-width (Default: 8-bit)
  - WINDOW_SET  : Number of window sets to process (Default: 5)

  [I/O Description]
  - i_run       : Start trigger (Level signal)
  - i_input_X   : 5 parallel input data channels (8-bit each)
  - o_mac_input : Flattened 40-bit output (5 pixels x 8 bits) to MAC unit
================================================================================
*/

module mac_shift_register #(
    parameter WINDOW_SIZE   = 5,    // 5x5 Kernel width
    parameter DATA_WIDTH    = 8,     // Pixel width
    parameter WINDOW_SET    = 5    // Number of rows per window set
)(
    input   wire                                    clk,
    input   wire                                    rstn,
    input   wire                                    i_run,
    input   wire    [DATA_WIDTH-1:0]                i_input_0,
    input   wire    [DATA_WIDTH-1:0]                i_input_1,
    input   wire    [DATA_WIDTH-1:0]                i_input_2,
    input   wire    [DATA_WIDTH-1:0]                i_input_3,
    input   wire    [DATA_WIDTH-1:0]                i_input_4,
    output  wire    [DATA_WIDTH*WINDOW_SIZE-1:0]    o_mac_input,
    output  wire                                    o_input_load_done
);
    // Shift Register for Input Data Columns
    reg     [DATA_WIDTH-1:0]    i_col [0:WINDOW_SIZE-1]; // 5 shift registers for 5 columns
    reg     [2:0]               pixel_count;
    reg     [2:0]               window_count;

    wire                        row_first_load;
    wire                        window_done;
    wire                        window_set_done;


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

    assign row_first_load   = (pixel_count == 3'd0) ? 1'b1 : 1'b0;
    assign window_done      = (pixel_count == 3'd4)   ? 1'b1 : 1'b0; // Each 5 rows in a window (0~4)    
    assign window_set_done  = (window_count == WINDOW_SET-1) && (pixel_count == WINDOW_SIZE-1)    ? 1'b1 : 1'b0; // After 5 windows
    
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
            pixel_count     <= 3'd0;
            window_count    <= 3'd0;
        end else begin
            case(state)
                IDLE: begin
                    // 초기화
                    pixel_count     <= 3'd0;
                    window_count    <= 3'd0;
                    {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]} <= 40'd0;
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
                    if(window_done) begin
                        pixel_count     <= 3'd0;
                        if(!window_set_done) begin
                            window_count    <= window_count + 3'd1;
                        end
                    end else begin
                        pixel_count         <= pixel_count + 3'd1;
                    end
                end
            endcase
        end
    end

    assign o_mac_input = {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]};
    assign o_input_load_done = window_set_done;
endmodule