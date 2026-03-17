package chipagent

import chisel3._
import chisel3.util._

class ALU extends Module {
  val io = IO(new Bundle {
    val a      = Input(UInt(32.W))
    val b      = Input(UInt(32.W))
    val op     = Input(UInt(3.W))
    val result = Output(UInt(32.W))
    val zero   = Output(Bool())
  })

  // Default assignments (prevents latch inference)
  io.result := 0.U

  switch(io.op) {
    is(0.U) { io.result := io.a + io.b }                           // ADD
    is(1.U) { io.result := io.a - io.b }                           // SUB
    is(2.U) { io.result := io.a & io.b }                           // AND
    is(3.U) { io.result := io.a | io.b }                           // OR
    is(4.U) { io.result := io.a ^ io.b }                           // XOR
    is(5.U) { io.result := (io.a.asSInt < io.b.asSInt).asUInt }   // SLT (signed)
  }

  io.zero := io.result === 0.U
}
