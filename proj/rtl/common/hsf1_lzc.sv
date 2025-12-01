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
// FILE NAME: hsf1_lzc.sv
// AUTHOR:    Onodera Tsusaki
// EMAIL:     apertureelectronic@outlook.com
//-------------------------------------------------------------------------
// RELEASE VERSION: 0.1a0
// VERSION DESCRIPTION: First Edition
//-------------------------------------------------------------------------
// RELEASES:
// VERSION    AUTHOR        RELEASE DATE  DESCRIPTION
// 0.1a0      O. Tsusaki    2025/11/27    First Edition
//-------------------------------------------------------------------------
// PURPOSE: Leading zero counter for floating point adder
//
//-------------------------------------------------------------------------
// PARAMETERS:
// PARAMETER NAME      RANGE       DESCRIPTION                 DEFAULT VALUE
// N/A
//-FHDR--------------------------------------------------------------------

`include "hs_ifr_global.svh"

`ifndef USE_DEFAULT_NETTYPE_WIRE
`default_nettype none
`else
`default_nettype wire
`endif

// Leading zero counter for floating point adder
module hsf1_lzc
#(
    parameter  int DATA_WIDTH = 24,
    `LP_MODULE int LZC_WIDTH  = $clog2(DATA_WIDTH + 1)
)
(
    input  logic [DATA_WIDTH - 1:0] din,
    output logic [LZC_WIDTH - 1:0]  lzc,
    output logic                    all_zero
);

genvar         idx, lvl;

localparam int EXT_DWIDTH                                 = 1 << $clog2(DATA_WIDTH);
localparam int TREE_LEVEL                                 = $clog2(EXT_DWIDTH);
localparam int EXT_LZC_WIDTH                              = $clog2(EXT_DWIDTH + 1);

typedef logic [EXT_DWIDTH - 1:0]    ext_data_t;
typedef logic [EXT_LZC_WIDTH - 1:0] ext_lzc_t;

// Reversed 0 extended input
//              EXT DW    0
// Format like: 0000LXXXXXM
ext_data_t     din_ext_rev;

// Binary tree
logic          all_zero_lvl  [TREE_LEVEL + 1][EXT_DWIDTH];                          // all_zero_lvl[n][i]: indicate node i in level n is all zero
ext_lzc_t      lzc_lvl       [TREE_LEVEL + 1][EXT_DWIDTH];                          // lzc_lvl[n][i]:  number of leading zero(s) in node i in level n

// Extend input
`GENERATE_START
for (idx = 0; idx < EXT_DWIDTH; idx++) begin : gen_rev_extin
    if (idx < DATA_WIDTH) begin
        assign din_ext_rev[idx] = din[DATA_WIDTH - 1 - idx];
    end
    else begin
        assign din_ext_rev[idx] = 1'b0;
    end
end : gen_rev_extin
`GENERATE_END

// Input layer (layer 0, each node 1 bit)
`GENERATE_START
for (idx = 0; idx < EXT_DWIDTH; idx++) begin : gen_bt_leaf_lv0
    assign all_zero_lvl[0][idx] = ~din_ext_rev[idx];
    assign lzc_lvl[0][idx]      = din_ext_rev[idx] ? '0 : EXT_LZC_WIDTH'(1);
end : gen_bt_leaf_lv0
`GENERATE_END

// Binary tree merge (layer > 0)
`GENERATE_START
for (lvl = 1; lvl <= TREE_LEVEL; lvl++) begin : gen_bt_lvl
    localparam int NUM_NODES = EXT_DWIDTH >> lvl; // There are half number of nodes in next level
    localparam int OFFSET    = 1 << (lvl - 1);    // Length of each leaf node (left and right)

    for (idx = 0; idx < NUM_NODES; idx++) begin : gen_bt_leaf
        logic     all_zero_left;
        logic     all_zero_right;
        ext_lzc_t lzc_left;
        ext_lzc_t lzc_right;

        assign all_zero_left          = all_zero_lvl[lvl - 1][2 * idx];
        assign all_zero_right         = all_zero_lvl[lvl - 1][2 * idx + 1];
        assign lzc_left               = lzc_lvl[lvl - 1][2 * idx];
        assign lzc_right              = lzc_lvl[lvl - 1][2 * idx + 1];

        // All zeros flag
        assign all_zero_lvl[lvl][idx] = all_zero_left & all_zero_right;

        // If left node all zero, we can just add length of it to LZC
        assign lzc_lvl[lvl][idx]      = (all_zero_left) ? (OFFSET + lzc_right) : lzc_left;
    end : gen_bt_leaf
end : gen_bt_lvl
`GENERATE_END

// Output
assign lzc      = all_zero_lvl[TREE_LEVEL][0] ? LZC_WIDTH'(DATA_WIDTH) : lzc_lvl[TREE_LEVEL][0][LZC_WIDTH - 1:0];
assign all_zero = all_zero_lvl[TREE_LEVEL][0];

endmodule : hsf1_lzc