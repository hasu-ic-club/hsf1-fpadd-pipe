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
// FILE NAME: hsf1_fpadd_pipe.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Corner-cases fixed Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/26    First Edition
// 0.1a1      O. Tsusaki    2025/11/30    Performance optimization by
//                                        move some logic units backward
//                                        to early stages
//                                        Move leading zero counter (LZC) to
//                                        ALU stage for performance optimi-
//                                        zation
// 0.2        O. Tsusaki    2026/11/23    Passing the rounding mode to pre-process
//                                        stage to handle the both zero saturation
//-------------------------------------------------------------------------
// PURPOSE: Pipelined floating-point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME  RANGE           DESCRIPTION             DEFAULT VALUE
// EXPONENT_WIDTH  1-32            Exponent bit width      8
// MANTISSA_WIDTH  1-128           Mantissa bit width      23
// FP_ROUND_MODE   fp_round_mode_s Floating point rounding FP_ROUND_MODE_TIES_TO_EVEN
//                                 mode
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"
`include "hsf1_macros.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Pipelined floating-point adder
module hsf1_fpadd_pipe
import hs_ifr_misc_typedefs_pkg::*;
import hsf1_typedef_pkg::*;
#(
    parameter int             EXPONENT_WIDTH = 8,
    parameter int             MANTISSA_WIDTH = 23,
    parameter fp_round_mode_s FP_ROUND_MODE  = FP_ROUND_MODE_TIES_TO_EVEN,
    `LP_MODULE int OP_WIDTH = 1 + EXPONENT_WIDTH + MANTISSA_WIDTH
)
(
    // Clock & reset
    input  logic                  clk,
    input  logic                  aresetn,

    // Operators input (handshake)
    input  logic [OP_WIDTH - 1:0] op_a_in,
    input  logic [OP_WIDTH - 1:0] op_b_in,
    input  logic                  op_valid,
    output logic                  op_ready,

    // Result output (handshake)
    output logic [OP_WIDTH - 1:0] result_out,
    output logic                  result_valid,
    input  logic                  result_ready,

    // Exception output (sync with result)
    output logic                  exception_out,    // Indicate the result has exception value (NaN/Infinite)
    output logic                  nan_out,          // Indicate the result is NaN
    output logic                  inf_out           // Indicate the result is infinite
);

`HSF1_FP_TYPEDEF(EXPONENT_WIDTH, MANTISSA_WIDTH);

`HSF1_MANTISSA_TYPEDEF(MANTISSA_WIDTH);
`HSF1_EXPONENT_TYPEDEF(EXPONENT_WIDTH);

`HSF1_EXT_MANT_TYPEDEF(MANTISSA_WIDTH);

localparam        int LZC_WIDTH             = $clog2(MANTISSA_WIDTH + 2 + 1);
typedef logic [LZC_WIDTH - 1:0] lzc_t;

// Packed structures for inter-stage data path
typedef struct packed
{
    fp_exp_t        exp_result;
    fp_ext_mant_t   mant_x;
    fp_ext_mant_t   mant_y;
    preproc_flags_s flags;
} preproc_alu_dp_s;

typedef struct packed
{
    fp_exp_t      exp_result;
    fp_ext_mant_t mant_result;
    lzc_t         lzc;
    alu_flags_s   flags;
} alu_postproc_dp_s;

typedef struct packed
{
    fp_s              result;
    exception_flags_s exception_flags;
} postproc_out_dp_s;

// Inter-stage handshake
logic                 preproc_alu_hs_valid;
logic                 preproc_alu_hs_ready;

logic                 alu_postproc_hs_valid;
logic                 alu_postproc_hs_ready;

// Inter-stage data path
preproc_alu_dp_s      preproc_out;
preproc_alu_dp_s      alu_in;

alu_postproc_dp_s     alu_out;
alu_postproc_dp_s     postproc_in;

postproc_out_dp_s     postproc_out;
postproc_out_dp_s     output_dp;

// Stage I: Pre-process stage
hsf1_preproc
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
preproc_inst
(
    .op_a_in   (op_a_in               ),
    .op_b_in   (op_b_in               ),
    .mant_x_out(preproc_out.mant_x    ),
    .mant_y_out(preproc_out.mant_y    ),
    .exp_result(preproc_out.exp_result),
    .flags     (preproc_out.flags     )
);

// Pipeline slice between pre-process and ALU
hs_dpath_skid_buffer
#(
    .FULL_THROUGHPUT(BOOL_TRUE              ),
    .CTRL_PIPE      (BOOL_FALSE             ),
    .DATA_PIPE      (BOOL_TRUE              ),
    .STROBE_UNIT    ($bits(preproc_alu_dp_s)),
    .DATA_TYPE      (preproc_alu_dp_s       )
)
preproc_alu_pipe_inst
(
    .clk       (clk                 ),
    .aresetn   (aresetn             ),
    .in_data   (preproc_out         ),
    .in_valid  (op_valid            ),
    .in_last   ('0                  ),
    .in_ready  (op_ready            ),
    .in_strobe ('0                  ),
    .out_data  (alu_in              ),
    .out_valid (preproc_alu_hs_valid),
    .out_last  (                    ),
    .out_ready (preproc_alu_hs_ready),
    .out_strobe(                    )
);

// Stage II: ALU
hsf1_alu
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH)
)
alu_inst
(
    .mant_x_in      (alu_in.mant_x      ),
    .mant_y_in      (alu_in.mant_y      ),
    .exp_result_in  (alu_in.exp_result  ),
    .flags_in       (alu_in.flags       ),
    .exp_result_out (alu_out.exp_result ),
    .mant_result_out(alu_out.mant_result),
    .mant_lzc_out   (alu_out.lzc        ),
    .flags_out      (alu_out.flags      )
);

// Pipeline slice between ALU and post-process
hs_dpath_skid_buffer
#(

    .FULL_THROUGHPUT(BOOL_TRUE               ),
    .CTRL_PIPE      (BOOL_FALSE              ),
    .DATA_PIPE      (BOOL_TRUE               ),
    .STROBE_UNIT    ($bits(alu_postproc_dp_s)),
    .DATA_TYPE      (alu_postproc_dp_s       )
)
alu_postproc_pipe_inst
(
    .clk       (clk                  ),
    .aresetn   (aresetn              ),
    .in_data   (alu_out              ),
    .in_valid  (preproc_alu_hs_valid ),
    .in_last   ('0                   ),
    .in_ready  (preproc_alu_hs_ready ),
    .in_strobe ('0                   ),
    .out_data  (postproc_in          ),
    .out_valid (alu_postproc_hs_valid),
    .out_last  (                     ),
    .out_ready (alu_postproc_hs_ready),
    .out_strobe(                     )
);

// Stage III: Post-process
hsf1_postproc
#(
    .EXPONENT_WIDTH(EXPONENT_WIDTH),
    .MANTISSA_WIDTH(MANTISSA_WIDTH),
    .FP_ROUND_MODE (FP_ROUND_MODE )
)
postproc_inst
(
    .mant_in      (postproc_in.mant_result     ),
    .exp_in       (postproc_in.exp_result      ),
    .lzc_in       (postproc_in.lzc             ),
    .flags_in     (postproc_in.flags           ),
    .result_out   (postproc_out.result         ),
    .exception_out(postproc_out.exception_flags)
);

// Pipeline slice between post-process and output

hs_dpath_skid_buffer
#(

    .FULL_THROUGHPUT(BOOL_TRUE               ),
    .CTRL_PIPE      (BOOL_FALSE              ),
    .DATA_PIPE      (BOOL_TRUE               ),
    .STROBE_UNIT    ($bits(postproc_out_dp_s)),
    .DATA_TYPE      (postproc_out_dp_s       )
)
postproc_out_pipe_inst
(
    .clk       (clk                  ),
    .aresetn   (aresetn              ),
    .in_data   (postproc_out         ),
    .in_valid  (alu_postproc_hs_valid),
    .in_last   ('0                   ),
    .in_ready  (alu_postproc_hs_ready),
    .in_strobe ('0                   ),
    .out_data  (output_dp            ),
    .out_valid (result_valid         ),
    .out_last  (                     ),
    .out_ready (result_ready         ),
    .out_strobe(                     )
);

assign result_out    = output_dp.result;
assign exception_out = |output_dp.exception_flags;
assign nan_out       = output_dp.exception_flags.nan;
assign inf_out       = output_dp.exception_flags.inf;

endmodule : hsf1_fpadd_pipe