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
// FILE NAME: hsf1_preproc.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Corner-cases fixed Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/26    First Edition
// 0.1a1      O. Tsusaki    2025/11/30    Move right pre-align of Y's mantissa
//                                        to pre-proc stage for performance
//                                        optimization
// 0.2        O. Tsusaki    2026/11/23    Fix the output sign of both zero operands
//                                        in all rounding modes
//-------------------------------------------------------------------------
// PURPOSE: Preprocess stage of pipelined floating point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// N/A
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf1_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Preprocess stage of pipelined floating point adder
module hsf1_preproc
import hsf1_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Input operators
    input  logic           [OP_WIDTH - 1:0]           op_a_in,
    input  logic           [OP_WIDTH - 1:0]           op_b_in,

    // Output operators
    // X: larger operator, Y: smaller operator
    // Note: Y is realigned when no bypass applied
    output logic           [MANTISSA_WIDTH + 1 - 1:0] mant_x_out,
    output logic           [MANTISSA_WIDTH + 1 - 1:0] mant_y_out,

    // This field is also multiplexed for the exponent of bypass results
    output logic           [EXPONENT_WIDTH - 1:0]     exp_result,

    output preproc_flags_s                            flags
);

`HSF1_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF1_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF1_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF1_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

// FP format structure
fp_s          op_a_fp;
fp_s          op_b_fp;

// Extended mantissa
fp_ext_mant_t ext_mant_a;
fp_ext_mant_t ext_mant_b;

// Fixed exponent (denormalized number's exponent to 1)
fp_exp_t      fixed_exp_a;
fp_exp_t      fixed_exp_b;

// Zero determination flag
logic         both_zero;

// Bypass flags
logic         result_pass;
logic         result_pass_a_b;

// Denormalized number flag
logic         op_a_denorm;
logic         op_b_denorm;

// Exponent align flags
logic         exp_a_lt_b;
logic         exp_a_eq_b;
logic         mant_a_lt_b;

logic         b_large;        // Indicate operator B is large, and we need to swap A/B

// Swapped mantissa of Y, which not re-aligned
fp_ext_mant_t mant_y;

// Swapped exponent for exponent difference
fp_exp_t      exp_x;
fp_exp_t      exp_y;

// Exponent difference
fp_exp_t      exp_diff;

// Initial GRS bits
grs_s         initial_grs;

// Re-aligned Y's mantissa
fp_ext_mant_t mant_y_realign;

// GRS bits for re-aligned Y's mantissa
grs_s         realign_grs;

// Assign input operators to FP format
assign op_a_fp                 = fp_s'(op_a_in);
assign op_b_fp                 = fp_s'(op_b_in);

// Special result generator for NaN/infinity/zero values
hsf1_sp_result_gen
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
sp_result_gen_inst
(
    .op_a_in    (op_a_in         ),
    .op_b_in    (op_b_in         ),
    .result_nan (flags.result_nan),
    .both_zero  (both_zero       ),
    .result_pass(result_pass     ),
    .pass_a_b   (result_pass_a_b ),
    .result_inf (flags.result_inf),
    .op_a_denorm(op_a_denorm     ),
    .op_b_denorm(op_b_denorm     )
);

// Extend mantissa with hidden bit
// Note: Denormalized (sub-normal) number has not hidden bit
assign ext_mant_a              = {~op_a_denorm, op_a_fp.mantissa};
assign ext_mant_b              = {~op_b_denorm, op_b_fp.mantissa};

// Fix the exponent for denormalized number
assign fixed_exp_a             = op_a_denorm ? fp_exp_t'('d1) : op_a_fp.exp;
assign fixed_exp_b             = op_b_denorm ? fp_exp_t'('d1) : op_b_fp.exp;

// Exponent comparison
assign exp_a_lt_b              = op_a_fp.exp < op_b_fp.exp;
assign exp_a_eq_b              = op_a_fp.exp == op_b_fp.exp;
assign mant_a_lt_b             = ext_mant_a < ext_mant_b;

assign b_large                 = exp_a_lt_b || (exp_a_eq_b && mant_a_lt_b);

// Non-swap/swap for operators
always_comb begin : op_swap
    if (b_large && ~result_pass) begin
        // Note: when pass through enabled, we do NOT swap the operators
        // and let X = A, Y = B
        // X = B, Y = A
        mant_x_out = ext_mant_b;
        mant_y     = ext_mant_a;
        exp_x      = fixed_exp_b;
        exp_y      = fixed_exp_a;
    end
    else begin
        // X = A, Y = B
        mant_x_out = ext_mant_a;
        mant_y     = ext_mant_b;
        exp_x      = fixed_exp_a;
        exp_y      = fixed_exp_b;
    end
end : op_swap

// Result sign determination
always_comb begin : result_sign_dete
    // Add on 0.2, both zero branch
    if (both_zero) begin
        if (FP_ROUND_MODE == FP_ROUND_MODE_TOWARD_NEGATIVE) begin
            flags.result_sign = op_a_fp.sign | op_b_fp.sign;
        end
        else begin
            flags.result_sign = op_a_fp.sign & op_b_fp.sign;
        end
    end
    else if (result_pass) begin
        // When bypass enabled, pass corresponding sign for result
        flags.result_sign = result_pass_a_b ? op_b_fp.sign : op_a_fp.sign;
    end
    else begin
        flags.result_sign = b_large ? op_b_fp.sign : op_a_fp.sign;
    end
end : result_sign_dete

// Exponent difference
assign exp_diff                = exp_x - exp_y;

// Result exponent / bypass exponent
always_comb begin : exp_result_mux
    if (result_pass) begin
        exp_result = result_pass_a_b ? op_b_fp.exp : op_a_fp.exp;
    end
    else begin
        exp_result = exp_x;
    end
end : exp_result_mux

// Initial GRS bits are all zero
assign initial_grs.guard       = '0;
assign initial_grs.round       = '0;
assign initial_grs.sticky      = '0;

// Right shifter w/ GRS for pre-align exponent of Y
hsf1_grs_rshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH(EXPONENT_WIDTH      )
)
pre_align_rshift_inst
(
    .grs_in  (initial_grs   ),
    .data_in (mant_y        ),
    .sft_in  (exp_diff      ),
    .data_out(mant_y_realign),
    .grs_out (realign_grs   )
);

// Output GRS flags
assign flags.grs               = realign_grs;

// Select Y mantissa directly pass to next stage (bypass)
// or re-aligned mantissa pass to next stage (normal)
assign mant_y_out              = result_pass ? mant_y : mant_y_realign;

// Output bypass flags
assign flags.result_pass       = result_pass;
assign flags.result_pass_x_y   = result_pass_a_b;

// Select adder/subtractor for same/different sign
assign flags.add_sub           = op_a_fp.sign ^ op_b_fp.sign;

endmodule : hsf1_preproc