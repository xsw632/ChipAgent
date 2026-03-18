val chiselVersion = "3.6.1"

lazy val root = (project in file("."))
  .settings(
    name := "chip-agent-chisel",
    version := "0.1.0",
    scalaVersion := "2.13.10",
    libraryDependencies ++= Seq(
      "edu.berkeley.cs" %% "chisel3" % chiselVersion
    ),
    addCompilerPlugin(
      "edu.berkeley.cs" % "chisel3-plugin" % chiselVersion
        cross CrossVersion.full
    )
  )
