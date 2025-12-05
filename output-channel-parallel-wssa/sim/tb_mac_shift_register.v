module tb_mac_shift_register();
    reg             clk;
    reg             rstn;
    reg             i_run;
    reg     [7:0]   i_input_0;
    reg     [7:0]   i_input_1;
    reg     [7:0]   i_input_2;
    reg     [7:0]   i_input_3;
    reg     [7:0]   i_input_4;  
    wire    [39:0]  o_mac_input;
    wire            o_input_load_done;

    mac_shift_register u_mac_shift_register (
        .clk            (clk),
        .rstn           (rstn),
        .i_run          (i_run),
        .i_input_0      (i_input_0),
        .i_input_1      (i_input_1),
        .i_input_2      (i_input_2),
        .i_input_3      (i_input_3),
        .i_input_4      (i_input_4),
        .o_mac_input    (o_mac_input),
        .o_input_load_done  (o_input_load_done)
    );

    // Clock Generation
    always #5 clk = ~clk;

    integer cnt;

    initial begin
        $dumpfile("tb_mac_shift_register.vcd");
        $dumpvars(0, tb_mac_shift_register);

        clk = 1;
        rstn = 0;
        i_run = 0;
        i_input_0 = 8'd0;
        i_input_1 = 8'd1;
        i_input_2 = 8'd2;
        i_input_3 = 8'd3;
        i_input_4 = 8'd4;

        #10;
        rstn = 1;
        @(negedge clk);
        i_run = 1;

        // Provide input data

        // 초기화
        cnt = 0;
        // i_input_0 = 0; // 초기값 설정 가정
        #10;
        repeat (25) begin
            #10;
            
            if (cnt < 4) begin
                // 0->1->2->3->4 구간: 1씩 증가
                i_input_0 = i_input_0 + 8'd1;
                i_input_1 = i_input_1 + 8'd1;
                i_input_2 = i_input_2 + 8'd1;
                i_input_3 = i_input_3 + 8'd1;
                i_input_4 = i_input_4 + 8'd1;
                cnt = cnt + 1;
            end else begin
                // 4->28 구간: 24 증가 (점프)
                i_input_0 = i_input_0 + 8'd24; 
                i_input_1 = i_input_1 + 8'd24;
                i_input_2 = i_input_2 + 8'd24;
                i_input_3 = i_input_3 + 8'd24;
                i_input_4 = i_input_4 + 8'd24;
                cnt = 0; // 카운터 리셋
            end
            if(o_input_load_done) begin
                $display("Input Load Done at time %t", $time);
                #10;
                i_run = 0;
            end
        end
        #100;
        $finish;
    end
endmodule