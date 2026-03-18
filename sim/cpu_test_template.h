#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>

// ============================================================================
// Section 1: RV32I Instruction Encoding Helpers
// ============================================================================

constexpr uint32_t r_type(uint32_t funct7, uint32_t rs2, uint32_t rs1,
                          uint32_t funct3, uint32_t rd,
                          uint32_t opcode = 0x33) {
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) |
           ((rd & 0x1F) << 7) | (opcode & 0x7F);
}

constexpr uint32_t i_type(uint32_t imm12, uint32_t rs1, uint32_t funct3,
                          uint32_t rd, uint32_t opcode) {
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) |
           ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F);
}

constexpr uint32_t s_type(uint32_t imm12, uint32_t rs2, uint32_t rs1,
                          uint32_t funct3, uint32_t opcode = 0x23) {
    uint32_t imm_11_5 = (imm12 >> 5) & 0x7F;
    uint32_t imm_4_0 = imm12 & 0x1F;
    return (imm_11_5 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) |
           ((funct3 & 0x7) << 12) | (imm_4_0 << 7) | (opcode & 0x7F);
}

constexpr uint32_t b_type(uint32_t imm13, uint32_t rs2, uint32_t rs1,
                          uint32_t funct3, uint32_t opcode = 0x63) {
    // imm13 layout: [12|10:5|4:1|11]
    uint32_t bit_12 = (imm13 >> 12) & 0x1;
    uint32_t bits_10_5 = (imm13 >> 5) & 0x3F;
    uint32_t bits_4_1 = (imm13 >> 1) & 0xF;
    uint32_t bit_11 = (imm13 >> 11) & 0x1;
    return (bit_12 << 31) | (bits_10_5 << 25) | ((rs2 & 0x1F) << 20) |
           ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) |
           (bits_4_1 << 8) | (bit_11 << 7) | (opcode & 0x7F);
}

constexpr uint32_t u_type(uint32_t imm20, uint32_t rd, uint32_t opcode) {
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F);
}

constexpr uint32_t j_type(uint32_t imm21, uint32_t rd,
                          uint32_t opcode = 0x6F) {
    // imm21 layout: [20|10:1|11|19:12]
    uint32_t bit_20 = (imm21 >> 20) & 0x1;
    uint32_t bits_10_1 = (imm21 >> 1) & 0x3FF;
    uint32_t bit_11 = (imm21 >> 11) & 0x1;
    uint32_t bits_19_12 = (imm21 >> 12) & 0xFF;
    return (bit_20 << 31) | (bits_10_1 << 21) | (bit_11 << 20) |
           (bits_19_12 << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F);
}

// -- Convenience aliases --

// R-type instructions (opcode 0x33)
constexpr uint32_t rv_add(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x0, rd);
}
constexpr uint32_t rv_sub(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x20, rs2, rs1, 0x0, rd);
}
constexpr uint32_t rv_and(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x7, rd);
}
constexpr uint32_t rv_or(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x6, rd);
}
constexpr uint32_t rv_xor(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x4, rd);
}
constexpr uint32_t rv_slt(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x2, rd);
}
constexpr uint32_t rv_sll(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x1, rd);
}
constexpr uint32_t rv_srl(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x00, rs2, rs1, 0x5, rd);
}
constexpr uint32_t rv_sra(uint32_t rd, uint32_t rs1, uint32_t rs2) {
    return r_type(0x20, rs2, rs1, 0x5, rd);
}

// I-type ALU instructions (opcode 0x13)
constexpr uint32_t rv_addi(uint32_t rd, uint32_t rs1, uint32_t imm) {
    return i_type(imm, rs1, 0x0, rd, 0x13);
}

// I-type Load instructions (opcode 0x03)
constexpr uint32_t rv_lw(uint32_t rd, uint32_t rs1, uint32_t imm) {
    return i_type(imm, rs1, 0x2, rd, 0x03);
}

// S-type Store instructions (opcode 0x23)
constexpr uint32_t rv_sw(uint32_t rs2, uint32_t rs1, uint32_t imm) {
    return s_type(imm, rs2, rs1, 0x2);
}

// B-type Branch instructions (opcode 0x63)
constexpr uint32_t rv_beq(uint32_t rs1, uint32_t rs2, uint32_t imm) {
    return b_type(imm, rs2, rs1, 0x0);
}
constexpr uint32_t rv_bne(uint32_t rs1, uint32_t rs2, uint32_t imm) {
    return b_type(imm, rs2, rs1, 0x1);
}

// U-type instructions
constexpr uint32_t rv_lui(uint32_t rd, uint32_t imm) {
    return u_type(imm, rd, 0x37);
}

// J-type instructions
constexpr uint32_t rv_jal(uint32_t rd, uint32_t imm) {
    return j_type(imm, rd);
}

// ============================================================================
// Section 2: Minimal RV32I Reference Emulator
// ============================================================================

struct RV32IState {
    uint32_t pc;
    uint32_t regs[32];
    uint8_t  mem[4096];
};

inline void rv32i_init(RV32IState& s) {
    s.pc = 0;
    memset(s.regs, 0, sizeof(s.regs));
    memset(s.mem, 0, sizeof(s.mem));
}

inline uint32_t rv32i_mem_read32(const RV32IState& s, uint32_t addr) {
    addr &= 0xFFC; // word-align, wrap to 4096
    return (uint32_t)s.mem[addr] |
           ((uint32_t)s.mem[addr + 1] << 8) |
           ((uint32_t)s.mem[addr + 2] << 16) |
           ((uint32_t)s.mem[addr + 3] << 24);
}

inline void rv32i_mem_write32(RV32IState& s, uint32_t addr, uint32_t val) {
    addr &= 0xFFC; // word-align, wrap to 4096
    s.mem[addr]     = (uint8_t)(val);
    s.mem[addr + 1] = (uint8_t)(val >> 8);
    s.mem[addr + 2] = (uint8_t)(val >> 16);
    s.mem[addr + 3] = (uint8_t)(val >> 24);
}

inline int32_t rv32i_sign_extend(uint32_t val, int bits) {
    uint32_t sign_bit = 1u << (bits - 1);
    return (int32_t)((val ^ sign_bit) - sign_bit);
}

inline void rv32i_step(RV32IState& s) {
    uint32_t inst = rv32i_mem_read32(s, s.pc);

    uint32_t opcode = inst & 0x7F;
    uint32_t rd     = (inst >> 7) & 0x1F;
    uint32_t funct3 = (inst >> 12) & 0x7;
    uint32_t rs1    = (inst >> 15) & 0x1F;
    uint32_t rs2    = (inst >> 20) & 0x1F;
    uint32_t funct7 = (inst >> 25) & 0x7F;

    // Immediate decoding
    int32_t imm_i = rv32i_sign_extend((inst >> 20) & 0xFFF, 12);
    int32_t imm_s = rv32i_sign_extend(((funct7 << 5) | (rd & 0x1F)), 12);
    int32_t imm_b = rv32i_sign_extend(
        (((inst >> 31) & 1) << 12) | (((inst >> 7) & 1) << 11) |
        (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1), 13);
    int32_t imm_u = (int32_t)(inst & 0xFFFFF000u);
    int32_t imm_j = rv32i_sign_extend(
        (((inst >> 31) & 1) << 20) | (((inst >> 12) & 0xFF) << 12) |
        (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1), 21);

    uint32_t rs1_val = s.regs[rs1];
    uint32_t rs2_val = s.regs[rs2];
    bool branch_taken = false;

    switch (opcode) {
    case 0x33: { // R-type
        uint32_t result = 0;
        switch (funct3) {
        case 0x0: result = (funct7 == 0x20) ? rs1_val - rs2_val : rs1_val + rs2_val; break;
        case 0x1: result = rs1_val << (rs2_val & 0x1F); break; // SLL
        case 0x2: result = ((int32_t)rs1_val < (int32_t)rs2_val) ? 1 : 0; break; // SLT
        case 0x3: result = (rs1_val < rs2_val) ? 1 : 0; break; // SLTU
        case 0x4: result = rs1_val ^ rs2_val; break;
        case 0x5: result = (funct7 == 0x20) ? (uint32_t)((int32_t)rs1_val >> (rs2_val & 0x1F))
                                             : rs1_val >> (rs2_val & 0x1F); break;
        case 0x6: result = rs1_val | rs2_val; break;
        case 0x7: result = rs1_val & rs2_val; break;
        }
        if (rd != 0) s.regs[rd] = result;
        break;
    }
    case 0x13: { // I-type ALU
        uint32_t result = 0;
        uint32_t shamt = rs2; // bits [24:20]
        switch (funct3) {
        case 0x0: result = rs1_val + (uint32_t)imm_i; break; // ADDI
        case 0x1: result = rs1_val << shamt; break; // SLLI
        case 0x2: result = ((int32_t)rs1_val < imm_i) ? 1 : 0; break; // SLTI
        case 0x3: result = (rs1_val < (uint32_t)imm_i) ? 1 : 0; break; // SLTIU
        case 0x4: result = rs1_val ^ (uint32_t)imm_i; break; // XORI
        case 0x5: result = (funct7 == 0x20) ? (uint32_t)((int32_t)rs1_val >> shamt)
                                             : rs1_val >> shamt; break; // SRLI/SRAI
        case 0x6: result = rs1_val | (uint32_t)imm_i; break; // ORI
        case 0x7: result = rs1_val & (uint32_t)imm_i; break; // ANDI
        }
        if (rd != 0) s.regs[rd] = result;
        break;
    }
    case 0x03: { // Load
        uint32_t addr = rs1_val + (uint32_t)imm_i;
        uint32_t result = 0;
        switch (funct3) {
        case 0x0: result = (uint32_t)rv32i_sign_extend(s.mem[addr & 0xFFF], 8); break; // LB
        case 0x1: result = (uint32_t)rv32i_sign_extend(
            (uint32_t)s.mem[addr & 0xFFF] | ((uint32_t)s.mem[(addr + 1) & 0xFFF] << 8), 16); break; // LH
        case 0x2: result = rv32i_mem_read32(s, addr); break; // LW
        case 0x4: result = s.mem[addr & 0xFFF]; break; // LBU
        case 0x5: result = (uint32_t)s.mem[addr & 0xFFF] | ((uint32_t)s.mem[(addr + 1) & 0xFFF] << 8); break; // LHU
        }
        if (rd != 0) s.regs[rd] = result;
        break;
    }
    case 0x23: { // Store
        uint32_t addr = rs1_val + (uint32_t)imm_s;
        switch (funct3) {
        case 0x0: s.mem[addr & 0xFFF] = (uint8_t)rs2_val; break; // SB
        case 0x1:
            s.mem[addr & 0xFFF] = (uint8_t)rs2_val;
            s.mem[(addr + 1) & 0xFFF] = (uint8_t)(rs2_val >> 8); break; // SH
        case 0x2: rv32i_mem_write32(s, addr, rs2_val); break; // SW
        }
        break;
    }
    case 0x63: { // B-type (Branch)
        switch (funct3) {
        case 0x0: branch_taken = (rs1_val == rs2_val); break; // BEQ
        case 0x1: branch_taken = (rs1_val != rs2_val); break; // BNE
        case 0x4: branch_taken = ((int32_t)rs1_val < (int32_t)rs2_val); break; // BLT
        case 0x5: branch_taken = ((int32_t)rs1_val >= (int32_t)rs2_val); break; // BGE
        case 0x6: branch_taken = (rs1_val < rs2_val); break; // BLTU
        case 0x7: branch_taken = (rs1_val >= rs2_val); break; // BGEU
        }
        if (branch_taken) {
            s.pc = (uint32_t)((int32_t)s.pc + imm_b);
            s.regs[0] = 0;
            return;
        }
        break;
    }
    case 0x37: // LUI
        if (rd != 0) s.regs[rd] = (uint32_t)imm_u;
        break;
    case 0x17: // AUIPC
        if (rd != 0) s.regs[rd] = s.pc + (uint32_t)imm_u;
        break;
    case 0x6F: // JAL
        if (rd != 0) s.regs[rd] = s.pc + 4;
        s.pc = (uint32_t)((int32_t)s.pc + imm_j);
        s.regs[0] = 0;
        return;
    case 0x67: // JALR
        if (rd != 0) s.regs[rd] = s.pc + 4;
        s.pc = (uint32_t)((int32_t)rs1_val + imm_i) & ~1u;
        s.regs[0] = 0;
        return;
    default:
        break;
    }

    s.pc += 4;
    s.regs[0] = 0; // x0 hardwired to zero
}

// ============================================================================
// Section 3: Testbench Comparison Helpers
// ============================================================================

struct CpuTestResult {
    int total;
    int pass;
    int fail;
};

inline void cpu_test_init(CpuTestResult& r) {
    r.total = 0;
    r.pass = 0;
    r.fail = 0;
}

inline bool cpu_check_reg(const char* test_name, int test_num,
                          uint32_t dut_val, uint32_t ref_val,
                          CpuTestResult& r) {
    r.total++;
    bool ok = (dut_val == ref_val);
    if (ok) {
        r.pass++;
    } else {
        r.fail++;
    }
    printf("[TEST %d] %s: dut=%u ref=%u | %s\n",
           test_num, test_name, dut_val, ref_val, ok ? "PASS" : "FAIL");
    return ok;
}

inline void cpu_test_report(const CpuTestResult& r) {
    printf("RESULT: %s %d/%d tests\n",
           (r.fail == 0) ? "PASSED" : "FAILED", r.pass, r.total);
}
