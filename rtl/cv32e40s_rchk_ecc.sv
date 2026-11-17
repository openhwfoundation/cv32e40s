// Copyright 2022 Silicon Labs, Inc.
//
// This file, and derivatives thereof are licensed under the
// Solderpad License, Version 2.0 (the "License").
//
// Use of this file means you agree to the terms and conditions
// of the license and are in full compliance with the License.
//
// You may obtain a copy of the License at:
//
//     https://solderpad.org/licenses/SHL-2.0/
//
// Unless required by applicable law or agreed to in writing, software
// and hardware implementations thereof distributed under the License
// is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESSED OR IMPLIED.
//
// See the License for the specific language governing permissions and
// limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Liam Salter - lps22@pitt.edu                               //
//                                                                            //
// Design Name:    cv32e40s_rchk_ecc                                          //
// Project Name:   CV32E40S                                                   //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    This module will perform SEC/DED ECC and signal an error   //
//                 if enabled and checksums do not match and the error is not //
//                 corrected                                                  //
//                 The corrected signal is asserted if a single-bit error is  //
//                 found and corrected                                        //
////////////////////////////////////////////////////////////////////////////////

module cv32e40s_rchk_ecc import cv32e40s_pkg::*;
#(
  parameter type RESP_TYPE = obi_data_resp_t
)
(
  input  RESP_TYPE   resp_i,
  input  logic [1:0] enable_i,
  output RESP_TYPE   resp_o,       // resp_i after correction
  output logic       corrected_o,  // single-bit error found and corrected
  output logic       err_o         // uncorrectable error detected
);

  localparam int unsigned DW = 33; // 32 rdata + 1 err

  // Parity matrix (7x33)
  localparam logic [6:0][DW-1:0] P = {
    33'h000003FFF,
    33'h000FFC00F,
    33'h03F03C0F0,
    33'h0C71C4711,
    33'h159649922,
    33'h1AAA92A44,
    33'h1F4D23488
  };

  logic [DW-1:0] data;
  logic [DW-1:0] data_match;     // syndrome matches column of high bit
  logic [DW-1:0] data_flip;      // corrected bit
  logic [   6:0] check_calc;
  logic [   6:0] syndrome;
  logic          check_en;
  logic          check_bit_err;  // error in a check bit

  assign check_en = enable_i[1] & resp_i.integrity;

  // rdata not used in stores
  assign data = {resp_i.err[0], (enable_i[0] ? resp_i.rdata : 32'h0)};

  // Recompute check bits
  for (genvar g = 0; g < 7; g++) begin : gen_check
    assign check_calc[g] = ^(data & P[g]);
  end

  assign syndrome = check_calc ^ resp_i.rchk[6:0];

  // Find the errored bit
  for (genvar g = 0; g < DW; g++) begin : gen_match
    logic [6:0] col;
    for (genvar h = 0; h < 7; h++) begin : gen_match_row
      assign col[h] = P[h][g];
    end
    assign data_match[g] = (syndrome == col);
  end

  assign data_flip = check_en ? (data_match & {1'b1, {32{enable_i[0]}}}) : '0;

  // Syndrome has one 1
  assign check_bit_err = check_en & (^syndrome) & (~|(syndrome & (syndrome - 7'd1)));

  always_comb begin : assign_resp_o
    resp_o = resp_i;
    resp_o.err[0] = resp_i.err[0] ^ data_flip[32];
    resp_o.rdata = resp_i.rdata ^ data_flip[31:0];
  end

  assign corrected_o = (|data_flip) | check_bit_err;

  // Error check enabled, syndrome nonzero, not corrected
  assign err_o = check_en & |syndrome & ~corrected_o;

endmodule
