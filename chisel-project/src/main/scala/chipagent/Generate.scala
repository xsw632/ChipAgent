package chipagent

import chisel3._
import chisel3.stage.ChiselStage

object Generate extends App {
  val targetDir = if (args.contains("--target-dir")) {
    val idx = args.indexOf("--target-dir")
    args(idx + 1)
  } else {
    "../generated"
  }

  val moduleName = if (args.contains("--module")) {
    val idx = args.indexOf("--module")
    args(idx + 1)
  } else {
    "TrivialModule"
  }

  val module: () => Module = moduleName match {
    case "TrivialModule" => () => new TrivialModule
    case "ALU"           => () => new ALU
    case other => throw new IllegalArgumentException(s"Unknown module: $other. Available: TrivialModule, ALU")
  }

  (new ChiselStage).emitVerilog(
    module(),
    Array("--target-dir", targetDir)
  )
}
