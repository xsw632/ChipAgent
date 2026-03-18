FIRRTL version 1.2.0
circuit TrivialModule :
  module TrivialModule :
    input clock : Clock
    input reset : UInt<1>
    output io : { flip in : UInt<8>, out : UInt<8>} @[src/main/scala/chipagent/TrivialModule.scala 6:14]

    io.out <= io.in @[src/main/scala/chipagent/TrivialModule.scala 10:10]

