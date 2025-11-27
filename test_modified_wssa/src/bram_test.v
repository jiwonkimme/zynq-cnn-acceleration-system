// Simulation Model for Single Port BRAM
module bram_test #(
    parameter BW = 64,          // Data Bit Width
    parameter AW = 3,           // Address Width
    parameter ENTRY = 8,        // Memory Depth
    parameter WRITE = 0,        // 1: Load Initial File, 0: No Init
    parameter MEM_FILE = "mem.hex"
) (
    input  wire             CLK,
    input  wire             CSN,    // Chip Select (Active Low) -> Enable
    input  wire [AW-1:0]    A,      // Address
    input  wire             WEN,    // Write Enable (1: Write, 0: Read)
    input  wire [BW-1:0]    DI,     // Data Input
    output wire [BW-1:0]    DOUT    // Data Output
);
    parameter    ATIME    = 2;  // Access Time (for delay modeling, if needed)

    // BRAM Modeling
    reg [BW-1:0] ram [0:ENTRY-1];
    reg [BW-1:0] outline;

    // Optional: Load Initial Memory Content
    initial begin
        if (WRITE > 0) begin
            $readmemh(MEM_FILE, ram);
        end
    end

    // Synchronous Read/Write Operation (1 Cycle Latency)
    always @ (posedge CLK)
    begin
        if (~CSN)
        begin
            if (WEN)    outline    <= ram[A];
            else        ram[A]    <= DI;
        end
    end

    // Output Assignment
    assign    #(ATIME)    DOUT    = outline;
    //assign        DOUT    = outline;

endmodule