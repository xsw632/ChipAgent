FIRRTL version 1.2.0
circuit ALU :
  module ALU :
    input clock : Clock
    input reset : UInt<1>
    output io : { flip a : UInt<32>, flip b : UInt<32>, flip op : UInt<3>, result : UInt<32>, zero : UInt<1>} @[src/main/scala/chipagent/ALU.scala 7:14]

    io.result <= UInt<1>("h0") @[src/main/scala/chipagent/ALU.scala 16:13]
    node _T = eq(UInt<1>("h0"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
    when _T : @[src/main/scala/chipagent/ALU.scala 18:17]
      node _io_result_T = add(io.a, io.b) @[src/main/scala/chipagent/ALU.scala 19:33]
      node _io_result_T_1 = tail(_io_result_T, 1) @[src/main/scala/chipagent/ALU.scala 19:33]
      io.result <= _io_result_T_1 @[src/main/scala/chipagent/ALU.scala 19:25]
    else :
      node _T_1 = eq(UInt<1>("h1"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
      when _T_1 : @[src/main/scala/chipagent/ALU.scala 18:17]
        node _io_result_T_2 = sub(io.a, io.b) @[src/main/scala/chipagent/ALU.scala 20:33]
        node _io_result_T_3 = tail(_io_result_T_2, 1) @[src/main/scala/chipagent/ALU.scala 20:33]
        io.result <= _io_result_T_3 @[src/main/scala/chipagent/ALU.scala 20:25]
      else :
        node _T_2 = eq(UInt<2>("h2"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
        when _T_2 : @[src/main/scala/chipagent/ALU.scala 18:17]
          node _io_result_T_4 = and(io.a, io.b) @[src/main/scala/chipagent/ALU.scala 21:33]
          io.result <= _io_result_T_4 @[src/main/scala/chipagent/ALU.scala 21:25]
        else :
          node _T_3 = eq(UInt<2>("h3"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
          when _T_3 : @[src/main/scala/chipagent/ALU.scala 18:17]
            node _io_result_T_5 = or(io.a, io.b) @[src/main/scala/chipagent/ALU.scala 22:33]
            io.result <= _io_result_T_5 @[src/main/scala/chipagent/ALU.scala 22:25]
          else :
            node _T_4 = eq(UInt<3>("h4"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
            when _T_4 : @[src/main/scala/chipagent/ALU.scala 18:17]
              node _io_result_T_6 = xor(io.a, io.b) @[src/main/scala/chipagent/ALU.scala 23:33]
              io.result <= _io_result_T_6 @[src/main/scala/chipagent/ALU.scala 23:25]
            else :
              node _T_5 = eq(UInt<3>("h5"), io.op) @[src/main/scala/chipagent/ALU.scala 18:17]
              when _T_5 : @[src/main/scala/chipagent/ALU.scala 18:17]
                node _io_result_T_7 = asSInt(io.a) @[src/main/scala/chipagent/ALU.scala 24:34]
                node _io_result_T_8 = asSInt(io.b) @[src/main/scala/chipagent/ALU.scala 24:48]
                node _io_result_T_9 = lt(_io_result_T_7, _io_result_T_8) @[src/main/scala/chipagent/ALU.scala 24:41]
                io.result <= _io_result_T_9 @[src/main/scala/chipagent/ALU.scala 24:25]
    node _io_zero_T = eq(io.result, UInt<1>("h0")) @[src/main/scala/chipagent/ALU.scala 27:24]
    io.zero <= _io_zero_T @[src/main/scala/chipagent/ALU.scala 27:11]

