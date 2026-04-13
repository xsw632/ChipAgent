// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VALU8.h for the primary calling header

#include "VALU8__pch.h"

void VALU8___024root___eval_triggers_vec__ico(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_triggers_vec__ico\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VicoTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VicoTriggered[0U]) 
                                     | (IData)((IData)(vlSelfRef.__VicoFirstIteration)));
}

bool VALU8___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___trigger_anySet__ico\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void VALU8___024root___ico_sequent__TOP__0(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___ico_sequent__TOP__0\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.io_result = (0x000000ffU & ((0U == (IData)(vlSelfRef.io_op))
                                           ? ((IData)(vlSelfRef.io_inputA) 
                                              + (IData)(vlSelfRef.io_inputB))
                                           : ((1U == (IData)(vlSelfRef.io_op))
                                               ? ((IData)(vlSelfRef.io_inputA) 
                                                  - (IData)(vlSelfRef.io_inputB))
                                               : ((2U 
                                                   == (IData)(vlSelfRef.io_op))
                                                   ? 
                                                  ((IData)(vlSelfRef.io_inputA) 
                                                   & (IData)(vlSelfRef.io_inputB))
                                                   : 
                                                  ((3U 
                                                    == (IData)(vlSelfRef.io_op))
                                                    ? 
                                                   ((IData)(vlSelfRef.io_inputA) 
                                                    | (IData)(vlSelfRef.io_inputB))
                                                    : 
                                                   ((4U 
                                                     == (IData)(vlSelfRef.io_op))
                                                     ? 
                                                    ((IData)(vlSelfRef.io_inputA) 
                                                     ^ (IData)(vlSelfRef.io_inputB))
                                                     : 
                                                    ((5U 
                                                      == (IData)(vlSelfRef.io_op)) 
                                                     & VL_LTS_III(8, (IData)(vlSelfRef.io_inputA), (IData)(vlSelfRef.io_inputB)))))))));
    vlSelfRef.io_zero = (0U == (IData)(vlSelfRef.io_result));
}

void VALU8___024root___eval_ico(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_ico\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VicoTriggered[0U])) {
        VALU8___024root___ico_sequent__TOP__0(vlSelf);
    }
}

#ifdef VL_DEBUG
VL_ATTR_COLD void VALU8___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

bool VALU8___024root___eval_phase__ico(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_phase__ico\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VicoExecute;
    // Body
    VALU8___024root___eval_triggers_vec__ico(vlSelf);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        VALU8___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
    }
#endif
    __VicoExecute = VALU8___024root___trigger_anySet__ico(vlSelfRef.__VicoTriggered);
    if (__VicoExecute) {
        VALU8___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

void VALU8___024root___eval(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VicoIterCount;
    // Body
    __VicoIterCount = 0U;
    vlSelfRef.__VicoFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VicoIterCount)))) {
#ifdef VL_DEBUG
            VALU8___024root___dump_triggers__ico(vlSelfRef.__VicoTriggered, "ico"s);
#endif
            VL_FATAL_MT("/home/aa/snap/chipagent/ChipAgent/MyDesign/ALU8/workspace/generated/ALU8.v", 1, "", "DIDNOTCONVERGE: Input combinational region did not converge after '--converge-limit' of 100 tries");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
        vlSelfRef.__VicoPhaseResult = VALU8___024root___eval_phase__ico(vlSelf);
        vlSelfRef.__VicoFirstIteration = 0U;
    } while (vlSelfRef.__VicoPhaseResult);
}

#ifdef VL_DEBUG
void VALU8___024root___eval_debug_assertions(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_debug_assertions\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if (VL_UNLIKELY(((vlSelfRef.clock & 0xfeU)))) {
        Verilated::overWidthError("clock");
    }
    if (VL_UNLIKELY(((vlSelfRef.reset & 0xfeU)))) {
        Verilated::overWidthError("reset");
    }
    if (VL_UNLIKELY(((vlSelfRef.io_op & 0xf8U)))) {
        Verilated::overWidthError("io_op");
    }
}
#endif  // VL_DEBUG
