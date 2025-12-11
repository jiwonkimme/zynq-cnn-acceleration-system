/*
================================================================================
  Module Name:    mac_shift_register
  Description:    Zero-Latency Start Shift Register for 2D Convolution
                  (Optimized: No IDLE state, Immediate response to i_run)
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
    output  wire    [DATA_WIDTH*WINDOW_WIDTH-1:0]   o_mac_input,
    output  wire                                    o_window_row_done,
    output  wire                                    o_window_set_done
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
    assign o_mac_input = {i_col[0], i_col[1], i_col[2], i_col[3], i_col[4]};
    
    // Output control signals (Pulse High on the last cycle of operation)
    assign o_window_row_done = is_row_done && i_run;
    assign o_window_set_done = is_all_done && i_run;

endmodule