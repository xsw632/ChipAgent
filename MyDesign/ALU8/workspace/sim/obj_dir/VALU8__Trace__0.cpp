// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals

#include "verilated_vcd_c.h"
#include "VALU8__Syms.h"


void VALU8___024root__trace_chg_0_sub_0(VALU8___024root* vlSelf, VerilatedVcd::Buffer* bufp);

void VALU8___024root__trace_chg_0(void* voidSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root__trace_chg_0\n"); );
    // Body
    VALU8___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<VALU8___024root*>(voidSelf);
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    VALU8___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void VALU8___024root__trace_chg_0_sub_0(VALU8___024root* vlSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root__trace_chg_0_sub_0\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 0);
    bufp->chgBit(oldp+0,(vlSelfRef.clock));
    bufp->chgBit(oldp+1,(vlSelfRef.reset));
    bufp->chgCData(oldp+2,(vlSelfRef.io_inputA),8);
    bufp->chgCData(oldp+3,(vlSelfRef.io_inputB),8);
    bufp->chgCData(oldp+4,(vlSelfRef.io_op),3);
    bufp->chgCData(oldp+5,(vlSelfRef.io_result),8);
    bufp->chgBit(oldp+6,(vlSelfRef.io_zero));
}

void VALU8___024root__trace_cleanup(void* voidSelf, VerilatedVcd* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root__trace_cleanup\n"); );
    // Locals
    VlUnpacked<CData/*0:0*/, 1> __Vm_traceActivity;
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        __Vm_traceActivity[__Vi0] = 0;
    }
    // Body
    VALU8___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<VALU8___024root*>(voidSelf);
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    vlSymsp->__Vm_activity = false;
    __Vm_traceActivity[0U] = 0U;
}
