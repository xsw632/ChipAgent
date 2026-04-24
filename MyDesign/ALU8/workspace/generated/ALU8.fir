FIRRTL version 1.2.0
circuit ALU8 :
  module ALU8 :
    input clock : Clock
    input reset : UInt<1>
    output io : { flip inputA : UInt<8>, flip inputB : UInt<8>, flip op : UInt<3>, result : UInt<8>, zero : UInt<1>} @[src/main/scala/chipagent/ALU8.scala 7:14]

    io.result <= UInt<1>("h0") @[src/main/scala/chipagent/ALU8.scala 16:13]
    io.zero <= UInt<1>("h0") @[src/main/scala/chipagent/ALU8.scala 17:11]
    node _T = eq(UInt<1>("h0"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
    when _T : @[src/main/scala/chipagent/ALU8.scala 20:17]
      node _io_result_T = add(io.inputA, io.inputB) @[src/main/scala/chipagent/ALU8.scala 21:38]
      node _io_result_T_1 = tail(_io_result_T, 1) @[src/main/scala/chipagent/ALU8.scala 21:38]
      io.result <= _io_result_T_1 @[src/main/scala/chipagent/ALU8.scala 21:25]
    else :
      node _T_1 = eq(UInt<1>("h1"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
      when _T_1 : @[src/main/scala/chipagent/ALU8.scala 20:17]
        node _io_result_T_2 = sub(io.inputA, io.inputB) @[src/main/scala/chipagent/ALU8.scala 22:38]
        node _io_result_T_3 = tail(_io_result_T_2, 1) @[src/main/scala/chipagent/ALU8.scala 22:38]
        io.result <= _io_result_T_3 @[src/main/scala/chipagent/ALU8.scala 22:25]
      else :
        node _T_2 = eq(UInt<2>("h2"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
        when _T_2 : @[src/main/scala/chipagent/ALU8.scala 20:17]
          node _io_result_T_4 = and(io.inputA, io.inputB) @[src/main/scala/chipagent/ALU8.scala 23:38]
          io.result <= _io_result_T_4 @[src/main/scala/chipagent/ALU8.scala 23:25]
        else :
          node _T_3 = eq(UInt<2>("h3"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
          when _T_3 : @[src/main/scala/chipagent/ALU8.scala 20:17]
            node _io_result_T_5 = or(io.inputA, io.inputB) @[src/main/scala/chipagent/ALU8.scala 24:38]
            io.result <= _io_result_T_5 @[src/main/scala/chipagent/ALU8.scala 24:25]
          else :
            node _T_4 = eq(UInt<3>("h4"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
            when _T_4 : @[src/main/scala/chipagent/ALU8.scala 20:17]
              node _io_result_T_6 = xor(io.inputA, io.inputB) @[src/main/scala/chipagent/ALU8.scala 25:38]
              io.result <= _io_result_T_6 @[src/main/scala/chipagent/ALU8.scala 25:25]
            else :
              node _T_5 = eq(UInt<3>("h5"), io.op) @[src/main/scala/chipagent/ALU8.scala 20:17]
              when _T_5 : @[src/main/scala/chipagent/ALU8.scala 20:17]
                node _io_result_T_7 = asSInt(io.inputA) @[src/main/scala/chipagent/ALU8.scala 26:39]
                node _io_result_T_8 = asSInt(io.inputB) @[src/main/scala/chipagent/ALU8.scala 26:58]
                node _io_result_T_9 = lt(_io_result_T_7, _io_result_T_8) @[src/main/scala/chipagent/ALU8.scala 26:46]
                io.result <= _io_result_T_9 @[src/main/scala/chipagent/ALU8.scala 26:25]
    node _io_zero_T = eq(io.result, UInt<1>("h0")) @[src/main/scala/chipagent/ALU8.scala 30:24]
    io.zero <= _io_zero_T @[src/main/scala/chipagent/ALU8.scala 30:11]

