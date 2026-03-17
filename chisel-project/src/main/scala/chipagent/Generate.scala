package chipagent

import chisel3._
import circt.stage.ChiselStage

object Generate extends App {
  val targetDir = if (args.contains("--target-dir")) {
    val idx = args.indexOf("--target-dir")
    args(idx + 1)
  } else {
    "../generated"
  }

  ChiselStage.emitSystemVerilogFile(
    new TrivialModule,
    Array("--target-dir", targetDir),
    Array("-disable-all-randomization", "-strip-debug-info")
  )
}
