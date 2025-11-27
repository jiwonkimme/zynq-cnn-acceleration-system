/*******************************************************************************
    tb_mac_top.v (Simulation Testbench)
    
    Target Tool: Icarus Verilog + GTKWave
    Description: 
        - Instantiates 'mac_top' (DUT) and 'bram_test' modules.
        - Loads input/weight data from hex files.
        - Verifies 128-bit output results against golden vectors.
        - Handles 8 test cases (M, N, T variations).
*******************************************************************************/
module tb_mac_top;

    // Simulation Parameters
    parameter PERIOD  = 10.0;
    parameter HPERIOD = PERIOD / 2.0;

    // DUT Signals
    reg             CLK;
    reg             RSTN;
    reg     [11:0]  MNT;
    reg             START;
    wire            DONE;

    // Input Memory Interface
    wire            EN_I;
    wire    [2:0]   ADDR_I;
    wire    [63:0]  RDATA_I;

    // Weight Memory Interface
    wire            EN_W;
    wire    [2:0]   ADDR_W;
    wire    [63:0]  RDATA_W;

    // Output Memory Interface (128-bit)
    wire            dut_EN_O;
    wire            dut_RW_O;       // 1: Write, 0: Read
    wire    [3:0]   dut_ADDR_O;
    wire    [127:0] dut_WDATA_O;
    wire    [127:0] RDATA_O;

    // Testbench Control for Output Memory
    reg             tb_clear_mode;  // 1: TB Control, 0: DUT Control
    reg             tb_EN_O;
    reg             tb_RW_O;
    reg     [3:0]   tb_ADDR_O;
    reg     [127:0] tb_WDATA_O;

    // Muxed Signals for Output Memory
    wire            mux_EN_O;
    wire            mux_RW_O;       // 1: Write, 0: Read (High Active Write assumed for BRAM)
    wire    [3:0]   mux_ADDR_O;
    wire    [127:0] mux_WDATA_O;

    // Test Vectors
    reg     [11:0]  mnt_vectors[0:7];
    reg     [127:0] golden_mem [0:15];
    reg             test_failed;
    integer         i, j;

    // Output File Handle
    integer         f_out;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    mac_top u_dut (
        .CLK        (CLK),
        .RSTN       (RSTN),
        .MNT        (MNT),
        .START      (START),
        .DONE       (DONE),
        
        .EN_I       (EN_I),
        .ADDR_I     (ADDR_I),
        .RDATA_I    (RDATA_I),
        
        .EN_W       (EN_W),
        .ADDR_W     (ADDR_W),
        .RDATA_W    (RDATA_W),
        
        .EN_O       (dut_EN_O),
        .RW_O       (dut_RW_O),
        .ADDR_O     (dut_ADDR_O),
        .WDATA_O    (dut_WDATA_O),
        .RDATA_O    (RDATA_O)
    );

    // =========================================================================
    // Memory Instantiations (Using bram_test.v)
    // =========================================================================

    // 1. Input Memory (Read Only for DUT)
    //    - WRITE=1: Load initial file
    //    - WEN=0: Always Read mode
    bram_test #(
        .BW(64), .AW(3), .ENTRY(8), 
        .WRITE(1), .MEM_FILE("./matrix-hex/input.hex")
    ) INPUT_MEM (
        .CLK    (CLK),
        .CSN    (~EN_I),        // Active Low Chip Select
        .A      (ADDR_I),
        .WEN    (1'b1),         // Read
        .DI     (64'd0),
        .DOUT   (RDATA_I)
    );

    // 2. Weight Memory (Read Only for DUT)
    bram_test #(
        .BW(64), .AW(3), .ENTRY(8), 
        .WRITE(1), .MEM_FILE("./matrix-hex/weight_transpose.hex")
    ) WEIGHT_MEM (
        .CLK    (CLK),
        .CSN    (~EN_W),        // Active Low Chip Select
        .A      (ADDR_W),
        .WEN    (1'b1),         // Read
        .DI     (64'd0),
        .DOUT   (RDATA_W)
    );


    // Note: Assuming 'bram_test' uses High-Active WEN (if WEN=1 then Write)
    // If DUT outputs 'dut_RW_O' where 1=Write, 0=Read, direct connection works.
    bram_test #(
        .BW(128), .AW(4), .ENTRY(16), 
        .WRITE(0), .MEM_FILE("") // No init file, cleared by TB
    ) OUT_MEM (
        .CLK    (CLK),
        .CSN    (~mux_EN_O),    // Active Low Chip Select
        .A      (mux_ADDR_O),
        .WEN    (~mux_RW_O),     // 1: Write, 0: Read
        .DI     (mux_WDATA_O),
        .DOUT   (RDATA_O)
    );

    // 3. Output Memory (Read/Write)
    //    - Mux Logic to allow TB to clear memory
    assign mux_EN_O    = (tb_clear_mode) ? tb_EN_O    : dut_EN_O;
    assign mux_RW_O    = (tb_clear_mode) ? tb_RW_O    : dut_RW_O;
    assign mux_ADDR_O  = (tb_clear_mode) ? tb_ADDR_O  : dut_ADDR_O;
    assign mux_WDATA_O = (tb_clear_mode) ? tb_WDATA_O : dut_WDATA_O;

    // =========================================================================
    // Simulation Tasks & Clock
    // =========================================================================


    // Task: Clear Output Memory
    task clear_out_mem;
        integer k;
        begin
            $display("[INFO] Clearing OUT_MEM to '0'...");
            tb_clear_mode = 1'b1; // Take control

            for (k = 0; k < 16; k = k + 1) begin
                @(posedge CLK);
                tb_EN_O    <= 1'b1;     // Enable
                tb_RW_O    <= 1'b1;     // Write
                tb_ADDR_O  <= k;
                tb_WDATA_O <= 128'dx;   // Clear Data
            end
            @(posedge CLK);
            tb_EN_O    <= 1'b0;
            tb_RW_O    <= 1'b0;
            @(posedge CLK);
            tb_clear_mode = 1'b0; // Release control
        end
    endtask

    // Task: Write Output Memory to File
    task dump_output_mem;
        input [31:0] case_idx;
        integer k;
        begin
            f_out = $fopen("./matrix-hex/output.hex", "a"); // Append mode
            if (f_out) begin
                $fwrite(f_out, "// Test Case %0d Output\n", case_idx);
                for (k = 0; k < 16; k = k + 1) begin
                    // Write 128-bit value in hex format
                    $fwrite(f_out, "%032x\n", OUT_MEM.ram[k]);
                end
                $fwrite(f_out, "\n");
                $fclose(f_out);
                $display("[INFO] Output dumped to output.hex for Case %0d", case_idx);
            end else begin
                $display("[ERROR] Failed to open output.hex");
            end
        end
    endtask

    // Clock Generation
    initial CLK = 0;
    always #(HPERIOD) CLK = ~CLK;

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // GTKWave Dump Setup
        $dumpfile("tb_mac_top.vcd");
        $dumpvars(0, tb_mac_top);
        // Dump array signals explicitly if needed (GTKWave might need help)
        // $dumpvars(0, u_dut.MAC_array); 

        // Clear existing output file
        f_out = $fopen("./matrix-hex/output.hex", "w");
        if (f_out) $fclose(f_out);

        // Initialize Vectors
        mnt_vectors[0] = 12'h444;
        mnt_vectors[1] = 12'h337;
        mnt_vectors[2] = 12'h374;
        mnt_vectors[3] = 12'h376;
        mnt_vectors[4] = 12'h634;
        mnt_vectors[5] = 12'h738;
        mnt_vectors[6] = 12'h583;
        mnt_vectors[7] = 12'h555;

        // Initialize Signals
        tb_clear_mode = 0;
        START = 0;
        MNT   = 0;
        RSTN  = 0;
        // tb_EN_O = 0; tb_RW_O = 0; tb_ADDR_O = 0; tb_WDATA_O = 0;

        // Apply Reset
        #(10*PERIOD);
        RSTN = 1;
        #(2*PERIOD);

        $display("========================================");
        $display("   WSSA Simulation Started (Icarus)     ");
        $display("========================================");

        // Loop through 8 Test Cases
        for (i = 0; i < 8; i = i + 1) begin
            $display("\n[RUNNING] Case %0d (MNT = %h)", i, mnt_vectors[i]);
            test_failed = 1'b0;

            // 1. Clear Memory
            clear_out_mem();
            #(PERIOD);

            // 2. Start DUT
            MNT   <= mnt_vectors[i];

            START <= 1'b1;
            #(PERIOD);
            START <= 1'b0;

            // 3. Wait for DONE
            @(posedge DONE);
            $display("[INFO] Case %0d DONE. Verifying results...", i);
            //#(2*PERIOD); // Safety margin

            // 3.5 결과 파일 저장
            dump_output_mem(i);

            // 4. Load Golden Data
            case (i)
                0: $readmemh("./matrix-hex/golden_case_0.hex", golden_mem);
                1: $readmemh("./matrix-hex/golden_case_1.hex", golden_mem);
                2: $readmemh("./matrix-hex/golden_case_2.hex", golden_mem);
                3: $readmemh("./matrix-hex/golden_case_3.hex", golden_mem);
                4: $readmemh("./matrix-hex/golden_case_4.hex", golden_mem);
                5: $readmemh("./matrix-hex/golden_case_5.hex", golden_mem);
                6: $readmemh("./matrix-hex/golden_case_6.hex", golden_mem);
                7: $readmemh("./matrix-hex/golden_case_7.hex", golden_mem);
            endcase

            // 5. Compare Results
            // Access internal RAM of bram_test instance 'OUT_MEM'
            for (j = 0; j < 16; j = j + 1) begin
                if (OUT_MEM.ram[j] !== golden_mem[j]) begin
                    $display("[ERROR] Mismatch at Addr %0d", j);
                    $display("    Expected: %h", golden_mem[j]);
                    $display("    Actual  : %h", OUT_MEM.ram[j]);
                    test_failed = 1;
                end
            end

            if (test_failed) begin
                $display("------------------------------------");
                $display("[FAILED] Case %0d failed. Stopping simulation.", i);
                $display("------------------------------------");
                $finish(2);
            end else begin
                $display("[PASSED] Case %0d passed.", i);
            end
            
            #(2*PERIOD);
        end

        $display("\n========================================");
        $display("   [SUCCESS] All Test Cases Passed!     ");
        $display("========================================");
        $finish;
    end

endmodule