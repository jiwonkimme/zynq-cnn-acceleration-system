///////////////////////////////////
//            TEAM XX            // 
//                               //
//  - 20xxxxxxxx  KIM MINSU      //
//  - 20xxxxxxxx  LEE YOUNGHEE   //
//  - 20xxxxxxxx  HONG GILDONG   //
///////////////////////////////////

#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "xil_exception.h"

#include "cnn_common.h"     // includes embedded arrays & PS forward() helpers



// ========================== PL CONTROL (FILL THESE) ==========================
// Define your PL register offsets and buffer base addresses here.
// Example:
//   #define PL_BASE        XPAR_MY_CNN_TOP_0_S00_AXI_BASEADDR
//   #define PL_REG_CTRL    (PL_BASE + 0x00)   // bit0: start, bit1: done
//   #define PL_REG_IN_ADDR (PL_BASE + 0x10)
//   #define PL_REG_OUT     (PL_BASE + 0x14)
//
// NOTE: These are *placeholders*. Students must fill them to match their IP.
// ============================================================================



int main(void)
{
    init_platform();

    // Enable global timer counter
    Xil_Out32(GTIMER_CONTROL_REG, 0x1);

    int inbyte_in;
    while (1)
    {
        print ("********************** SoC CNN Acceleration System ***********************\r\n ");
        print ("Press '1' to run the test \r\n");
        print ("Press '2' to exit \r\n");
        print ("Selection:");
        inbyte_in = inbyte ();
        print ("\r\n");
        print ("\r\n");

        switch (inbyte_in)
        {
            case '1':
                printf("\n[PS vs PL E2E CNN] N_TEST=%d\n", N_TEST);

                // ============================= PS PATH =============================
                printf(">>> CNN Running in PS...\n");
                u64 t0_ps = Get_Global_Time();

                int correct_ps = 0;
                u64 cyc_ps = 0;
                for (int i = 0; i < N_TEST; i++){
                    const uint8_t* x = &test_1000_images_embedded[i*IMG_SIZE];
                    uint8_t label = test_1000_labels_embedded[i];
                
                    uint8_t pred = ps_forward_one(x, conv1_w_embedded, conv2_w_embedded, fc1_w_embedded);
                
                    if (pred == label) correct_ps++;
                }
            
                u64 t1_ps = Get_Global_Time();
                cyc_ps = (t1_ps - t0_ps);
                // ==================================================================
                
            
                // ====================== PL WEIGHT UPLOAD (ONCE) ===================
                print(">>> Loading weights to PL...\r\n");
                u64 t_w0 = Get_Global_Time();

                // TODO(PL_weights): Upload weights for PL here.
                // ...
                // ...
                // ...
                // - - - - - - - - - - - - - - - - - - - - - - -  
                
                u64 t_w1 = Get_Global_Time();
                u64 cyc_pl_weight = (t_w1 - t_w0);
                // ==================================================================


                // ============================ PL PATH =============================
                print(">>> CNN Running in PL...\n");
                u64 t0_pl = Get_Global_Time();

                int correct_pl = 0;
                for (int i = 0; i < N_TEST; i++) {
                    const uint8_t* x     = &test_1000_images_embedded[i * IMG_SIZE];
                    const uint8_t  label =  test_1000_labels_embedded[i];

                    // TODO(PL_invoke): Send the input to PL, start, wait done, read result.
                    //   -> Your code must set the variable 'pred' (0..9) for accuracy check.
                    // ...
                    // ...
                    // ...
                    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

                    uint8_t pred = 0;

                    if (pred == label) correct_pl++;
                }

                u64 t1_pl         = Get_Global_Time();
                u64 cyc_pl_infer  = (t1_pl - t0_pl);
                // ==================================================================
            


                // ============================= SUMMARY ============================
                double us_ps_total  = cycles_to_us(cyc_ps);
                double us_pl_weight = cycles_to_us(cyc_pl_weight);
                double us_pl_infer  = cycles_to_us(cyc_pl_infer);
                
            
                printf("\n=== Summary ===\n");
                printf("PS  Acc = %d/%d = %.2f%% | Total = %.2f us | Avg/img = %.2f us\n",
                    correct_ps, N_TEST, 100.0*correct_ps/N_TEST, us_ps_total, us_ps_total/N_TEST);
                printf("PL  Acc = %d/%d = %.2f%% | Weight upload = %.2f us\n",
                    correct_pl, N_TEST, 100.0*correct_pl/N_TEST, us_pl_weight);
                printf("PL  Inference only: Total = %.2f us | Avg/img = %.2f us\n",
                    us_pl_infer, us_pl_infer/N_TEST);
                printf("PL  Cold-start total (upload + infer) = %.2f us\n",
                    us_pl_weight + us_pl_infer);

                if (us_pl_infer > 0)
                    printf("Speedup (PS/PL, steady-state avg) = %.2fx\n",
                        (us_ps_total/N_TEST) / (us_pl_infer/N_TEST));
                // ==================================================================
                break;

            case '2':
                print ("exit \r\n");
                cleanup_platform();
                return 0;

            default:
                print("Invalid selection. Please press '1' or '2'.\r\n");
                break;
        }

        print("\r\n");
    }

    cleanup_platform();
    return 0;
}
