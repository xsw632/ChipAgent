// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VALU8__SYMS_H_
#define VERILATED_VALU8__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "VALU8.h"

// INCLUDE MODULE CLASSES
#include "VALU8___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES) VALU8__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    VALU8* const __Vm_modelp;
    bool __Vm_activity = false;  ///< Used by trace routines to determine change occurred
    uint32_t __Vm_baseCode = 0;  ///< Used by trace routines when tracing multiple models
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    VALU8___024root                TOP;

    // CONSTRUCTORS
    VALU8__Syms(VerilatedContext* contextp, const char* namep, VALU8* modelp);
    ~VALU8__Syms();

    // METHODS
    const char* name() const { return TOP.vlNamep; }
};

#endif  // guard
