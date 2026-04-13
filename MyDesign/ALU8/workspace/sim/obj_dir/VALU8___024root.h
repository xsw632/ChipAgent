// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See VALU8.h for the primary calling header

#ifndef VERILATED_VALU8___024ROOT_H_
#define VERILATED_VALU8___024ROOT_H_  // guard

#include "verilated.h"


class VALU8__Syms;

class alignas(VL_CACHE_LINE_BYTES) VALU8___024root final {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clock,0,0);
    VL_IN8(reset,0,0);
    VL_IN8(io_inputA,7,0);
    VL_IN8(io_inputB,7,0);
    VL_IN8(io_op,2,0);
    VL_OUT8(io_result,7,0);
    VL_OUT8(io_zero,0,0);
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VstlPhaseResult;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __VicoPhaseResult;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VicoTriggered;

    // INTERNAL VARIABLES
    VALU8__Syms* vlSymsp;
    const char* vlNamep;

    // CONSTRUCTORS
    VALU8___024root(VALU8__Syms* symsp, const char* namep);
    ~VALU8___024root();
    VL_UNCOPYABLE(VALU8___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
