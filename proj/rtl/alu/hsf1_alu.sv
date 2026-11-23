//+FHDR--------------------------------------------------------------------
// Copyright (C) 2025 Hasunosora IC Design Club
// MIT License
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this design and associated documentation files (the “Design”),
// to deal in the Design without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Design, and to permit persons to whom the
// Design is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Design.
//
// THE DESIGN IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
// TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// DESIGN OR THE USE OR OTHER DEALINGS IN THE DESIGN.
//-------------------------------------------------------------------------
// FILE NAME: hsf1_alu.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/26    First Edition
// 0.1a1      O. Tsusaki    2025/11/30    Move right pre-align of Y's mantissa
//                                        to pre-proc stage for performance
//                                        optimization
//                                        Move leading zero counter (LZC) to
//                                        ALU stage for performance optimi-
//                                        zation
// 0.2        O. Tsusaki    2026/11/23    Fix some overflow to infinite saturation
//                                        when TOWARD_ZERO/TOWARD_POSITIVE/TOWARD_NEGATIVE
//                                        has been selected.
//                                        ALU need to reserve the immediate determination
//                                        and move it to post-proc stage.
//-------------------------------------------------------------------------
// PURPOSE: Arithmetic logic unit (stage) for pipelined floating point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf1_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Arithmetic logic unit (stage) for pipelined floating point adder
module hsf1_alu
import hsf1_typedef_pkg::*;
#(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    `LP_MODULE int LZC_WIDTH = $clog2(MANTISSA_WIDTH + 2 + 1)
)
(
    // Input operators
    // X: larger operator, Y: smaller operator
    input  logic           [MANTISSA_WIDTH + 1 - 1:0] mant_x_in,
    input  logic           [MANTISSA_WIDTH + 1 - 1:0] mant_y_in,

    // This field is also multiplexed for the exponent of bypass results
    input  logic           [EXPONENT_WIDTH - 1:0]     exp_result_in,

    input  preproc_flags_s                            flags_in,

    output logic           [EXPONENT_WIDTH - 1:0]     exp_result_out,
    output logic           [MANTISSA_WIDTH + 1 - 1:0] mant_result_out,

    output logic           [LZC_WIDTH - 1:0]          mant_lzc_out,

    output alu_flags_s                                flags_out
);

`HSF1_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);
`HSF1_EXPONENT_TYPEDEF(EXPONENT_WIDTH);

typedef logic [LZC_WIDTH - 1:0] lzc_t;

typedef struct packed
{
    fp_ext_mant_t mantissa;
    grs_s         grs;
} fp_grs_mant_s;

typedef struct packed
{
    logic [1:0]                  carry_hidden;
    logic [MANTISSA_WIDTH - 1:0] mantissa;
    grs_s                        grs;
} fp_sum_grs_mant_s;

typedef struct packed
{
    fp_ext_mant_t mantissa;
    logic         guard;
    logic         round;
} fp_sftable_mant_s;

// Initial GRS bits
grs_s                      initial_grs;

// Extended X, Y's mantissa w/ GRS bits
fp_grs_mant_s              mant_grs_x;
fp_grs_mant_s              ralign_mant_grs_y;

// Core adder result
fp_sum_grs_mant_s          sum_grs;
logic                      sum_carry_out;

// Summary mantissa result
fp_ext_mant_t              mant_sum;
fp_sftable_mant_s          sftable_mant_sum;

// Exponent reuslt
fp_exp_t                   exp_result;

// Leading zero count of result mantissa for normalize
lzc_t                      mant_sum_lzc;
logic                      mant_sum_zero;

// Initial GRS bits are all zero
assign initial_grs.guard          = '0;
assign initial_grs.round          = '0;
assign initial_grs.sticky         = '0;

// Update note: We move the pre-align of Y's mantissa (right shifter)
// to pre-proc stage to balance the logic delay of these two stages
// Now, the core adder can receive the aligned mantissa directly from
// pipeline register slice

// Merge GRS bits into extended mantissas
assign mant_grs_x.mantissa        = mant_x_in;
assign mant_grs_x.grs             = initial_grs;
assign ralign_mant_grs_y.mantissa = mant_y_in;
assign ralign_mant_grs_y.grs      = flags_in.grs;

// Core adder
hsf1_cadder
#(
    .DATA_WIDTH($bits(fp_grs_mant_s))
)
cadder_inst
(
    .op_a_in   (mant_grs_x           ),
    .op_b_in   (ralign_mant_grs_y    ),
    .add_sub   (flags_in.add_sub     ),
    .result_out(sum_grs              )
);

assign sum_carry_out              = sum_grs.carry_hidden[1];

// Overflow detection
// Fix on 0.2, we do not detemine the overflow to infinite
// at ALU stage. The infinite flag is only from the pre-proc stage now.
assign flags_out.result_inf       = flags_in.result_inf;

// Exponent result
assign exp_result                 = sum_carry_out ? (exp_result_in + 'd1) : exp_result_in;

// Fix on 0.2, remove the selection of overflow exponent
always_comb begin : exp_result_mux
    if (flags_in.result_pass) begin
        // Bypass
        exp_result_out = exp_result_in;
    end
    else begin
        exp_result_out = exp_result;
    end
end : exp_result_mux

// Summary mantissa
// Fix on 0.2, remove the branch of overflow cause mantissa to zero
always_comb begin : mant_sum_mux
    if (sum_carry_out) begin
        // Right shift 1 bit
        // Fix on 0.2, we don't use {sum_grs.carry_hidden, sum_grs.mantissa[MANTISSA_WIDTH - 1:1]}
        // because if the MANTISSA_WIDTH = 1, it cause sum_gra.mantissa[0:1] error
        mant_sum         = sum_grs[4 +: (MANTISSA_WIDTH + 1)];
        sftable_mant_sum = {sum_grs.carry_hidden, sum_grs.mantissa, sum_grs.grs.guard};
    end
    else begin
        mant_sum         = {sum_grs.carry_hidden[0], sum_grs.mantissa};
        sftable_mant_sum = {sum_grs.carry_hidden[0], sum_grs.mantissa, sum_grs.grs.guard, sum_grs.grs.round};
    end
end : mant_sum_mux

// Leading zero counter (LZC) for result mantissa
hsf1_lzc
#(
    .DATA_WIDTH($bits(fp_sftable_mant_s))
)
lzc_inst
(
    .din     (sftable_mant_sum),
    .lzc     (mant_sum_lzc    ),
    .all_zero(mant_sum_zero   )
);

assign mant_lzc_out               = mant_sum_lzc;

// Fix on 0.2, sticky bit may affect the all-zero check of the mantissa.
assign flags_out.mant_sum_zero    = mant_sum_zero && !sum_grs.grs.sticky;

// Comparator between exponent and LZC
assign flags_out.lzc_lt_exp       = mant_sum_lzc < exp_result;

// Mantissa result
always_comb begin : mant_result_mux
    if (flags_in.result_pass) begin
        mant_result_out = flags_in.result_pass_x_y ? mant_y_in : mant_x_in;
    end
    else begin
        mant_result_out = mant_sum;
    end
end : mant_result_mux

// GRS result
// Fix on 0.2, remove overflow branch to clear GRS bits
always_comb begin : grs_result_mux
    if (flags_in.result_pass) begin
        // Bypass or overflow to infinity, GRS all zero
        flags_out.grs.guard  = '0;
        flags_out.grs.round  = '0;
        flags_out.grs.sticky = '0;
    end
    else if (sum_carry_out) begin
        // Right shift, need recalculate GRS
        flags_out.grs.guard  = sum_grs.mantissa[0];
        flags_out.grs.round  = sum_grs.grs.guard;
        flags_out.grs.sticky = sum_grs.grs.sticky | sum_grs.grs.round;
    end
    else begin
        flags_out.grs.guard  = sum_grs.grs.guard;
        flags_out.grs.round  = sum_grs.grs.round;
        flags_out.grs.sticky = sum_grs.grs.sticky;
    end
end : grs_result_mux

// Pass flags
assign flags_out.result_nan       = flags_in.result_nan;
assign flags_out.result_sign      = flags_in.result_sign;
assign flags_out.result_pass      = flags_in.result_pass;

endmodule : hsf1_alu