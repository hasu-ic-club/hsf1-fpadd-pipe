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
// FILE NAME: hsf1_grs_lshift.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.2
// VERSION DESCRIPTION: Corner-cases fixed Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/27    First Edition
// 0.2        O. Tsusaki    2026/11/23    Fix the behaviour of the shifter 
//                                        when the data width is small
//-------------------------------------------------------------------------
// PURPOSE: Unsigned left shifter with GRS rounding bit recording
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// DATA_WIDTH          1-128       Shifted data width          24
// SFT_AMOUNT_WIDTH    1-128        Shift amount width         8
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Unsigned left shifter with GRS rounding bit recording
module hsf1_grs_lshift
import hsf1_typedef_pkg::*;
#(
    parameter int DATA_WIDTH       = 24,
    parameter int SFT_AMOUNT_WIDTH = 8
)
(
    input  grs_s                           grs_in,
    input  logic  [DATA_WIDTH - 1:0]       data_in,
    input  logic  [SFT_AMOUNT_WIDTH - 1:0] sft_in,

    output logic  [DATA_WIDTH - 1:0]       data_out,
    output grs_s                           grs_out
);


genvar                                      stg, idx;

// Total width includes original data width and guard, round bit
localparam int                              TOTAL_DWIDTH                          = DATA_WIDTH + 3;
localparam int                              SFT_STAGES                            = $clog2(TOTAL_DWIDTH);     // Barrel shifter stages
localparam int                              VLD_SFT_AMOUNT_WIDTH                  = $clog2(TOTAL_DWIDTH + 1); // Width of valid shift amount

// Valid shift amount
logic          [VLD_SFT_AMOUNT_WIDTH - 1:0] vld_sft;                                                          // Truncated shift amount to valid

// Barrel shifter stages
logic          [TOTAL_DWIDTH - 1:0]         bsft_data            [SFT_STAGES + 1];

// Valid shift amount truncate
// Fix on 0.2, the bit-width of sft-in may smaller than the VLD_SFT_AMOUNT_WIDTH
assign vld_sft          = VLD_SFT_AMOUNT_WIDTH'($unsigned(sft_in));

// Input layer
assign bsft_data[0] = {data_in, grs_in.guard, grs_in.round, grs_in.sticky};

// Barrel shifter
`GENERATE_START
for (stg = 0; stg < SFT_STAGES; stg++) begin : bsft_stage
    localparam int STAGE_SFT    = (1 << stg);

    logic stg_do_shift;   // Indicate current stage need to be shifted or not
    logic lossed_bits_or; // OR of shifted out bits in current stage

    assign stg_do_shift         = vld_sft[stg];

    // Barrel shifting
    for (idx = 0; idx < TOTAL_DWIDTH; idx++) begin : bsft_bits
        if (idx >= STAGE_SFT) begin
            // The shifted bit is still in the range of valid data
            assign bsft_data[stg + 1][idx] = stg_do_shift ? bsft_data[stg][idx - STAGE_SFT] : bsft_data[stg][idx];
        end
        else begin
            // Shift 0 in
            assign bsft_data[stg + 1][idx] = stg_do_shift ? '0 : bsft_data[stg][idx];
        end
    end : bsft_bits
end : bsft_stage
`GENERATE_END

// Final output
always_comb begin : sft_final_out
    data_out       = bsft_data[SFT_STAGES][3 +: DATA_WIDTH];
    grs_out.guard  = bsft_data[SFT_STAGES][2];
    grs_out.round  = bsft_data[SFT_STAGES][1];
    grs_out.sticky = bsft_data[SFT_STAGES][0];
end : sft_final_out

endmodule : hsf1_grs_lshift