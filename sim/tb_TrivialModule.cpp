#include "VTrivialModule.h"
#include "verilated.h"
#include <cstdio>
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  VTrivialModule* top = new VTrivialModule;
  top->clock = 0;
  top->reset = 0;
  top->io_in = 42;
  top->eval();
  int pass = (top->io_out == 42);
  printf("[TEST 1] PASSTHROUGH: in=42 | expect=42 got=%d | %s\n",
         top->io_out, pass ? "PASS" : "FAIL");
  top->final();
  delete top;
  return pass ? 0 : 1;
}
