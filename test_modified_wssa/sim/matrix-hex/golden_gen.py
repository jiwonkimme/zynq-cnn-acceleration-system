import numpy as np
import os

def main():
    """
    Generates 8 golden vector files for Verilog simulation.
    - Spec: 32-bit Accumulation, 128-bit Data Bus.
    - Format: Fixed 2-Line per Time Step (T).
        Even Address (2*t)     : T=t, Cols 0-3
        Odd Address  (2*t + 1) : T=t, Cols 4-7
        
        If M <= 4, Odd Addresses are UNUSED ('x').
        If M > 4,  Odd Addresses contain valid data (or 0-padding).
    """
    
    mnt_vectors = [0x444, 0x337, 0x374, 0x376, 0x634, 0x738, 0x583, 0x555]

    input_matrix = np.array([
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x01],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x01],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x01],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x01]
    ], dtype=np.int64)

    transposed_weight_matrix = np.array([
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
    ], dtype=np.int64)

    print("Generating 8 Golden Vector Files (128-bit Width)...")

    for i in range(8):
        mnt = mnt_vectors[i]
        M = (mnt >> 8) & 0xF
        N = (mnt >> 4) & 0xF
        T = mnt & 0xF
        
        i_matrix = input_matrix[:T, :N]
        w_matrix = transposed_weight_matrix[:M, :N]
        transposed_w_matrix = w_matrix.T
        
        result_matrix = np.dot(i_matrix, transposed_w_matrix)

        # 16-entry Golden Memory (Initialize with None for 'x')
        golden_mem = [None] * 16 

        # Logic: Fixed 2 lines per T step.
        # Line 0 (Even): Cols 0-3
        # Line 1 (Odd): Cols 4-7
        
        for t in range(T):
            # 1. Process First Group (Cols 0-3) -> Even Address
            m_start = 0
            packed_val = 0
            for offset in range(4):
                m_idx = m_start + offset
                val = 0
                if m_idx < M:
                    val = int(result_matrix[t, m_idx]) & 0xFFFFFFFF
                else:
                    val = 0
                shift = (3 - offset) * 32
                packed_val |= (val << shift)
            
            addr_even = t * 2
            if addr_even < 16:
                golden_mem[addr_even] = packed_val

            # 2. Process Second Group (Cols 4-7) -> Odd Address
            # Only write if M > 4. If M <= 4, leave as None ('x')
            if M > 4:
                m_start = 4
                packed_val = 0
                for offset in range(4):
                    m_idx = m_start + offset
                    val = 0
                    if m_idx < M:
                        val = int(result_matrix[t, m_idx]) & 0xFFFFFFFF
                    else:
                        val = 0
                    shift = (3 - offset) * 32
                    packed_val |= (val << shift)
                
                addr_odd = t * 2 + 1
                if addr_odd < 16:
                    golden_mem[addr_odd] = packed_val

        # File Writing
        filename = f"golden_case_{i}.hex"
        script_dir = os.path.dirname(os.path.abspath(__file__))
        output_path = os.path.join(script_dir, filename)
        
        with open(output_path, 'w') as f:
            for val in golden_mem:
                if val is None:
                    f.write("x" * 32 + "\n")
                else:
                    f.write(f"{val:032x}\n")
        
        print(f"[SUCCESS] Generated {output_path} (MNT={mnt:x})")

if __name__ == "__main__":
    main()