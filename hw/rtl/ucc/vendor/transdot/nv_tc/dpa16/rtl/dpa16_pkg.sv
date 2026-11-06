// DPA-16 PE: shared definitions. Reference model: ../model/dpa16_ref.py
package dpa16_pkg;
  typedef enum logic [2:0] {
    FMT_FP16  = 3'd0,   // 16 x FP16
    FMT_BF16  = 3'd1,   // 16 x BF16
    FMT_TF32  = 3'd2,   //  8 x TF32 (32-bit containers)
    FMT_FP8   = 3'd3,   // 32 x E4M3 / E5M2 (per side)
    FMT_NVFP4 = 3'd4,   // 64 x E2M1, UE4M3 scale per 16
    FMT_MXFP4 = 3'd5    // 64 x E2M1, E8M0 scale per 32 (given per 16-block)
  } fmt_e;

  localparam int NTILE = 16;   // 12x12 multiplier tiles
  localparam int NSLOT = 32;   // aligned product slots (FP8 uses all 32)
  localparam int WIN   = 27;   // alignment window: 2 integer + 25 fraction bits
  localparam int AW    = 12;   // signed anchor / exponent width
  localparam int SUMW  = 34;   // signed sum of 33 window terms

  localparam logic [31:0] QNAN = 32'h7FC0_0000;
endpackage
