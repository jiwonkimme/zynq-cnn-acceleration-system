import numpy as np

def generate_golden_hex(filename="golden_result.hex"):
    print("[-] Generating Golden Model with Logic: if(cnt<23) +1 else +5 ...")

    # ==========================================
    # 1. Weight Matrix Generation (4x5)
    # ==========================================
    # Verilog Input: {0, 1, 2, 3, 4} (Visual Order)
    # Python Map   : [0, 1, 2, 3, 4] (Col 0..4)
    # Logic: Val = Row + Col
    weights = []
    for r in range(4): 
        w_row = [(r + c) for c in range(5)] 
        weights.append(w_row)
    
    W = np.array(weights) # Shape: (4, 5)

    # ==========================================
    # 2. Input Matrix Generation (5x24)
    # ==========================================
    # Logic Mirroring Verilog:
    #   if (cnt < 23): val += 1, cnt++
    #   else:          val += 5, cnt=0
    
    inputs = []
    
    # Initial Value (at t=0): [0, 1, 2, 3, 4]
    current_col = [0, 1, 2, 3, 4] 
    cnt = 0
    
    # Generate 24 cycles (Time 0 to 23)
    for t in range(120):
        # 1. Store current input (for this cycle)
        inputs.append(current_col[:])
        
        # 2. Update logic for NEXT cycle (Same as Verilog)
        if cnt < 23:
            # Normal Increment (+1)
            current_col = [x + 1 for x in current_col]
            cnt += 1
        else:
            # Jump Increment (+5) - This prepares data for t=24
            current_col = [x + 5 for x in current_col]
            cnt = 0
        
    I = np.array(inputs).T # Transpose to (5, 24)

    # ==========================================
    # 3. Compute & Save
    # ==========================================
    Result = np.dot(W, I)
    
    # ------------------------------------------
    # Debug Print
    # ------------------------------------------
    print("\n[1] Weight Matrix (Straight)")
    print(W)
    print(I)
    #print("\n[2] Input Matrix (First 5 Cols)")
    #print(I[:, :5])
    #print("\n[2-1] Input Matrix (Last 5 Cols - Checking Continuity)")
    #print(I[:, -5:])
    
    # ------------------------------------------
    # Save to Hex
    # ------------------------------------------
    with open(filename, "w") as f:
        for c in range(120):
            # Pack 4 rows: R3(MSB)...R0(LSB)
            val_r0 = Result[0][c] & 0xFFFFFFFF
            val_r1 = Result[1][c] & 0xFFFFFFFF
            val_r2 = Result[2][c] & 0xFFFFFFFF
            val_r3 = Result[3][c] & 0xFFFFFFFF
            
            line = f"{val_r0:08X}{val_r1:08X}{val_r2:08X}{val_r3:08X}"
            f.write(line + "\n")
            
    print(f"\n[-] Saved '{filename}'.")

if __name__ == "__main__":
    generate_golden_hex()