#include "VALU.h"
#include "verilated.h"
#include <cstdio>

struct TestCase {
    int op;
    uint32_t a, b, expected;
    const char* op_name;
};

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    VALU* dut = new VALU{ctx};

    dut->clock = 0;
    dut->reset = 0;

    TestCase tests[] = {
        // ADD (op=0): io_a + io_b
        {0, 5, 3, 8, "ADD"},
        {0, 0xFFFFFFFF, 1, 0, "ADD"},

        // SUB (op=1): io_a - io_b
        {1, 10, 3, 7, "SUB"},
        {1, 0, 1, 0xFFFFFFFF, "SUB"},

        // AND (op=2): io_a & io_b
        {2, 0xFF00FF00, 0x0F0F0F0F, 0x0F000F00, "AND"},
        {2, 0xAAAAAAAA, 0x55555555, 0x00000000, "AND"},

        // OR (op=3): io_a | io_b
        {3, 0xFF00, 0x00FF, 0xFFFF, "OR"},
        {3, 0xA0A0A0A0, 0x05050505, 0xA5A5A5A5, "OR"},

        // XOR (op=4): io_a ^ io_b
        {4, 0xFF, 0xFF, 0x00, "XOR"},
        {4, 0xAAAAAAAA, 0x55555555, 0xFFFFFFFF, "XOR"},

        // SLT (op=5): signed(io_a) < signed(io_b) ? 1 : 0
        {5, 1, 2, 1, "SLT"},
        {5, 0xFFFFFFFF, 0, 1, "SLT"},
    };

    int total = sizeof(tests) / sizeof(tests[0]);
    int pass = 0;

    for (int i = 0; i < total; i++) {
        dut->io_op = tests[i].op;
        dut->io_a = tests[i].a;
        dut->io_b = tests[i].b;
        dut->eval();

        uint32_t got = dut->io_result;
        bool ok = (got == tests[i].expected);
        if (ok) pass++;

        printf("[TEST %d] %s: a=%u b=%u | expect=%u got=%u | %s\n",
               i + 1, tests[i].op_name, tests[i].a, tests[i].b,
               tests[i].expected, got, ok ? "PASS" : "FAIL");
    }

    printf("RESULT: %s %d/%d tests\n",
           (pass == total) ? "PASSED" : "FAILED", pass, total);

    dut->final();
    delete dut;
    delete ctx;

    return (pass == total) ? 0 : 1;
}
