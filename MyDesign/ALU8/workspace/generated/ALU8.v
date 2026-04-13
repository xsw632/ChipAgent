module ALU8(
  input        clock,
  input        reset,
  input  [7:0] io_inputA, // @[src/main/scala/chipagent/ALU8.scala 7:14]
  input  [7:0] io_inputB, // @[src/main/scala/chipagent/ALU8.scala 7:14]
  input  [2:0] io_op, // @[src/main/scala/chipagent/ALU8.scala 7:14]
  output [7:0] io_result, // @[src/main/scala/chipagent/ALU8.scala 7:14]
  output       io_zero // @[src/main/scala/chipagent/ALU8.scala 7:14]
);
  wire [7:0] _io_result_T_1 = io_inputA + io_inputB; // @[src/main/scala/chipagent/ALU8.scala 21:38]
  wire [7:0] _io_result_T_3 = io_inputA - io_inputB; // @[src/main/scala/chipagent/ALU8.scala 22:38]
  wire [7:0] _io_result_T_4 = io_inputA & io_inputB; // @[src/main/scala/chipagent/ALU8.scala 23:38]
  wire [7:0] _io_result_T_5 = io_inputA | io_inputB; // @[src/main/scala/chipagent/ALU8.scala 24:38]
  wire [7:0] _io_result_T_6 = io_inputA ^ io_inputB; // @[src/main/scala/chipagent/ALU8.scala 25:38]
  wire  _GEN_0 = 3'h5 == io_op & $signed(io_inputA) < $signed(io_inputB); // @[src/main/scala/chipagent/ALU8.scala 16:13 20:17 26:25]
  wire [7:0] _GEN_1 = 3'h4 == io_op ? _io_result_T_6 : {{7'd0}, _GEN_0}; // @[src/main/scala/chipagent/ALU8.scala 20:17 25:25]
  wire [7:0] _GEN_2 = 3'h3 == io_op ? _io_result_T_5 : _GEN_1; // @[src/main/scala/chipagent/ALU8.scala 20:17 24:25]
  wire [7:0] _GEN_3 = 3'h2 == io_op ? _io_result_T_4 : _GEN_2; // @[src/main/scala/chipagent/ALU8.scala 20:17 23:25]
  wire [7:0] _GEN_4 = 3'h1 == io_op ? _io_result_T_3 : _GEN_3; // @[src/main/scala/chipagent/ALU8.scala 20:17 22:25]
  assign io_result = 3'h0 == io_op ? _io_result_T_1 : _GEN_4; // @[src/main/scala/chipagent/ALU8.scala 20:17 21:25]
  assign io_zero = io_result == 8'h0; // @[src/main/scala/chipagent/ALU8.scala 30:24]
endmodule
