FIRRTL version 1.2.0
circuit Decoder3to8 :
  module Decoder3to8 :
    input clock : Clock
    input reset : UInt<1>
    output io : { flip in : UInt<3>, flip en : UInt<1>, out : UInt<8>} @[src/main/scala/chipagent/Decoder3to8.scala 6:14]

    node _io_out_T = dshl(UInt<1>("h1"), io.in) @[src/main/scala/chipagent/Decoder3to8.scala 12:28]
    node _io_out_T_1 = mux(io.en, _io_out_T, UInt<1>("h0")) @[src/main/scala/chipagent/Decoder3to8.scala 12:16]
    io.out <= _io_out_T_1 @[src/main/scala/chipagent/Decoder3to8.scala 12:10]

