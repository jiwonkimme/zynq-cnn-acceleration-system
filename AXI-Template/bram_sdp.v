/*
// Simple Dual-Port BRAM Module for Input/Weight Storage
// - Port A: Write Only     (for external connection,  Data width 32-bit, Depth 16)
// - Port B: Read Only      (for internal connection, Data width 64-bit, Depth 8)

input_sdpram your_instance_name (
  .clka(clka),    // input wire clka
  .ena(ena),      // input wire ena
  .wea(wea),      // input wire [0 : 0] wea
  .addra(addra),  // input wire [3 : 0] addra
  .dina(dina),    // input wire [31 : 0] dina
  .clkb(clkb),    // input wire clkb
  .enb(enb),      // input wire enb
  .addrb(addrb),  // input wire [2 : 0] addrb
  .doutb(doutb)  // output wire [63 : 0] doutb
);
*/

module bram_sdp #(
    parameter BW = 64,      // 데이터 폭 (기존 8 -> 32 확장 권장)
    parameter AW = 3,      // 주소 폭
    parameter ENTRY = 8    // 엔트리 수
)(
    input  wire           CLK,
    
    // [Port A: 쓰기 전용 - 외부(PS/AXI)에서 연결]
    input  wire           WE_A,      // Write Enable (Active High로 변경 추천)
    input  wire [AW-1:0]  ADDR_A,
    input  wire [BW-1:0]  DIN_A,
    
    // [Port B: 읽기 전용 - WSSA 내부에서 연결]
    input  wire           EN_B,      // Read Enable
    input  wire [AW-1:0]  ADDR_B,
    output reg  [BW-1:0]  DOUT_B
);

    (* ram_style = "block" *)
    reg [BW-1:0] ram [0:ENTRY-1];

    // Port A: Write Operation
    always @(posedge CLK) begin
        if (WE_A) begin
            ram[ADDR_A] <= DIN_A;
        end
    end

    // Port B: Read Operation
    always @(posedge CLK) begin
        if (EN_B) begin
            DOUT_B <= ram[ADDR_B];
        end
    end

endmodule