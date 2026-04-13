// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VALU8.h for the primary calling header

#include "VALU8__pch.h"

void VALU8___024root___ctor_var_reset(VALU8___024root* vlSelf);

VALU8___024root::VALU8___024root(VALU8__Syms* symsp, const char* namep)
 {
    vlSymsp = symsp;
    vlNamep = strdup(namep);
    // Reset structure values
    VALU8___024root___ctor_var_reset(this);
}

void VALU8___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

VALU8___024root::~VALU8___024root() {
    VL_DO_DANGLING(std::free(const_cast<char*>(vlNamep)), vlNamep);
}
