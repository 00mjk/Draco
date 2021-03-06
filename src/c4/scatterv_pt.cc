//--------------------------------------------*-C++-*---------------------------------------------//
/*!
 * \file   c4/scatterv_pt.cc
 * \author Thomas M. Evans
 * \date   Mon Mar 25 14:44:54 2002
 * \brief  C4 MPI determinate and indeterminate scatterv instantiations.
 * \note   Copyright (C) 2016-2020 Triad National Security, LLC., All rights reserved. */
//------------------------------------------------------------------------------------------------//

#include "C4_Functions.hh"
#include "C4_Req.hh"
#include "scatterv.t.hh"
#include <c4/config.h>

namespace rtt_c4 {
using std::vector;

//------------------------------------------------------------------------------------------------//
// EXPLICIT INSTANTIATIONS OF NON-BLOCKING SEND/RECEIVE
//------------------------------------------------------------------------------------------------//

template DLL_PUBLIC_c4 void
indeterminate_scatterv(vector<vector<unsigned>> &outgoing_data,
                       vector<unsigned> &incoming_data);

template DLL_PUBLIC_c4 void
indeterminate_scatterv(vector<vector<int>> &outgoing_data,
                       vector<int> &incoming_data);

template DLL_PUBLIC_c4 void
indeterminate_scatterv(vector<vector<double>> &outgoing_data,
                       vector<double> &incoming_data);

//------------------------------------------------------------------------------------------------//

template DLL_PUBLIC_c4 void
determinate_scatterv(vector<vector<unsigned>> &outgoing_data,
                     vector<unsigned> &incoming_data);

template DLL_PUBLIC_c4 void
determinate_scatterv(vector<vector<int>> &outgoing_data,
                     vector<int> &incoming_data);

template DLL_PUBLIC_c4 void
determinate_scatterv(vector<vector<double>> &outgoing_data,
                     vector<double> &incoming_data);

} // end namespace rtt_c4

//------------------------------------------------------------------------------------------------//
// end of C4_MPI_scatterv_pt.cc
//------------------------------------------------------------------------------------------------//
