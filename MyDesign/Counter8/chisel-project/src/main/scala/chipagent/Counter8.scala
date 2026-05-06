package chipagent

import chisel3._

class Counter8 extends Module {
  val io = IO(new Bundle {
    val count = Output(UInt(8.W))
  })
  val reg = RegInit(0.U(8.W))
  reg := reg + 1.U
  io.count := reg
}
