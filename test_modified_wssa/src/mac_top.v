//////////////////////////////////////////////////////////////////////////////////
// Module Name:    mac_top
// Project Name:   Zynq CNN Acceleration System
// Description:    
//    - Top-level Controller for the Weight-Stationary Systolic Array.
//    - Implements FSM for loading weights, streaming inputs, and storing results.
//    - Handles address generation for 5x5 convolution windowing (via FSM states).
//    - Interfaces with external BRAMs (True Dual-Port for Output).
//
// Modifications for CNN Inference:
//    1. [Interface Update] Expanded Output Data Bus (WDATA_O, RDATA_O) to 128-bit 
//       to support high-precision 32-bit results from the array.
//    2. [Register Expansion] Updated internal result registers (wdata_o_reg, RESULT_reg) 
//       and initialization logic to 128-bit width.
//////////////////////////////////////////////////////////////////////////////////

module mac_top (
    input     wire              CLK,
    input     wire              RSTN,
    input     wire     [11:0]   MNT,
    input     wire              START,
    output    reg               DONE,

    output    wire              EN_I,
    output    wire    [2:0]     ADDR_I,
    input     wire    [63:0]    RDATA_I,
    output    wire              EN_W,
    output    wire    [2:0]     ADDR_W,
    input     wire    [63:0]    RDATA_W,
   
    output    wire              EN_O,
    output    wire              RW_O,
    output    wire    [3:0]     ADDR_O,
    output    wire    [127:0]   WDATA_O,
    input     wire    [127:0]   RDATA_O
);


    // WRITE YOUR CONTROL SYSTEM CODE
    // Weight 거꾸로 읽어야함.
    wire    [3:0]    M, N, T;

    assign  M       =   MNT [11:8];
    assign  N       =   MNT [7:4];
    assign  T       =   MNT [3:0];

    // 상태 정의
    reg             prev_START;

    reg     [3:0]   state, next_state;
    parameter IDLE      =   4'b0000;
    parameter STOP      =   4'b1111;        
    parameter READY     =   4'b0001;
    parameter LOAD_W    =   4'b0010;
    parameter LOAD_I    =   4'b0100;
    parameter STORE_O   =   4'b1000;
    
    reg     [1:0]   where_w_reg, where_i_reg;
    reg     [10:0]  clock_cycle;

    // 상태 전이
    always @(posedge CLK or negedge RSTN) begin
        if (!RSTN) begin
            state       <=  IDLE;
            prev_START  <=  1'b0;
            clock_cycle <=  11'd0 - 11'd2; // 실제 유효한 동작이 시작되는 시점을 0으로 맞추기 위한 오프셋(Offset) 보정
        end else begin
            state       <=  next_state;
            prev_START  <=  START;
            clock_cycle <=  clock_cycle + 11'd1;
        end
    end

    // 출력 로직
    reg         [2:0]   addr_w_reg;
    reg         [2:0]   addr_i_reg; 
    reg         [3:0]   addr_o_reg;

    reg                 en_i_reg, 
                        en_w_reg, 
                        en_o_reg,
                        rw_o_reg;

    reg         [127:0]  wdata_o_reg;
    
    reg         [3:0]   cycle_count;
    reg         [3:0]   store_count;

    reg signed  [127:0]  RESULT_reg;

    //M,N,T 값 가지고 CYCLE 몇번 돌건지 만들어야함!
    wire        [2:0]   stage;

    assign  stage   =   {(M>4'd4),(N>4'd4),(T>4'd4)};

    /*stage 0 | 3'b000 | M≤4, N≤4, T≤4일 때 1바퀴                           | (2,2)

            1 | 3'b001 | M≤4, N≤4, T>4일 때 1바퀴 + LOAD_I                  | (2,2), (3,2)

            2 | 3'b010 | M≤4, N>4, T≤4일 때 1바퀴 + LOAD_W                  | (2,2), (1,1)

            3 | 3'b011 | M≤4, N>4, T>4일 때 1바퀴 + LOAD_I                  | (2,2), (3,2), (2,1), (3,1) 
                                            LOAD_W + LOAD_I 

            4 | 3'b100 | M>4, N≤4, T≤4일 때 2바퀴 (LOAD_W)                  | (2,2), (2,3)

            5 | 3'b101 | M>4, N≤4, T>4일 때 1바퀴 + LOAD_I                  | (2,2), (3,2), (2,3), (3,3)
                                            LOAD_W + LOAD_I

            6 | 3'b110 | M>4, N>4, T≤4일 때 4바퀴 (LOAD_W)                  | (2,2), (2,3), (1,1), (1,4)
                                            
            7 | 3'b111 | M>4, N>4, T>4일 때 1바퀴 + LOAD_I                  | (2,2), (3,2), (2,3), (3,3), (1,1), (4,1), (1,4), (4,4)
                                            1바퀴 + LOAD_I
                                            1바퀴 + LOAD_I
                                            1바퀴 + LOAD_I
    */

    reg     [2:0]   load_w_times, load_i_times;
    reg             overwrite_sig;
    reg     [3:0]   compute_cycle;

    always @(*) begin
        if((N>=4)) begin
            if(where_w_reg==2'd0||where_w_reg==2'd3) begin
                compute_cycle   =   (N-4'd4) + 4'd5; 
            end else begin 
                compute_cycle   =   4'd9;
            end
        end else begin 
            compute_cycle       =   N + 4'd5;
        end
    end
    always @(*) begin
        case (state)
            IDLE: begin
                next_state      =   (START)                             ? READY     :   IDLE;
                DONE            =   1'b0;
            end
            STOP: begin
                next_state      =   IDLE;
                DONE            =   1'b1;
            end
            READY:  next_state  =   LOAD_W;          
            LOAD_W: next_state  =   (addr_w_reg[1:0]==2'b00)            ? LOAD_I    :   LOAD_W;
            LOAD_I: begin
                if((T >= compute_cycle)) begin
                    next_state  =   (cycle_count==compute_cycle+4'd1)   ? STORE_O   :   LOAD_I;
                end else begin 
                    next_state  =   (cycle_count==compute_cycle)        ? STORE_O   :   LOAD_I;
                end
            end
            STORE_O: begin 
                case(stage)
                    3'd0: begin
                        if(store_count==T) begin
                            next_state      =   STOP;
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd1: begin
                        if(store_count==T) begin
                            next_state      =   STOP;
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd2: begin
                        if(store_count==T) begin
                            if(load_w_times>=2'd2) begin
                                next_state      =   STOP;
                            end else begin
                                next_state      =   READY;
                            end
                        //---------------------------------------
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd3: begin //LOAD I -> W -> I 순
                        if(store_count==T) begin
                            if(load_w_times>=2'd2) begin
                                next_state  =   STOP;
                            end else begin
                                next_state  =   READY;
                            end 
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd4: begin
                        if(store_count==T) begin
                            if(load_w_times>=2'd2) begin
                                next_state  =   STOP;
                            end else begin
                                next_state  =   READY;
                            end
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd5: begin //LOAD I -> W -> I 순
                        if(store_count==T) begin
                            if(load_w_times>=2'd2) begin
                                next_state  =   STOP;
                            end else begin
                                next_state  =   READY;
                            end
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd6: begin //LOAD W 4번
                        if(store_count==T) begin
                            if(load_w_times == 2'd1) begin 
                                next_state  =   READY;
                            end else if(load_w_times == 2'd2) begin 
                                next_state  =   READY;
                            end else if(load_w_times == 2'd3) begin 
                                next_state  =   READY;
                            end else begin
                                next_state  =   STOP;
                            end
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    3'd7: begin //LOAD I-> W-> I-> W-> I-> W->I
                        if(store_count==T) begin
                            if(load_w_times==1) begin 
                                next_state  =   READY;
                            end else if(load_w_times==2) begin 
                                next_state  =   READY;
                            end else if(load_w_times==3) begin 
                                next_state  =   READY;
                            end else begin
                                next_state  =   STOP;
                            end
                        end else begin
                            next_state      =   STORE_O;
                        end
                    end
                    default:    begin
                        next_state  =   IDLE;
                    end
                endcase
            end            
            default:    begin
                next_state  =   IDLE;
            end
        endcase
    end


    reg     [2:0]   up_addr_reg, down_addr_reg;
    reg             save;
    reg             stop_mac_reg;
    reg             used_row_reg;


    always @(*) begin
        if((stage==3'd2)||(stage==3'd3)) begin
            overwrite_sig   =   (load_w_times>=3'd2);
        end else if((stage==3'd6)||(stage==3'd7)) begin
            overwrite_sig   =   (load_w_times>=3'd3);
        end else begin 
            overwrite_sig   =   1'b0;
        end
    end


    always @(posedge CLK or negedge RSTN) begin
        if (!RSTN) begin
            addr_i_reg      <=  3'd0;
            addr_w_reg      <=  3'd0;
            addr_o_reg      <=  4'd0;
            en_i_reg        <=  1'b0;
            en_w_reg        <=  1'b0;
            en_o_reg        <=  1'b0;
            rw_o_reg        <=  1'b0;
            wdata_o_reg     <=  128'd0;
            cycle_count     <=  4'd0;
            load_w_times    <=  2'd0;
            load_i_times    <=  2'd0;
            up_addr_reg     <=  3'b011;
            down_addr_reg   <=  3'b111;
            stop_mac_reg    <=  1'b0;
            used_row_reg    <=  1'b0;    
            where_w_reg     <=  2'd1;
            where_i_reg     <=  2'd1;      
            save            <=  1'b1;
        end else begin
            if(M>4) begin
                used_row_reg    <=  (addr_w_reg[1:0] <= M[1:0]-2'd1) ? 1'b1 : ~addr_w_reg[2];
            end else begin 
                used_row_reg    <=  (addr_w_reg[1:0] <= M[1:0]-2'd1) ? 1'b1 : 1'b0;
            end

            case (state)
                IDLE: begin
                    addr_i_reg      <=  3'd0;
                    addr_w_reg      <=  3'd0;
                    addr_o_reg      <=  4'd0;
                    en_i_reg        <=  1'b0;
                    en_w_reg        <=  1'b0;
                    en_o_reg        <=  1'b0;
                    rw_o_reg        <=  1'b0;
                    wdata_o_reg     <=  128'd0;
                    cycle_count     <=  4'd0;
                    store_count     <=  4'd0;
                    load_w_times    <=  2'd0;
                    load_i_times    <=  2'd0;
                    up_addr_reg     <=  3'b011;
                    down_addr_reg   <=  3'b111;
                    stop_mac_reg    <=  1'b0;
                    //used_row_reg    <=  1'b0;          
                    where_w_reg     <=  2'd1;
                    where_i_reg     <=  2'd1;
                    save            <=  1'b1;
                end
                READY: begin
                    addr_i_reg      <=  3'd0;
                    //weight는 가장 먼저 들어간 값이 가장 아랫값이니까 address 3 2 1 0 순으로
                    addr_w_reg      <=  3'b111;
                    addr_o_reg      <=  4'd0;
                    en_i_reg        <=  1'b0;
                    en_w_reg        <=  1'b0;
                    en_o_reg        <=  1'b0;
                    rw_o_reg        <=  1'b0;
                    wdata_o_reg     <=  128'd0;
                    cycle_count     <=  4'd0;
                    store_count     <=  4'd0;
                    load_w_times    <=  load_w_times + 2'd1;
                    load_i_times    <=  load_i_times;
                    up_addr_reg     <=  3'b011;
                    down_addr_reg   <=  3'b111;
                    stop_mac_reg    <=  stop_mac_reg;
                    save            <=  1'b1;
                end
                LOAD_W: begin
                    if(addr_w_reg[1:0]==2'b00) begin
                        en_w_reg            <=  1'b0;
                    end else begin
                        en_w_reg            <=  1'b1;
                        if(where_w_reg==2'd0 || where_w_reg==2'd1) begin
                            addr_w_reg      <=  up_addr_reg;
                            up_addr_reg     <=  up_addr_reg - 3'd1;
                        end else begin
                            addr_w_reg      <=  down_addr_reg;
                            down_addr_reg   <=  down_addr_reg - 3'd1;
                        end
                    end
                end
                LOAD_I: begin
                    if ((cycle_count == 4'd0)&&(T == 4'd1)) begin
                        stop_mac_reg    <=  1'b0;
                        en_i_reg        <=  1'b1;
                        cycle_count     <=  4'd1;
                        addr_i_reg      <=  3'd0;
                        //--------------------Read---------------------
                        en_o_reg        <=  overwrite_sig;
                        rw_o_reg        <=  1'b0; // Read Mode
                        addr_o_reg      <=  {3'd0,(where_w_reg==2'd2||where_w_reg==2'd3)};
                        //---------------------------------------------
                    end else if (cycle_count == 4'd0) begin
                        stop_mac_reg    <=  1'b0;
                        en_i_reg        <=  1'b1;
                        cycle_count     <=  4'd1;
                        addr_i_reg      <=  3'd0;
                        //--------------------Read---------------------
                        en_o_reg        <=  overwrite_sig;
                        rw_o_reg        <=  1'b0; // Read Mode
                        addr_o_reg      <=  {3'd0,(where_w_reg==2'd2||where_w_reg==2'd3)};
                        //---------------------------------------------
                    end else if (cycle_count<(T-4'd1)) begin 
                        addr_i_reg      <=  addr_i_reg + 3'd1;
                        cycle_count     <=  cycle_count + 4'd1;
                        addr_o_reg      <=  addr_o_reg  +4'd2;
                    end else if (cycle_count==(T-4'd1)) begin
                        addr_i_reg      <=  addr_i_reg + 3'd1;
                        cycle_count     <=  cycle_count + 4'd1;
                        addr_o_reg      <=  addr_o_reg  +4'd2;
                    end else if (cycle_count==T) begin
                        stop_mac_reg    <=  1'b1;
                        en_i_reg        <=  1'b0;
                        addr_i_reg      <=  3'd0;
                        cycle_count     <=  cycle_count + 4'd1;
                        en_o_reg        <=  1'b0;
                        addr_o_reg      <=  {3'd0,(where_w_reg==2'd2||where_w_reg==2'd3)};
                    end else if (cycle_count==compute_cycle) begin
                        load_i_times    <=  load_i_times + 2'd1;
                        stop_mac_reg    <=  1'b1;
                        en_i_reg        <=  1'b0;
                        addr_i_reg      <=  3'd0;
                        cycle_count     <=  4'd0;              
                    end else begin
                        cycle_count     <=  cycle_count + 4'd1;
                    end
                end
                STORE_O: begin
                    case(stage)
                        3'd0: begin
                            if(store_count==T) begin
                                where_i_reg     <=   2'd1;
                                where_w_reg     <=   2'd1;
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd1: begin
                            if(store_count==T) begin
                                where_i_reg     <=   2'd1;
                                where_w_reg     <=   2'd1;
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd2: begin
                            if(store_count==T) begin
                                if(load_w_times>=2'd2) begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end else begin
                                    where_w_reg     <=   2'd0;
                                    where_i_reg     <=   2'd0;
                                end
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd3: begin //LOAD I -> W -> I 순
                            if(store_count==T) begin
                                if(load_w_times>=2'd2) begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end else begin
                                    where_w_reg     <=   2'd0;
                                    where_i_reg     <=   2'd0;
                                end 
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd4: begin
                            if(store_count==T) begin
                                if(load_w_times>=2'd2) begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end else begin
                                    where_w_reg     <=   2'd2;
                                    where_i_reg     <=   2'd1;
                                end
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd5: begin //LOAD I -> W -> I 순
                            if(store_count==T) begin
                                if(load_w_times>=2'd1) begin
                                    where_w_reg     <=   2'd2;
                                    where_i_reg     <=   2'd2;
                                end else begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd6: begin //LOAD W 4번
                            if(store_count==T) begin
                                if(load_w_times == 2'd1) begin 
                                    where_w_reg     <=   2'd2;
                                    where_i_reg     <=   2'd1;
                                end else if(load_w_times == 2'd2) begin 
                                    where_w_reg     <=   2'd0;
                                    where_i_reg     <=   2'd0;
                                end else if(load_w_times == 2'd3) begin 
                                    where_w_reg     <=   2'd3;
                                    where_i_reg     <=   2'd0;
                                end else begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        3'd7: begin //LOAD I-> W-> I-> W-> I-> W->I
                            if(store_count==T) begin
                                if(load_w_times==1) begin 
                                    where_w_reg     <=   2'd2;
                                    where_i_reg     <=   2'd1;
                                end else if(load_w_times==2) begin 
                                    where_w_reg     <=   2'd0;
                                    where_i_reg     <=   2'd0;
                                end else if(load_w_times==3) begin 
                                    where_w_reg     <=   2'd3;
                                    where_i_reg     <=   2'd0;
                                end else begin
                                    where_w_reg     <=   2'd1;
                                    where_i_reg     <=   2'd1;
                                end
                            end else begin
                                where_w_reg     <=   where_w_reg;
                                where_i_reg     <=   where_i_reg;
                            end
                        end
                        default:    begin
                            where_w_reg     <=   2'd1;
                            where_i_reg     <=   2'd1;
                        end
                    endcase
                    
                    if(store_count==4'd0) begin
                        en_o_reg    <=  1'b1;
                        rw_o_reg    <=  1'b1; // Write Mode
                        wdata_o_reg <=  RESULT_reg;
                        addr_o_reg  <=  {3'd0,(where_w_reg==2'd2||where_w_reg==2'd3)};
                        store_count <=  4'd1;
                    end else if(store_count < T) begin
                        addr_o_reg  <=  addr_o_reg + 4'd2;
                        store_count <=  store_count + 4'd1;
                        wdata_o_reg <=  RESULT_reg;
                    end else if(store_count == T) begin
                        en_o_reg    <=  1'b0;
                        rw_o_reg    <=  1'b0; // Read Mode (덮어쓰는 일 없게)
                        // addr_o_reg  <=  addr_o_reg + 4'd2;
                        addr_o_reg  <=  4'd0;
                        store_count <=  4'd0;
                        wdata_o_reg <=  RESULT_reg;
                    end else begin
                        store_count <=  4'd0;
                        en_o_reg    <=  1'b0;
                        rw_o_reg    <=  1'b0; // Read Mode (덮어쓰는 일 없게)
                    end
                end

                STOP: begin
                    case(stage)
                        3'd0, 3'd2: begin 
                            // T 1 & 2 all
                            if(save) begin
                                en_o_reg    <=  1'b1;
                                wdata_o_reg <=  128'd0;
                                rw_o_reg    <=  1'b1;
                                addr_o_reg  <=  T * 4'd2;
                                save        <=  1'b0;
                            end else if(addr_o_reg == 4'd14)begin
                                addr_o_reg  <=  4'd1;
                            end else if(addr_o_reg == 4'd15)begin 
                                en_o_reg    <=  1'b0;
                            end else begin 
                                addr_o_reg  <=  addr_o_reg  +   4'd2;
                            end
                        end
                        3'd1, 3'd3: begin 
                            // T 1 & 2 all
                            if(T<4'd8) begin
                                if(save) begin
                                    en_o_reg    <=  1'b1;
                                    wdata_o_reg <=  128'd0;
                                    rw_o_reg    <=  1'b1;
                                    addr_o_reg  <=  T * 4'd2;
                                    save        <=  1'b0;
                                end else if(addr_o_reg == 4'd14)begin
                                    addr_o_reg  <=  4'd1;
                                end else if(addr_o_reg == 4'd15)begin 
                                    en_o_reg    <=  1'b0;
                                end else begin 
                                    addr_o_reg  <=  addr_o_reg  +   4'd2;
                                end
                            end else begin
                                if(save) begin
                                    en_o_reg    <=  1'b1;
                                    wdata_o_reg <=  128'd0;
                                    rw_o_reg    <=  1'b1;
                                    addr_o_reg  <=  4'd1;
                                    save        <=  1'b0;
                                end else if(addr_o_reg == 4'd15)begin 
                                    en_o_reg    <=  1'b0;
                                end else begin 
                                    addr_o_reg  <=  addr_o_reg  +   4'd2;
                                end
                            end
                        end

                        3'd4, 3'd6: begin
                            // T 1 & 2
                            if(save) begin
                                en_o_reg    <=  1'b1;
                                rw_o_reg    <=  1'b1;
                                wdata_o_reg <=  128'd0;
                                addr_o_reg  <=  T * 4'd2;
                                save        <=  1'b0;
                            end else if(addr_o_reg == 4'd14)begin
                                addr_o_reg  <=  4'd2*T + 4'd1;
                            end else if(addr_o_reg == 4'd15)begin 
                                en_o_reg    <=  1'b0;
                            end else begin 
                                addr_o_reg  <=  addr_o_reg  +   4'd2;
                            end
                        end
                        3'd5, 3'd7: begin
                            // T 1 & 2
                            if(T<4'd8) begin
                                if(save) begin
                                    en_o_reg    <=  1'b1;
                                    rw_o_reg    <=  1'b1;
                                    wdata_o_reg <=  128'd0;
                                    addr_o_reg  <=  T * 4'd2;
                                    save        <=  1'b0;
                                end else if(addr_o_reg == 4'd14)begin
                                    addr_o_reg  <=  4'd2 * T + 4'd1;
                                end else if(addr_o_reg == 4'd15)begin 
                                    en_o_reg    <=  1'b0;
                                end else begin 
                                    addr_o_reg  <=  addr_o_reg  +   4'd2;
                                end
                            end else begin 
                                en_o_reg    <=  1'b0;
                                rw_o_reg    <=  1'b0;
                                addr_o_reg  <=  4'd0;
                            end
                        end
                        default: begin
                            en_o_reg    <=  1'b0;
                            rw_o_reg    <=  1'b0;
                            addr_o_reg  <=  4'd0;
                        end
                    endcase
                end
                default : begin
                    addr_i_reg      <=  3'd0;
                    addr_w_reg      <=  3'd0;
                    addr_o_reg      <=  4'd0;
                    en_i_reg        <=  1'b0;
                    en_w_reg        <=  1'b0;
                    en_o_reg        <=  1'b0;
                    rw_o_reg        <=  1'b0;
                    wdata_o_reg     <=  128'd0;
                    cycle_count     <=  4'd0;
                    load_w_times    <=  2'd0;
                    load_i_times    <=  2'd0;
                    up_addr_reg     <=  3'b011;
                    down_addr_reg   <=  3'b111;
                    stop_mac_reg    <=  1'b0;
                    used_row_reg    <=  1'b0;    
                    where_w_reg     <=  2'd1;
                    where_i_reg     <=  2'd1;      
                    save            <=  1'b1;
                end
            endcase 
        end
    end

    reg [127:0] WDATA_O_reg;
    
    // Output Assignments
    assign  EN_I    =   en_i_reg;
    assign  ADDR_I  =   addr_i_reg;
    assign  EN_W    =   en_w_reg;
    assign  ADDR_W  =   addr_w_reg;
    assign  EN_O    =   en_o_reg;
    assign  RW_O    =   rw_o_reg;
    assign  ADDR_O  =   addr_o_reg;
    assign  WDATA_O =   WDATA_O_reg;

    always @(*) begin
        if(state==STOP) begin
            WDATA_O_reg =   128'd0;
        end else begin
            WDATA_O_reg =   ((T >= compute_cycle)) ? wdata_o_reg : RESULT_reg;
        end
    end
    //--------------------------------------
   
    //------------------INPUT---------------
    // EN_I & EN_W -> 1 cycle + 2ns
    reg     [63:0]  I;
    wire    [31:0]  x_i;
    wire    [31:0]  upper_I, lower_I;

    always @(*) begin
        case (N)
            4'd1: I =   {RDATA_I[63:56], {56{1'b0}}};
            4'd2: I =   {RDATA_I[63:48], {48{1'b0}}};
            4'd3: I =   {RDATA_I[63:40], {40{1'b0}}};
            4'd4: I =   {RDATA_I[63:32], {32{1'b0}}};
            4'd5: I =   {RDATA_I[63:24], {24{1'b0}}};
            4'd6: I =   {RDATA_I[63:16], {16{1'b0}}};
            4'd7: I =   {RDATA_I[63:8],  {8{1'b0}}};
            4'd8: I =   RDATA_I;
            default: I = 64'd0; // Handles invalid N
        endcase
    end

    assign  upper_I =   I[63:32];
    assign  lower_I =   I[31:0];

    assign  x_i     =   (where_i_reg==2'd1 || where_i_reg==2'd2) ? upper_I : lower_I;
    // 4<=T<8의 경우, 사용하지 않는 행의 input은 32'd0; 
    //--------------------------------------
    
    //-----------------WEIGHT----------------
    reg     [63:0]  W;
    wire    [31:0]  w_i;
    wire    [31:0]  upper_W, lower_W;

    always @(*) begin
        case (N)
            4'd1: W =   {RDATA_W[63:56], {56{1'b0}}};
            4'd2: W =   {RDATA_W[63:48], {48{1'b0}}};
            4'd3: W =   {RDATA_W[63:40], {40{1'b0}}};
            4'd4: W =   {RDATA_W[63:32], {32{1'b0}}};
            4'd5: W =   {RDATA_W[63:24], {24{1'b0}}};
            4'd6: W =   {RDATA_W[63:16], {16{1'b0}}};
            4'd7: W =   {RDATA_W[63:8],  {8{1'b0}}};
            4'd8: W =   RDATA_W;
            default: W = 64'd0; // Handles invalid N
        endcase
    end

    assign  upper_W =   W[63:32];
    assign  lower_W =   W[31:0];

    assign  w_i     =   (where_w_reg==2'd1 || where_w_reg==2'd2) ? upper_W : lower_W;
    // 4<=M<8의 경우, 사용하지 않는 행의 weight는 32'd0; 

    //--------------------------------------

    //-------------INSTANTIATION------------
    wire    stop_mac;
    assign  stop_mac    =   stop_mac_reg;

    reg     [3:0]   en_col;
    wire    [3:0]   shift;
    assign  shift =  (where_w_reg==2'd0||where_w_reg==2'd3) ? (4'd8 - N) : 4'd0;
    always @(*) begin
        if(EN_W) begin
            if(N>4) begin 
                en_col  =   4'b1111 << shift;
            end else begin
                en_col  =   4'b1111 << (4'd4 - N);
            end
        end else begin
            en_col = 4'd0;
        end
    end

    reg             en_x_i_2d [0:1];
    reg     [3:0]   en_w_i_2d [0:1];

    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            en_x_i_2d[0] <=  0;
            en_x_i_2d[1] <=  0;

            en_w_i_2d[0] <=  0;
            en_w_i_2d[1] <=  0;
        end else begin
            en_x_i_2d[0] <=  EN_I;
            en_x_i_2d[1] <=  en_x_i_2d[0];

            en_w_i_2d[0] <=  en_col;
            en_w_i_2d[1] <=  en_w_i_2d[0];
        end
    end

    wire [127:0] RESULT;
    wire         used_row;
    assign used_row =   used_row_reg;

    // WRITE YOUR MAC_ARRAY DATAPATH CODE
    mac_4x4_array MAC_array(
        .CLK(CLK),
        .RSTN(RSTN),
        .stop_mac(stop_mac),
        .used_row(used_row),
        .overwrite_sig(overwrite_sig),
        .RDATA_O(RDATA_O),
        .en_x_i(en_x_i_2d[1]),
        .en_w_i(en_w_i_2d[1]),
        .x_i(x_i),
        .w_i(w_i),
        .RESULT(RESULT)
    );
    //--------------------------------------
    //-----------------OUTPUT---------------
    always @(posedge CLK or negedge RSTN) begin
        if(!RSTN) begin
            RESULT_reg  <=  128'd0;
        end else begin
            RESULT_reg  <=  RESULT;
        end
    end
    //--------------------------------------
endmodule