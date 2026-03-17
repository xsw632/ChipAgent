val chiselVersion = "7.2.0"

lazy val root = (project in file("."))
  .settings(
    name := "chip-agent-chisel",
    version := "0.1.0",
    scalaVersion := "2.13.16",
    libraryDependencies ++= Seq(
      "org.chipsalliance" %% "chisel" % chiselVersion
    ),
    addCompilerPlugin(
      "org.chipsalliance" % "chisel-plugin" % chiselVersion
        cross CrossVersion.full
    )
  )
