#include "VALU8.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>

struct TestCase {
    int op;
    uint8_t a, b, expected;
    const char* op_name;
};

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    VALU8* dut = new VALU8{ctx};

    // VCD tracing setup
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("trace.vcd");

    vluint64_t sim_time = 0;
    dut->clock = 0;
    dut->reset = 0;

    TestCase tests[] = {
        // ADD (op=0): a + b (8-bit wrap)
        {0, 5, 3, 8, "ADD"},
        {0, 0, 0, 0, "ADD"},
        {0, 255, 1, 0, "ADD"},           // overflow wrap
        {0, 128, 128, 0, "ADD"},         // overflow wrap

        // SUB (op=1): a - b (8-bit wrap)
        {1, 10, 3, 7, "SUB"},
        {1, 0, 1, 255, "SUB"},           // underflow wrap
        {1, 100, 100, 0, "SUB"},
        {1, 255, 255, 0, "SUB"},

        // AND (op=2): a & b
        {2, 0xFF, 0x0F, 0x0F, "AND"},
        {2, 0xAA, 0x55, 0x00, "AND"},
        {2, 0xFF, 0xFF, 0xFF, "AND"},
        {2, 0x00, 0xFF, 0x00, "AND"},

        // OR (op=3): a | b
        {3, 0xF0, 0x0F, 0xFF, "OR"},
        {3, 0xA0, 0x05, 0xA5, "OR"},
        {3, 0x00, 0x00, 0x00, "OR"},
        {3, 0xFF, 0x00, 0xFF, "OR"},

        // XOR (op=4): a ^ b
        {4, 0xFF, 0xFF, 0x00, "XOR"},
        {4, 0xAA, 0x55, 0xFF, "XOR"},
        {4, 0x00, 0x00, 0x00, "XOR"},
        {4, 0x0F, 0xF0, 0xFF, "XOR"},

        // SLT (op=5): signed(a) < signed(b) ? 1 : 0
        // 8-bit signed: 0x80=-128, 0x7F=127, 0xFF=-1
        {5, 1, 2, 1, "SLT"},             // 1 < 2 = true
        {5, 2, 1, 0, "SLT"},             // 2 < 1 = false
        {5, 0xFF, 0, 1, "SLT"},          // -1 < 0 = true
        {5, 0, 0xFF, 0, "SLT"},          // 0 < -1 = false
        {5, 0x80, 0x7F, 1, "SLT"},       // -128 < 127 = true
        {5, 5, 5, 0, "SLT"},             // 5 < 5 = false (equal)
    };

    int total = sizeof(tests) / sizeof(tests[0]);
    int pass = 0;

    for (int i = 0; i < total; i++) {
        dut->io_op = tests[i].op;
        dut->io_inputA = tests[i].a;
        dut->io_inputB = tests[i].b;
        dut->eval();

        // Dump VCD at this test's timestamp
        tfp->dump(sim_time);
        sim_time++;

        uint8_t got = dut->io_result;
        bool ok = (got == tests[i].expected);
        if (ok) pass++;

        printf("[TEST %d] %s: a=%u b=%u | expect=%u got=%u | %s\n",
               i + 1, tests[i].op_name,
               (unsigned)tests[i].a, (unsigned)tests[i].b,
               (unsigned)tests[i].expected, (unsigned)got,
               ok ? "PASS" : "FAIL");
    }

    printf("RESULT: %s %d/%d tests\n",
           (pass == total) ? "PASSED" : "FAILED", pass, total);

    tfp->close();
    dut->final();
    delete dut;
    delete ctx;
    delete tfp;

    return (pass == total) ? 0 : 1;
}
