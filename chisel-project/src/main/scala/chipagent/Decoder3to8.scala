package chipagent

import chisel3._

class Decoder3to8 extends Module {
  val io = IO(new Bundle {
    val in  = Input(UInt(3.W))
    val en  = Input(Bool())
    val out = Output(UInt(8.W))
  })

  io.out := Mux(io.en, 1.U << io.in, 0.U)
}
