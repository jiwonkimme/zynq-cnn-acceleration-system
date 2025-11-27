module BRAM_TDP #(
    parameter BW = 32,      // 데이터 폭 (Output은 32비트 추천)
    parameter AW = 10,      // 주소 폭
    parameter ENTRY = 1024
)(
    input  wire           CLK,

    // [Port A: PL 연결] Read & Write (부분합 누적용)
    input  wire           WE_A,      // Write Enable (1=Write, 0=Read)
    input  wire           EN_A,      // Chip Enable
    input  wire [AW-1:0]  ADDR_A,
    input  wire [BW-1:0]  DIN_A,
    output reg  [BW-1:0]  DOUT_A,    // 읽은 데이터 (Partial Sum)

    // [Port B: PS 연결] Read Only (결과 회수용)
    input  wire           EN_B,      // Chip Enable
    input  wire [AW-1:0]  ADDR_B,
    output reg  [BW-1:0]  DOUT_B     // 최종 결과
);

    // BRAM 합성 유도 속성
    (* ram_style = "block" *)
    reg [BW-1:0] ram [0:ENTRY-1];

    // Port A Operation (Read / Write)
    always @(posedge CLK) begin
        if (EN_A) begin
            if (WE_A) begin
                ram[ADDR_A] <= DIN_A;  // 쓰기
            end
            DOUT_A <= ram[ADDR_A];     // 읽기 (Write-First or Read-First 모드에 따라 다름)
        end
    end

    // Port B Operation (Read Only)
    always @(posedge CLK) begin
        if (EN_B) begin
            DOUT_B <= ram[ADDR_B];     // 읽기
        end
    end

endmodule