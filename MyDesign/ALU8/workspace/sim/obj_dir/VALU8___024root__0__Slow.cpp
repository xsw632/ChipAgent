// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See VALU8.h for the primary calling header

#include "VALU8__pch.h"

VL_ATTR_COLD void VALU8___024root___eval_static(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_static\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void VALU8___024root___eval_initial(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_initial\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

VL_ATTR_COLD void VALU8___024root___eval_final(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_final\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void VALU8___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool VALU8___024root___eval_phase__stl(VALU8___024root* vlSelf);

VL_ATTR_COLD void VALU8___024root___eval_settle(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_settle\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            VALU8___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("/home/aa/snap/chipagent/ChipAgent/MyDesign/ALU8/workspace/generated/ALU8.v", 1, "", "DIDNOTCONVERGE: Settle region did not converge after '--converge-limit' of 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        vlSelfRef.__VstlPhaseResult = VALU8___024root___eval_phase__stl(vlSelf);
        vlSelfRef.__VstlFirstIteration = 0U;
    } while (vlSelfRef.__VstlPhaseResult);
}

VL_ATTR_COLD void VALU8___024root___eval_triggers_vec__stl(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_triggers_vec__stl\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered[0U]) 
                                     | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
}

VL_ATTR_COLD bool VALU8___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void VALU8___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(VALU8___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool VALU8___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___trigger_anySet__stl\n"); );
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

void VALU8___024root___ico_sequent__TOP__0(VALU8___024root* vlSelf);

VL_ATTR_COLD void VALU8___024root___eval_stl(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_stl\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        VALU8___024root___ico_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD bool VALU8___024root___eval_phase__stl(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___eval_phase__stl\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    VALU8___024root___eval_triggers_vec__stl(vlSelf);
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        VALU8___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
    __VstlExecute = VALU8___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        VALU8___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool VALU8___024root___trigger_anySet__ico(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void VALU8___024root___dump_triggers__ico(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ (IData)(VALU8___024root___trigger_anySet__ico(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void VALU8___024root___ctor_var_reset(VALU8___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    VALU8___024root___ctor_var_reset\n"); );
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->vlNamep);
    vlSelf->clock = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 5452235342940299466ull);
    vlSelf->reset = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9928399931838511862ull);
    vlSelf->io_inputA = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 1798633101215474224ull);
    vlSelf->io_inputB = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 9485757725118711349ull);
    vlSelf->io_op = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 2536292131817234354ull);
    vlSelf->io_result = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 3263675428409028133ull);
    vlSelf->io_zero = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 2566402247111658187ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VicoTriggered[__Vi0] = 0;
    }
}
