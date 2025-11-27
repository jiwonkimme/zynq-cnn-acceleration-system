//////////////////////////////////////////////////////////////////////////////////
// Module Name:    mac_4x4_array
// Project Name:   Zynq CNN Acceleration System
// Description:    
//    - A 4x4 Systolic Array composed of 4 columns.
//    - Manages diagonal data feeding (skewing) for Input Feature Maps.
//    - Collects and aligns 4 parallel output results.
//
// Modifications for CNN Inference:
//    1. [I/O Expansion] Expanded Result Bus (RESULT) and Partial Sum Input (RDATA_O) 
//       from 64-bit to 128-bit (to carry four 32-bit values).
//    2. [Internal Logic] Expanded all internal pipeline registers (latency delays) 
//       and adder trees to support 32-bit precision.
//    3. [Slicing Logic] Updated data slicing logic to handle 128-bit concatenated data
//       (e.g., [127:96], [95:64], ... instead of 16-bit chunks).
//////////////////////////////////////////////////////////////////////////////////


module mac_4x4_array(
    input wire                  CLK,
    input wire                  RSTN,
    input wire                  en_x_i,
    input wire          [3:0]   en_w_i,
    input wire                  stop_mac,
    input wire                  used_row,
    input wire                  overwrite_sig,
    input wire  signed  [127:0]  RDATA_O,

    input wire          [31:0]  x_i,
    input wire  signed  [31:0]  w_i,

    output wire signed  [127:0]  RESULT
);

    reg         [31:0]  I;
    reg signed  [31:0]  W;
    reg signed  [127:0]  RDATA_O_reg;
    reg         [3:0]   en_w_i_reg;
    reg                 stop_mac_pipe;
    reg                 used_row_pipe;

    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            I               <=  32'd0;
            W               <=  32'd0;
            stop_mac_pipe   <=  1'b0;
            used_row_pipe   <=  1'b0;
            RDATA_O_reg     <=  128'd0;
        end else begin
            I               <=  x_i;
            W               <=  w_i;
            stop_mac_pipe   <=  stop_mac;
            used_row_pipe   <=  used_row;
            RDATA_O_reg     <=  RDATA_O;
        end
    end

    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            en_w_i_reg      <=  4'd0;
        end else if(en_w_i)begin
            en_w_i_reg      <=  en_w_i;
        end else begin 
            en_w_i_reg      <=  en_w_i_reg;
        end
    end

    // column 별로 4행에 대한 wire signed 선언
    wire        [7:0]  x_i_1;
    wire signed [7:0]  w_i_1;

    wire        [7:0]  x_i_2;
    wire signed [7:0]  w_i_2;

    wire        [7:0]  x_i_3;
    wire signed [7:0]  w_i_3;

    wire        [7:0]  x_i_4;
    wire signed [7:0]  w_i_4;

    // row 별로 4열에 대한 wire signed 선언
    wire signed [31:0] after_sum_1 [0:3];
    wire signed [31:0] after_sum_2 [0:3];
    wire signed [31:0] after_sum_3 [0:3];
    wire signed [31:0] after_sum_4 [0:3];

    // column 별로 4행에 대한 assign
    assign  x_i_1    =   I [31:24];
    assign  x_i_2    =   I [23:16];
    assign  x_i_3    =   I [15:8];
    assign  x_i_4    =   I [7:0];

    assign  w_i_1    =   W [31:24];
    assign  w_i_2    =   W [23:16];
    assign  w_i_3    =   W [15:8];
    assign  w_i_4    =   W [7:0];

    // input delay
    /*
        1열 0-cycle delay
        2열 1-cycle delay
        3열 2-cycle delay
        4열 3-cycle delay
    */

    reg         [7:0]   x_i_2_1d;
    reg         [7:0]   x_i_3_2d        [0:1];
    reg         [7:0]   x_i_4_3d        [0:2];
    reg signed  [31:0]  RDATA_O_i_2_1d;
    reg signed  [31:0]  RDATA_O_i_3_2d  [0:1];
    reg signed  [31:0]  RDATA_O_i_4_3d  [0:2];
    reg                 stop_mac_2_1d;
    reg                 stop_mac_3_2d   [0:1];
    reg                 stop_mac_4_3d   [0:2];

    wire signed [31:0]  RDATA_O_i       [0:3];
    
    // 128-bit bus slicing - 32-bit 단위
    assign RDATA_O_i[0]  =   (overwrite_sig) ? RDATA_O_reg[127:96] : 32'd0;
    assign RDATA_O_i[1]  =   (overwrite_sig) ? RDATA_O_reg[95:64]  : 32'd0;
    assign RDATA_O_i[2]  =   (overwrite_sig) ? RDATA_O_reg[63:32]  : 32'd0;
    assign RDATA_O_i[3]  =   (overwrite_sig) ? RDATA_O_reg[31:0]   : 32'd0;

    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            x_i_4_3d[0]         <=  8'd0;
            x_i_4_3d[1]         <=  8'd0;
            x_i_4_3d[2]         <=  8'd0;

            x_i_3_2d[0]         <=  8'd0;
            x_i_3_2d[1]         <=  8'd0;

            x_i_2_1d            <=  8'd0;

            RDATA_O_i_4_3d[0]   <=  32'd0;
            RDATA_O_i_4_3d[1]   <=  32'd0;
            RDATA_O_i_4_3d[2]   <=  32'd0;

            RDATA_O_i_3_2d[0]   <=  32'd0;
            RDATA_O_i_3_2d[1]   <=  32'd0;

            RDATA_O_i_2_1d      <=  32'd0;

            stop_mac_4_3d[0]    <=  1'd0;
            stop_mac_4_3d[1]    <=  1'd0;
            stop_mac_4_3d[2]    <=  1'd0;

            stop_mac_3_2d[0]    <=  1'd0;
            stop_mac_3_2d[1]    <=  1'd0;

            stop_mac_2_1d       <=  1'd0;
        end else begin
            x_i_4_3d[0]         <=  x_i_4;
            x_i_4_3d[1]         <=  x_i_4_3d[0];
            x_i_4_3d[2]         <=  x_i_4_3d[1];

            x_i_3_2d[0]         <=  x_i_3;
            x_i_3_2d[1]         <=  x_i_3_2d[0];

            x_i_2_1d            <=  x_i_2;

            RDATA_O_i_4_3d[0]   <=  RDATA_O_i[3];
            RDATA_O_i_4_3d[1]   <=  RDATA_O_i_4_3d[0];
            RDATA_O_i_4_3d[2]   <=  RDATA_O_i_4_3d[1];

            RDATA_O_i_3_2d[0]   <=  RDATA_O_i[2];
            RDATA_O_i_3_2d[1]   <=  RDATA_O_i_3_2d[0];

            RDATA_O_i_2_1d      <=  RDATA_O_i[1];

            stop_mac_4_3d[0]    <=  stop_mac_pipe;
            stop_mac_4_3d[1]    <=  stop_mac_4_3d[0];
            stop_mac_4_3d[2]    <=  stop_mac_4_3d[1];

            stop_mac_3_2d[0]    <=  stop_mac_pipe;
            stop_mac_3_2d[1]    <=  stop_mac_3_2d[0];

            stop_mac_2_1d       <=  stop_mac_pipe;
        end
    end


//-----------------Column 1 start-------------------
    mac_4x1_col col1(
        .CLK(CLK),
        .RSTN(RSTN),
        .en_x_i(en_x_i),
        .en_w_i(en_w_i[3]),
        .stop_mac(stop_mac_pipe),
        .used_row(used_row_pipe),
        .before_sum_1(RDATA_O_i[0]),
        .before_sum_2(RDATA_O_i_2_1d),
        .before_sum_3(RDATA_O_i_3_2d[1]),
        .before_sum_4(RDATA_O_i_4_3d[2]),
        .x_i(x_i_1),
        .w_i(w_i_1),
        .after_sum_1(after_sum_1[0]),
        .after_sum_2(after_sum_1[1]),
        .after_sum_3(after_sum_1[2]),
        .after_sum_4(after_sum_1[3])
    );
//-----------------Column 1 end---------------------

//-----------------Column 2 start-------------------
    mac_4x1_col col2(
        .CLK(CLK),
        .RSTN(RSTN),
        .en_x_i(en_x_i),
        .en_w_i(en_w_i[2]),
        .stop_mac(stop_mac_2_1d),
        .used_row(used_row_pipe),
        .before_sum_1(after_sum_1[0]),
        .before_sum_2(after_sum_1[1]),
        .before_sum_3(after_sum_1[2]),
        .before_sum_4(after_sum_1[3]),
        .x_i(x_i_2_1d),
        .w_i(w_i_2),
        .after_sum_1(after_sum_2[0]),
        .after_sum_2(after_sum_2[1]),
        .after_sum_3(after_sum_2[2]),
        .after_sum_4(after_sum_2[3])
    );
//-----------------Column 2 end---------------------

//-----------------Column 3 start-------------------
    mac_4x1_col col3(
        .CLK(CLK),
        .RSTN(RSTN),
        .en_x_i(en_x_i),
        .en_w_i(en_w_i[1]),
        .stop_mac(stop_mac_3_2d[1]),
        .used_row(used_row_pipe),
        .before_sum_1(after_sum_2[0]),
        .before_sum_2(after_sum_2[1]),
        .before_sum_3(after_sum_2[2]),
        .before_sum_4(after_sum_2[3]),
        .x_i(x_i_3_2d[1]),
        .w_i(w_i_3),
        .after_sum_1(after_sum_3[0]),
        .after_sum_2(after_sum_3[1]),
        .after_sum_3(after_sum_3[2]),
        .after_sum_4(after_sum_3[3])
    );
//-----------------Column 3 end---------------------

//-----------------Column 4 start-------------------
    mac_4x1_col col4(
        .CLK(CLK),
        .RSTN(RSTN),
        .en_x_i(en_x_i),
        .en_w_i(en_w_i[0]),
        .stop_mac(stop_mac_4_3d[2]),
        .used_row(used_row_pipe),
        .before_sum_1(after_sum_3[0]),
        .before_sum_2(after_sum_3[1]),
        .before_sum_3(after_sum_3[2]),
        .before_sum_4(after_sum_3[3]),
        .x_i(x_i_4_3d[2]),
        .w_i(w_i_4),
        .after_sum_1(after_sum_4[0]),
        .after_sum_2(after_sum_4[1]),
        .after_sum_3(after_sum_4[2]),
        .after_sum_4(after_sum_4[3])
    );
//-----------------Column 4 end-------------------

//-----------------Output start-------------------
    // OUTPUT delay
    /*
        1행 3-cycle delay
        2행 2-cycle delay
        3행 1-cycle delay
        4행 0-cycle delay
    */
    reg signed  [31:0]  row_1_3d    [0:2];
    reg signed  [31:0]  row_2_2d    [0:1];
    reg signed  [31:0]  row_3_1d;

    reg signed  [31:0]  after_sum   [0:3];

    always @(*) begin
        case(en_w_i_reg)
            4'b1111 : begin
                after_sum[0] = after_sum_4[0];
                after_sum[1] = after_sum_4[1];
                after_sum[2] = after_sum_4[2];
                after_sum[3] = after_sum_4[3];
            end
            4'b1110 : begin
                after_sum[0] = after_sum_3[0];
                after_sum[1] = after_sum_3[1];
                after_sum[2] = after_sum_3[2];
                after_sum[3] = after_sum_3[3];
            end
            4'b1100 : begin
                after_sum[0] = after_sum_2[0];
                after_sum[1] = after_sum_2[1];
                after_sum[2] = after_sum_2[2];
                after_sum[3] = after_sum_2[3];
            end
            4'b1000 : begin
                after_sum[0] = after_sum_1[0];
                after_sum[1] = after_sum_1[1];
                after_sum[2] = after_sum_1[2];
                after_sum[3] = after_sum_1[3];
            end
            default : begin
                after_sum[0] = after_sum_4[0];
                after_sum[1] = after_sum_4[1];
                after_sum[2] = after_sum_4[2];
                after_sum[3] = after_sum_4[3];
            end
        endcase
    end

    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            row_1_3d[0] <=  32'd0;
            row_1_3d[1] <=  32'd0;
            row_1_3d[2] <=  32'd0;

            row_2_2d[0] <=  32'd0;
            row_2_2d[1] <=  32'd0;

            row_3_1d    <=  32'd0;
        end else begin
            row_1_3d[0] <=  after_sum[0];
            row_1_3d[1] <=  row_1_3d[0];
            row_1_3d[2] <=  row_1_3d[1];

            row_2_2d[0] <=  after_sum[1];
            row_2_2d[1] <=  row_2_2d[0];

            row_3_1d    <=  after_sum[2];
        end
    end
    assign  RESULT  =   {row_1_3d[2], row_2_2d[1], row_3_1d, after_sum[3]};
//------------------Output end------------------
endmodule