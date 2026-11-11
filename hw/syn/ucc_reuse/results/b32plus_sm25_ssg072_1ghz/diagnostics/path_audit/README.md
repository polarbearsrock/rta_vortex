# Register-boundary critical-path audit

Accepted46711.098um2 candidate final setup paths; fixed SSG0.72V1GHz constraints, retiming off, no new exceptions.

Surviving operator names give partial attribution, not total module delay.

## cuda_inputs.rpt: +0 ps

- Start: `(F) op_i[1]`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_12632_reg/SE`; RTL `('\\u_fma_i_dpa16_i_core_l1[0]', 2)`, driver `u_fma_i_dpa16_i_core_mux_5160_51`.

## cuda_normal_s1.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[0]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) pre_select_366_reg/D`; RTL `select_366`, driver `registered scheduling selection`.

## cuda_normal_s2.rpt: +0 ps

- Start: `(R) p1_11435_reg/CP`; RTL `('\\u_fma_i_tiles_gen_tile[11].i_tile_g_row[1].g_col[0].y', 0)`, driver `\u_fma_i_tiles_gen_tile[11].i_tile_mux_3635_20`.
- End: `(R) p1_29537_reg/D`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 11)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.

## cuda_normal_s3.rpt: +0 ps

- Start: `(R) p1_29545_reg/CP`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 3)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.
- End: `(R) p1_32781_reg/D`; RTL `('u_fma_product_shifted', 40)`, driver `u_fma_i_mul_add_3749_22`.
- Surviving operator `u_fma_i_dpa16_i_core_u_align_mul_1344_28_I3` (20 output bits): 164 ps on named cells.
- Surviving operator `u_fma_i_mul_add_3749_22` (64 output bits): 75 ps on named cells.

## cuda_normal_s4.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[3]/CP`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_33980_reg/D`; RTL `('u_fma_lzc_data', 51)`, driver `u_fma_mux_6834_21`.
- Surviving operator `u_fma_i_factored_sum_add_7238_38` (79 output bits): 157 ps on named cells.

## cuda_normal_s5.rpt: +0 ps

- Start: `(R) p1_33402_reg/CP`; RTL `('u_fma_sum', 49)`, driver `u_fma_mux_6817_52`.
- End: `(R) p1_34742_reg/D`; RTL `('u_fma_sum_normalized', 17)`, driver `u_fma_mux_sum_normalized_6883_40`.

## cuda_normal_s6.rpt: +867 ps

- Start: `(R) p5_18159_reg/CP`; RTL `('u_fma_sfu_special', None)`, driver `u_fma_i_sfu_mux_r_special_4844_9`.
- End: `(R) p6_18159_reg/D`; RTL `('u_fma_sfu_special', None)`, driver `u_fma_i_sfu_mux_r_special_4844_9`.

## cuda_output.rpt: +0 ps

- Start: `(R) p5_14872_reg/CP`; RTL `('u_fma_cvt_i2f', None)`, driver `u_fma_cvt_i2f`.
- End: `(R) d_o[19]`; RTL `primary port`, driver `primary port`.

## cuda_sfu_s1.rpt: +0 ps

- Start: `(F) op_i[1]`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_12632_reg/SE`; RTL `('\\u_fma_i_dpa16_i_core_l1[0]', 2)`, driver `u_fma_i_dpa16_i_core_mux_5160_51`.

## cuda_sfu_s2.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[0]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) pre_select_366_reg/D`; RTL `select_366`, driver `registered scheduling selection`.

## cuda_sfu_s3.rpt: +0 ps

- Start: `(R) p1_11435_reg/CP`; RTL `('\\u_fma_i_tiles_gen_tile[11].i_tile_g_row[1].g_col[0].y', 0)`, driver `\u_fma_i_tiles_gen_tile[11].i_tile_mux_3635_20`.
- End: `(R) p1_29537_reg/D`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 11)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.

## cuda_sfu_s4.rpt: +0 ps

- Start: `(R) p1_29545_reg/CP`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 3)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.
- End: `(R) p1_32781_reg/D`; RTL `('u_fma_product_shifted', 40)`, driver `u_fma_i_mul_add_3749_22`.
- Surviving operator `u_fma_i_dpa16_i_core_u_align_mul_1344_28_I3` (20 output bits): 164 ps on named cells.
- Surviving operator `u_fma_i_mul_add_3749_22` (64 output bits): 75 ps on named cells.

## cuda_sfu_s5.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[3]/CP`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_33980_reg/D`; RTL `('u_fma_lzc_data', 51)`, driver `u_fma_mux_6834_21`.
- Surviving operator `u_fma_i_factored_sum_add_7238_38` (79 output bits): 157 ps on named cells.

## cuda_sfu_s6.rpt: +0 ps

- Start: `(R) p1_33402_reg/CP`; RTL `('u_fma_sum', 49)`, driver `u_fma_mux_6817_52`.
- End: `(R) p1_34742_reg/D`; RTL `('u_fma_sum_normalized', 17)`, driver `u_fma_mux_sum_normalized_6883_40`.

## dpa_inputs.rpt: +0 ps

- Start: `(F) op_i[1]`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_12632_reg/SE`; RTL `('\\u_fma_i_dpa16_i_core_l1[0]', 2)`, driver `u_fma_i_dpa16_i_core_mux_5160_51`.

## dpa_normal_s1.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[0]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) pre_select_366_reg/D`; RTL `select_366`, driver `registered scheduling selection`.

## dpa_normal_s2.rpt: +0 ps

- Start: `(R) p1_11435_reg/CP`; RTL `('\\u_fma_i_tiles_gen_tile[11].i_tile_g_row[1].g_col[0].y', 0)`, driver `\u_fma_i_tiles_gen_tile[11].i_tile_mux_3635_20`.
- End: `(R) p1_29537_reg/D`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 11)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.

## dpa_normal_s3.rpt: +0 ps

- Start: `(R) p1_29715_reg/CP`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[0]', 1)`, driver `u_fma_i_dpa16_i_core_mux_5254_28`.
- End: `(R) p1_32925_reg/D`; RTL `('u_fma_shared_add_a', 8)`, driver `u_fma_mux_6801_7`.
- Surviving operator `u_fma_i_dpa16_i_core_u_align_mul_1344_28_I1` (20 output bits): 90 ps on named cells.

## dpa_normal_s4.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[3]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) p1_34241_reg/SN`; RTL `('\\u_fma_fp32_round[special]', None)`, driver `u_fma_mux_6898_27`.
- Surviving operator `u_fma_i_factored_sum_add_7238_38` (79 output bits): 51 ps on named cells.

## dpa_normal_s5.rpt: +0 ps

- Start: `(R) p1_33976_reg/CP`; RTL `('u_fma_lzc_data', 55)`, driver `u_fma_mux_6834_21`.
- End: `(R) p1_34833_reg/D`; RTL `('u_fma_n_2596', None)`, driver `u_fma_mux_6917_35`.

## dpa_normal_s6.rpt: +867 ps

- Start: `(R) p5_18159_reg/CP`; RTL `('u_fma_sfu_special', None)`, driver `u_fma_i_sfu_mux_r_special_4844_9`.
- End: `(R) p6_18159_reg/D`; RTL `('u_fma_sfu_special', None)`, driver `u_fma_i_sfu_mux_r_special_4844_9`.

## dpa_output.rpt: +0 ps

- Start: `(R) p5_14872_reg/CP`; RTL `('u_fma_cvt_i2f', None)`, driver `u_fma_cvt_i2f`.
- End: `(R) d_o[19]`; RTL `primary port`, driver `primary port`.

## dpa_sfu_s1.rpt: +0 ps

- Start: `(F) op_i[1]`; RTL `primary port`, driver `primary port`.
- End: `(R) p1_12632_reg/SE`; RTL `('\\u_fma_i_dpa16_i_core_l1[0]', 2)`, driver `u_fma_i_dpa16_i_core_mux_5160_51`.

## dpa_sfu_s2.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[0]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) pre_select_366_reg/D`; RTL `select_366`, driver `registered scheduling selection`.

## dpa_sfu_s3.rpt: +0 ps

- Start: `(R) p1_11435_reg/CP`; RTL `('\\u_fma_i_tiles_gen_tile[11].i_tile_g_row[1].g_col[0].y', 0)`, driver `\u_fma_i_tiles_gen_tile[11].i_tile_mux_3635_20`.
- End: `(R) p1_29537_reg/D`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[2]', 11)`, driver `u_fma_i_dpa16_i_core_mux_5254_225`.

## dpa_sfu_s4.rpt: +0 ps

- Start: `(R) p1_29715_reg/CP`; RTL `('\\u_fma_i_dpa16_i_core_r1_tprod[0]', 1)`, driver `u_fma_i_dpa16_i_core_mux_5254_28`.
- End: `(R) p1_32925_reg/D`; RTL `('u_fma_shared_add_a', 8)`, driver `u_fma_mux_6801_7`.
- Surviving operator `u_fma_i_dpa16_i_core_u_align_mul_1344_28_I1` (20 output bits): 90 ps on named cells.

## dpa_sfu_s5.rpt: +0 ps

- Start: `(R) sfu_valid_pipe_reg[3]/CP`; RTL `primary port`, driver `primary port`.
- End: `(F) p1_34241_reg/SN`; RTL `('\\u_fma_fp32_round[special]', None)`, driver `u_fma_mux_6898_27`.
- Surviving operator `u_fma_i_factored_sum_add_7238_38` (79 output bits): 51 ps on named cells.

## dpa_sfu_s6.rpt: +0 ps

- Start: `(R) p1_33976_reg/CP`; RTL `('u_fma_lzc_data', 55)`, driver `u_fma_mux_6834_21`.
- End: `(R) p1_34833_reg/D`; RTL `('u_fma_n_2596', None)`, driver `u_fma_mux_6917_35`.
