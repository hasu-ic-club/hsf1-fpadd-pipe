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
// FILE NAME: hsf1_postproc.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a1
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/27    First Edition
// 0.1a1      O. Tsusaki    2025/11/30    Move leading zero counter (LZC) to
//                                        ALU stage for performance optimi-
//                                        zation
//-------------------------------------------------------------------------
// PURPOSE: Postprocess stage of pipelined floating point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MOD    fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf1_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Postprocess stage of pipelined floating point adder
module hsf1_postproc
import hsf1_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH  = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH,
    `LP_MODULE int LZC_WIDTH = $clog2(MANTISSA_WIDTH + 2 + 1)
)
(
    // Result under process input
    input  logic             [MANTISSA_WIDTH + 1 - 1:0] mant_in,
    input  logic             [EXPONENT_WIDTH - 1:0]     exp_in,

    // LZC input
    input  logic             [LZC_WIDTH - 1:0]          lzc_in,

    // Flags
    input  alu_flags_s                                  flags_in,

    // Output
    output logic             [OP_WIDTH - 1:0]           result_out,
    output exception_flags_s                            exception_out
);

`HSF1_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);
`HSF1_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF1_EXPONENT_TYPEDEF(EXPONENT_WIDTH);
`HSF1_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

localparam    fp_exp_t MAX_EXPONENT      = {EXPONENT_WIDTH{1'b1}};          // Exponent all 1 (overflowed)
localparam    fp_exp_t EDGE_EXPONENT     = MAX_EXPONENT - 1;                // This is the real valid maximum exponent

typedef logic [LZC_WIDTH - 1:0] lzc_t;

// Zero
logic                  mant_all_zero;

// Hidden bit
logic                  hidden_bit;

// Leading zero count of result mantissa for normalize
lzc_t                  mant_result_lzc;
logic                  lzc_lt_exp;

// Left shift amount for normalize
fp_exp_t               lshift_amount;

// Re-aligned result (left shifted)
fp_ext_mant_t          ralign_lsft_mant;
grs_s                  ralign_lsft_grs;
fp_exp_t               ralign_exp;

// Rounded mantissa
fp_ext_mant_t          rnd_mant;
logic                  rnd_cout;

// Final result
fp_mant_t              result_mant;
fp_exp_t               result_exp;
logic                  final_rnd_to_inf;

fp_s                   result_fp;

// Assign all zero determination
assign mant_all_zero     = flags_in.mant_sum_zero && ~flags_in.grs.guard && ~flags_in.grs.round;

// Assign the hidden bit
assign hidden_bit        = mant_in[MANTISSA_WIDTH];

// LZC of mantissa result 
assign mant_result_lzc   = lzc_in;

// Determine the normalize left shift amount
assign lzc_lt_exp        = flags_in.lzc_lt_exp;

always_comb begin : lshift_amount_dete
    if (!hidden_bit && (exp_in != 'd1) && (exp_in != 'd0)) begin
        if (lzc_lt_exp) begin
            // Not a denormalized number, to shift left with leading zeros of mantissa
            lshift_amount = fp_exp_t'(mant_result_lzc);
        end
        else begin
            // Count of leading zero(s) large than exponent can handle,
            // convert to the denormalized number by shift out all exponent
            lshift_amount = exp_in - 'd1;
        end
    end
    else begin
        lshift_amount = '0;
    end
end : lshift_amount_dete

// Left shifter w/ GRS for re-align
hsf1_grs_lshift
#(
    .DATA_WIDTH      ($bits(fp_ext_mant_t)),
    .SFT_AMOUNT_WIDTH($bits(fp_exp_t)     )
)
grs_lshift_inst
(
    .grs_in  (flags_in.grs    ),
    .data_in (mant_in         ),
    .sft_in  (lshift_amount   ),
    .data_out(ralign_lsft_mant),
    .grs_out (ralign_lsft_grs )
);

// Realign exponent (left shift)
always_comb begin : ralign_exp_dete
    if (flags_in.result_nan || flags_in.result_inf) begin
        // All ones exponent means NaN or Inf
        ralign_exp = '1;
    end
    else if (mant_all_zero) begin
        // All zero
        ralign_exp = '0;
    end
    else if (!hidden_bit) begin
        if (lzc_lt_exp && (exp_in != 'd1) && (exp_in != 'd0)) begin
            // Right shift for realign
            ralign_exp = exp_in - mant_result_lzc;
        end
        else begin
            // Zero / denormalized number
            ralign_exp = '0;
        end
    end
    else begin
        // Normal
        ralign_exp = exp_in;
    end
end : ralign_exp_dete

// GRS rounding
hsf1_grs_round
#(
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
grs_round_inst
(
    .sign_in     (flags_in.result_sign),
    .ext_mant_in (ralign_lsft_mant    ),
    .grs_in      (ralign_lsft_grs     ),
    .rnd_mant_out(rnd_mant            ),
    .rnd_cout    (rnd_cout            )
);

// Final realign / fix
always_comb begin : final_fix
    if (rnd_cout) begin
        // Round and overflow to next exponent
        if (ralign_exp == EDGE_EXPONENT) begin
            // Overflow to infinity
            result_exp       = MAX_EXPONENT;
            result_mant      = '0;
            final_rnd_to_inf = '1;
        end
        else begin
            result_exp       = ralign_exp + 'd1;                // Right shift for re-align
            result_mant      = rnd_mant[1 +: $bits(fp_mant_t)]; // Right shift 1 bit and hidden bit truncate
            final_rnd_to_inf = '0;
        end
    end
    else if (rnd_mant[$bits(fp_mant_t)] && (~|ralign_exp)) begin
        // A denormalized number overflowed to normalized
        result_exp       = EXPONENT_WIDTH'(1);
        result_mant      = rnd_mant[0 +: $bits(fp_mant_t)]; // Hidden bit truncate
        final_rnd_to_inf = '0;
    end
    else begin
        // Normal
        result_exp       = ralign_exp;
        result_mant      = rnd_mant[0 +: $bits(fp_mant_t)]; // Hidden bit truncate
        final_rnd_to_inf = '0;
    end
end : final_fix

// Result output
always_comb begin : result_mux
    if (flags_in.result_nan) begin
        // Generate a NaN number
        result_fp.sign     = '0;
        result_fp.mantissa = $bits(fp_mant_t)'(1);
        result_fp.exp      = '1;
    end
    else if (flags_in.result_pass) begin
        // Directly pass the number
        result_fp.sign     = flags_in.result_sign;
        result_fp.mantissa = mant_in[0 +: $bits(fp_mant_t)];
        result_fp.exp      = exp_in;
    end
    else begin
        result_fp.sign     = (mant_all_zero && !flags_in.result_inf) ? '0 : flags_in.result_sign;
        result_fp.mantissa = result_mant;
        result_fp.exp      = result_exp;
    end
end : result_mux

assign result_out        = result_fp;

// Exception flags output
assign exception_out.nan = flags_in.result_nan;
assign exception_out.inf = !flags_in.result_nan && (flags_in.result_inf || final_rnd_to_inf);

endmodule : hsf1_postproc