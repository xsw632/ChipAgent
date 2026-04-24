// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "VALU8__pch.h"
#include "verilated_vcd_c.h"

//============================================================
// Constructors

VALU8::VALU8(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new VALU8__Syms(contextp(), _vcname__, this)}
    , clock{vlSymsp->TOP.clock}
    , reset{vlSymsp->TOP.reset}
    , io_inputA{vlSymsp->TOP.io_inputA}
    , io_inputB{vlSymsp->TOP.io_inputB}
    , io_op{vlSymsp->TOP.io_op}
    , io_result{vlSymsp->TOP.io_result}
    , io_zero{vlSymsp->TOP.io_zero}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
    contextp()->traceBaseModelCbAdd(
        [this](VerilatedTraceBaseC* tfp, int levels, int options) { traceBaseModel(tfp, levels, options); });
}

VALU8::VALU8(const char* _vcname__)
    : VALU8(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

VALU8::~VALU8() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void VALU8___024root___eval_debug_assertions(VALU8___024root* vlSelf);
#endif  // VL_DEBUG
void VALU8___024root___eval_static(VALU8___024root* vlSelf);
void VALU8___024root___eval_initial(VALU8___024root* vlSelf);
void VALU8___024root___eval_settle(VALU8___024root* vlSelf);
void VALU8___024root___eval(VALU8___024root* vlSelf);

void VALU8::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate VALU8::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    VALU8___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_activity = true;
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        VALU8___024root___eval_static(&(vlSymsp->TOP));
        VALU8___024root___eval_initial(&(vlSymsp->TOP));
        VALU8___024root___eval_settle(&(vlSymsp->TOP));
        vlSymsp->__Vm_didInit = true;
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    VALU8___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool VALU8::eventsPending() { return false; }

uint64_t VALU8::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* VALU8::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void VALU8___024root___eval_final(VALU8___024root* vlSelf);

VL_ATTR_COLD void VALU8::final() {
    VALU8___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* VALU8::hierName() const { return vlSymsp->name(); }
const char* VALU8::modelName() const { return "VALU8"; }
unsigned VALU8::threads() const { return 1; }
void VALU8::prepareClone() const { contextp()->prepareClone(); }
void VALU8::atClone() const {
    contextp()->threadPoolpOnClone();
}
std::unique_ptr<VerilatedTraceConfig> VALU8::traceConfig() const {
    return std::unique_ptr<VerilatedTraceConfig>{new VerilatedTraceConfig{false, false, false}};
};

//============================================================
// Trace configuration

void VALU8___024root__trace_decl_types(VerilatedVcd* tracep);

void VALU8___024root__trace_init_top(VALU8___024root* vlSelf, VerilatedVcd* tracep);

VL_ATTR_COLD static void trace_init(void* voidSelf, VerilatedVcd* tracep, uint32_t code) {
    // Callback from tracep->open()
    VALU8___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<VALU8___024root*>(voidSelf);
    VALU8__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (!vlSymsp->_vm_contextp__->calcUnusedSigs()) {
        VL_FATAL_MT(__FILE__, __LINE__, __FILE__,
            "Turning on wave traces requires Verilated::traceEverOn(true) call before time 0.");
    }
    vlSymsp->__Vm_baseCode = code;
    tracep->pushPrefix(vlSymsp->name(), VerilatedTracePrefixType::SCOPE_MODULE);
    VALU8___024root__trace_decl_types(tracep);
    VALU8___024root__trace_init_top(vlSelf, tracep);
    tracep->popPrefix();
}

VL_ATTR_COLD void VALU8___024root__trace_register(VALU8___024root* vlSelf, VerilatedVcd* tracep);

VL_ATTR_COLD void VALU8::traceBaseModel(VerilatedTraceBaseC* tfp, int levels, int options) {
    (void)levels; (void)options;
    VerilatedVcdC* const stfp = dynamic_cast<VerilatedVcdC*>(tfp);
    if (VL_UNLIKELY(!stfp)) {
        vl_fatal(__FILE__, __LINE__, __FILE__,"'VALU8::trace()' called on non-VerilatedVcdC object;"
            " use --trace-fst with VerilatedFst object, and --trace-vcd with VerilatedVcd object");
    }
    stfp->spTrace()->addModel(this);
    stfp->spTrace()->addInitCb(&trace_init, &(vlSymsp->TOP), name(), false, 7);
    VALU8___024root__trace_register(&(vlSymsp->TOP), stfp->spTrace());
}
