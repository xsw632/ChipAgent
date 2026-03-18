#include "VDecoder3to8.h"
#include "verilated.h"
#include <cstdio>

struct TestCase {
    uint8_t in;
    uint8_t en;
    uint8_t expected;
    const char* desc;
};

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    VDecoder3to8* dut = new VDecoder3to8{ctx};

    dut->clock = 0;
    dut->reset = 0;

    TestCase tests[] = {
        // Enable=1: out = 1 << in
        {0, 1, 0x01, "en=1 in=0"},
        {1, 1, 0x02, "en=1 in=1"},
        {2, 1, 0x04, "en=1 in=2"},
        {3, 1, 0x08, "en=1 in=3"},
        {4, 1, 0x10, "en=1 in=4"},
        {5, 1, 0x20, "en=1 in=5"},
        {6, 1, 0x40, "en=1 in=6"},
        {7, 1, 0x80, "en=1 in=7"},
        // Enable=0: out = 0
        {0, 0, 0x00, "en=0 in=0"},
        {3, 0, 0x00, "en=0 in=3"},
        {7, 0, 0x00, "en=0 in=7"},
    };

    int total = sizeof(tests) / sizeof(tests[0]);
    int pass = 0;

    for (int i = 0; i < total; i++) {
        dut->io_in = tests[i].in;
        dut->io_en = tests[i].en;
        dut->eval();

        uint8_t got = dut->io_out;
        bool ok = (got == tests[i].expected);
        if (ok) pass++;

        printf("[TEST %d] %s | expect=0x%02X got=0x%02X | %s\n",
               i + 1, tests[i].desc, tests[i].expected, got,
               ok ? "PASS" : "FAIL");
    }

    printf("RESULT: %s %d/%d tests\n",
           (pass == total) ? "PASSED" : "FAILED", pass, total);

    dut->final();
    delete dut;
    delete ctx;

    return (pass == total) ? 0 : 1;
}
