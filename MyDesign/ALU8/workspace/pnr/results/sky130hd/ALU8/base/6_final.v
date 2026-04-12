module ALU8 (clock,
    io_zero,
    reset,
    io_inputA,
    io_inputB,
    io_op,
    io_result);
 input clock;
 output io_zero;
 input reset;
 input [7:0] io_inputA;
 input [7:0] io_inputB;
 input [2:0] io_op;
 output [7:0] io_result;

 wire _000_;
 wire _001_;
 wire _002_;
 wire _003_;
 wire _004_;
 wire _005_;
 wire _006_;
 wire _007_;
 wire _008_;
 wire _009_;
 wire _010_;
 wire _011_;
 wire _012_;
 wire _013_;
 wire _014_;
 wire _015_;
 wire _016_;
 wire _017_;
 wire _018_;
 wire _019_;
 wire _020_;
 wire _021_;
 wire _022_;
 wire _023_;
 wire _024_;
 wire _025_;
 wire _026_;
 wire _027_;
 wire _028_;
 wire _029_;
 wire _030_;
 wire _031_;
 wire _032_;
 wire _033_;
 wire _034_;
 wire _035_;
 wire _036_;
 wire _037_;
 wire _038_;
 wire _039_;
 wire _040_;
 wire _041_;
 wire _042_;
 wire _043_;
 wire _044_;
 wire _045_;
 wire _046_;
 wire _047_;
 wire _048_;
 wire _049_;
 wire _050_;
 wire _051_;
 wire _052_;
 wire _053_;
 wire _056_;
 wire _057_;
 wire _059_;
 wire _061_;
 wire _064_;
 wire _065_;
 wire _066_;
 wire _067_;
 wire _068_;
 wire _069_;
 wire _071_;
 wire _072_;
 wire _073_;
 wire _075_;
 wire _077_;
 wire _078_;
 wire _079_;
 wire _080_;
 wire _081_;
 wire _082_;
 wire _083_;
 wire _084_;
 wire _085_;
 wire _086_;
 wire _087_;
 wire _088_;
 wire _089_;
 wire _090_;
 wire _091_;
 wire _092_;
 wire _093_;
 wire _094_;
 wire _095_;
 wire _096_;
 wire _097_;
 wire _098_;
 wire _099_;
 wire _100_;
 wire _101_;
 wire _102_;
 wire _103_;
 wire _104_;
 wire _105_;
 wire _106_;
 wire _107_;
 wire _108_;
 wire _109_;
 wire _110_;
 wire _111_;
 wire _112_;
 wire _113_;
 wire _114_;
 wire _115_;
 wire _116_;
 wire _117_;
 wire _118_;
 wire _119_;
 wire _120_;
 wire _121_;
 wire _122_;
 wire _123_;
 wire _124_;
 wire _125_;
 wire _126_;
 wire _127_;
 wire _128_;
 wire _129_;
 wire _130_;
 wire _131_;
 wire _132_;
 wire _133_;
 wire _134_;
 wire _135_;
 wire _136_;
 wire _137_;
 wire _138_;
 wire _139_;
 wire _140_;
 wire _141_;
 wire _142_;
 wire _143_;
 wire _144_;
 wire _145_;
 wire _146_;
 wire _147_;
 wire _148_;
 wire _149_;
 wire _150_;
 wire _151_;
 wire _152_;
 wire _153_;
 wire _154_;
 wire _155_;
 wire _156_;
 wire _157_;
 wire _158_;
 wire _159_;
 wire _160_;
 wire _161_;
 wire _162_;
 wire _163_;
 wire _164_;
 wire _165_;
 wire _166_;
 wire _167_;
 wire _168_;
 wire _169_;
 wire _170_;
 wire _171_;
 wire _172_;
 wire _173_;
 wire _174_;
 wire _175_;
 wire _176_;
 wire _177_;
 wire _178_;
 wire _179_;
 wire _180_;
 wire _181_;
 wire _183_;
 wire _184_;
 wire _185_;
 wire _186_;
 wire _187_;
 wire _188_;
 wire _189_;
 wire _190_;
 wire _191_;
 wire _192_;
 wire _193_;
 wire _194_;
 wire _195_;
 wire _196_;
 wire _197_;
 wire _198_;
 wire _199_;
 wire net1;
 wire net2;
 wire net3;
 wire net4;
 wire net5;
 wire net6;
 wire net7;
 wire net8;
 wire net9;
 wire net10;
 wire net11;
 wire net12;
 wire net13;
 wire net14;
 wire net15;
 wire net16;
 wire net17;
 wire net18;
 wire net19;
 wire net20;
 wire net21;
 wire net22;
 wire net23;
 wire net24;
 wire net25;
 wire net26;
 wire net27;
 wire net28;
 wire net29;

 sky130_fd_sc_hd__inv_1 _200_ (.A(net12),
    .Y(_037_));
 sky130_fd_sc_hd__inv_1 _201_ (.A(net10),
    .Y(_001_));
 sky130_fd_sc_hd__inv_1 _202_ (.A(net6),
    .Y(_048_));
 sky130_fd_sc_hd__inv_1 _203_ (.A(net2),
    .Y(_000_));
 sky130_fd_sc_hd__inv_1 _204_ (.A(_047_),
    .Y(_002_));
 sky130_fd_sc_hd__inv_1 _205_ (.A(net1),
    .Y(_042_));
 sky130_fd_sc_hd__inv_1 _206_ (.A(net13),
    .Y(_013_));
 sky130_fd_sc_hd__inv_1 _207_ (.A(net14),
    .Y(_049_));
 sky130_fd_sc_hd__inv_1 _208_ (.A(net4),
    .Y(_036_));
 sky130_fd_sc_hd__inv_1 _209_ (.A(net16),
    .Y(_031_));
 sky130_fd_sc_hd__inv_1 _210_ (.A(net8),
    .Y(_030_));
 sky130_fd_sc_hd__inv_1 _211_ (.A(net9),
    .Y(_043_));
 sky130_fd_sc_hd__inv_1 _212_ (.A(net15),
    .Y(_025_));
 sky130_fd_sc_hd__inv_1 _213_ (.A(net5),
    .Y(_012_));
 sky130_fd_sc_hd__inv_1 _214_ (.A(net7),
    .Y(_024_));
 sky130_fd_sc_hd__inv_1 _216_ (.A(_053_),
    .Y(_183_));
 sky130_fd_sc_hd__a21o_1 _219_ (.A1(_041_),
    .A2(_015_),
    .B1(_017_),
    .X(_056_));
 sky130_fd_sc_hd__nand2_1 _220_ (.A(_051_),
    .B(_056_),
    .Y(_057_));
 sky130_fd_sc_hd__nor2b_1 _222_ (.A(_003_),
    .B_N(_021_),
    .Y(_059_));
 sky130_fd_sc_hd__o2111ai_1 _224_ (.A1(_023_),
    .A2(_059_),
    .B1(_051_),
    .C1(_039_),
    .D1(_015_),
    .Y(_061_));
 sky130_fd_sc_hd__nor2_1 _227_ (.A(net18),
    .B(net29),
    .Y(_064_));
 sky130_fd_sc_hd__nand4_1 _228_ (.A(_183_),
    .B(_057_),
    .C(_061_),
    .D(_064_),
    .Y(_065_));
 sky130_fd_sc_hd__nor2b_1 _229_ (.A(_026_),
    .B_N(net29),
    .Y(_066_));
 sky130_fd_sc_hd__nor2b_1 _230_ (.A(net29),
    .B_N(_029_),
    .Y(_067_));
 sky130_fd_sc_hd__nor2b_1 _231_ (.A(net19),
    .B_N(net18),
    .Y(_068_));
 sky130_fd_sc_hd__o21ai_1 _232_ (.A1(_066_),
    .A2(_067_),
    .B1(_068_),
    .Y(_069_));
 sky130_fd_sc_hd__nand2_1 _234_ (.A(net19),
    .B(_064_),
    .Y(_071_));
 sky130_fd_sc_hd__and4_1 _235_ (.A(_027_),
    .B(_065_),
    .C(_069_),
    .D(_071_),
    .X(_072_));
 sky130_fd_sc_hd__nand2_1 _236_ (.A(_057_),
    .B(_061_),
    .Y(_073_));
 sky130_fd_sc_hd__nor3_1 _238_ (.A(net19),
    .B(net18),
    .C(net29),
    .Y(_075_));
 sky130_fd_sc_hd__nor2_2 _240_ (.A(net19),
    .B(net18),
    .Y(_077_));
 sky130_fd_sc_hd__nand2_1 _241_ (.A(net29),
    .B(_077_),
    .Y(_078_));
 sky130_fd_sc_hd__nor3b_2 _242_ (.A(_039_),
    .B(_021_),
    .C_N(_006_),
    .Y(_079_));
 sky130_fd_sc_hd__nor2b_1 _243_ (.A(_039_),
    .B_N(_022_),
    .Y(_080_));
 sky130_fd_sc_hd__inv_1 _244_ (.A(_015_),
    .Y(_081_));
 sky130_fd_sc_hd__o31a_2 _245_ (.A1(_040_),
    .A2(_079_),
    .A3(_080_),
    .B1(_081_),
    .X(_082_));
 sky130_fd_sc_hd__nor4_1 _246_ (.A(_052_),
    .B(_016_),
    .C(_078_),
    .D(_082_),
    .Y(_083_));
 sky130_fd_sc_hd__inv_1 _247_ (.A(_051_),
    .Y(_084_));
 sky130_fd_sc_hd__nor4b_1 _248_ (.A(net19),
    .B(net18),
    .C(net29),
    .D_N(_053_),
    .Y(_085_));
 sky130_fd_sc_hd__nor2_1 _249_ (.A(_027_),
    .B(_085_),
    .Y(_086_));
 sky130_fd_sc_hd__o311ai_1 _250_ (.A1(_084_),
    .A2(_052_),
    .A3(_078_),
    .B1(_086_),
    .C1(_069_),
    .Y(_087_));
 sky130_fd_sc_hd__a211oi_1 _251_ (.A1(_073_),
    .A2(_075_),
    .B1(_083_),
    .C1(_087_),
    .Y(_088_));
 sky130_fd_sc_hd__inv_1 _252_ (.A(_052_),
    .Y(_089_));
 sky130_fd_sc_hd__o21ai_0 _253_ (.A1(_016_),
    .A2(_082_),
    .B1(_084_),
    .Y(_090_));
 sky130_fd_sc_hd__and2_1 _254_ (.A(_089_),
    .B(_090_),
    .X(_091_));
 sky130_fd_sc_hd__nand3_1 _255_ (.A(net29),
    .B(_077_),
    .C(_087_),
    .Y(_092_));
 sky130_fd_sc_hd__o22ai_1 _256_ (.A1(_072_),
    .A2(_088_),
    .B1(_091_),
    .B2(_092_),
    .Y(net26));
 sky130_fd_sc_hd__inv_1 _257_ (.A(_046_),
    .Y(_005_));
 sky130_fd_sc_hd__inv_1 _258_ (.A(net11),
    .Y(_019_));
 sky130_fd_sc_hd__inv_1 _259_ (.A(_029_),
    .Y(_093_));
 sky130_fd_sc_hd__a21o_1 _260_ (.A1(_039_),
    .A2(_023_),
    .B1(_041_),
    .X(_094_));
 sky130_fd_sc_hd__a21oi_1 _261_ (.A1(_015_),
    .A2(_094_),
    .B1(_017_),
    .Y(_095_));
 sky130_fd_sc_hd__a21o_1 _262_ (.A1(_009_),
    .A2(_047_),
    .B1(_011_),
    .X(_096_));
 sky130_fd_sc_hd__nand4_1 _263_ (.A(_039_),
    .B(_015_),
    .C(_021_),
    .D(_096_),
    .Y(_097_));
 sky130_fd_sc_hd__o21ai_0 _264_ (.A1(_053_),
    .A2(_051_),
    .B1(_027_),
    .Y(_098_));
 sky130_fd_sc_hd__a31o_2 _265_ (.A1(_183_),
    .A2(_095_),
    .A3(_097_),
    .B1(_098_),
    .X(_099_));
 sky130_fd_sc_hd__nor2b_1 _266_ (.A(_032_),
    .B_N(net29),
    .Y(_100_));
 sky130_fd_sc_hd__nor2b_1 _267_ (.A(net29),
    .B_N(_035_),
    .Y(_101_));
 sky130_fd_sc_hd__o21ai_0 _268_ (.A1(_100_),
    .A2(_101_),
    .B1(_068_),
    .Y(_102_));
 sky130_fd_sc_hd__nand3_1 _269_ (.A(_033_),
    .B(_071_),
    .C(_102_),
    .Y(_103_));
 sky130_fd_sc_hd__a31oi_1 _270_ (.A1(_093_),
    .A2(_075_),
    .A3(_099_),
    .B1(_103_),
    .Y(_104_));
 sky130_fd_sc_hd__nand2_1 _271_ (.A(_095_),
    .B(_097_),
    .Y(_105_));
 sky130_fd_sc_hd__nand2_1 _272_ (.A(_029_),
    .B(_075_),
    .Y(_106_));
 sky130_fd_sc_hd__a21oi_1 _273_ (.A1(_027_),
    .A2(_085_),
    .B1(_033_),
    .Y(_107_));
 sky130_fd_sc_hd__nand3_1 _274_ (.A(_102_),
    .B(_106_),
    .C(_107_),
    .Y(_108_));
 sky130_fd_sc_hd__a41oi_1 _275_ (.A1(_051_),
    .A2(_027_),
    .A3(_075_),
    .A4(_105_),
    .B1(_108_),
    .Y(_109_));
 sky130_fd_sc_hd__inv_2 _276_ (.A(net29),
    .Y(_110_));
 sky130_fd_sc_hd__inv_1 _277_ (.A(net19),
    .Y(_111_));
 sky130_fd_sc_hd__inv_1 _278_ (.A(net18),
    .Y(_112_));
 sky130_fd_sc_hd__nand2_1 _279_ (.A(_111_),
    .B(_112_),
    .Y(_113_));
 sky130_fd_sc_hd__nor2_1 _280_ (.A(_009_),
    .B(_046_),
    .Y(_114_));
 sky130_fd_sc_hd__nor2_1 _281_ (.A(_039_),
    .B(_015_),
    .Y(_115_));
 sky130_fd_sc_hd__nand2b_1 _282_ (.A_N(_022_),
    .B(_021_),
    .Y(_116_));
 sky130_fd_sc_hd__o311ai_0 _283_ (.A1(_022_),
    .A2(_010_),
    .A3(_114_),
    .B1(_115_),
    .C1(_116_),
    .Y(_117_));
 sky130_fd_sc_hd__a2111oi_0 _284_ (.A1(_081_),
    .A2(_040_),
    .B1(_028_),
    .C1(_016_),
    .D1(_052_),
    .Y(_118_));
 sky130_fd_sc_hd__a21oi_1 _285_ (.A1(_051_),
    .A2(_089_),
    .B1(_027_),
    .Y(_119_));
 sky130_fd_sc_hd__o2bb2ai_1 _286_ (.A1_N(_117_),
    .A2_N(_118_),
    .B1(_119_),
    .B2(_028_),
    .Y(_120_));
 sky130_fd_sc_hd__or4b_1 _287_ (.A(_110_),
    .B(_113_),
    .C(_120_),
    .D_N(_108_),
    .X(_121_));
 sky130_fd_sc_hd__nand4_1 _288_ (.A(net29),
    .B(_077_),
    .C(_103_),
    .D(_120_),
    .Y(_122_));
 sky130_fd_sc_hd__o211ai_2 _289_ (.A1(_104_),
    .A2(_109_),
    .B1(_121_),
    .C1(_122_),
    .Y(net27));
 sky130_fd_sc_hd__and3b_1 _290_ (.A_N(_003_),
    .B(_021_),
    .C(_039_),
    .X(_123_));
 sky130_fd_sc_hd__nor3_1 _291_ (.A(_015_),
    .B(_094_),
    .C(_123_),
    .Y(_124_));
 sky130_fd_sc_hd__o21ai_0 _292_ (.A1(_094_),
    .A2(_123_),
    .B1(_015_),
    .Y(_125_));
 sky130_fd_sc_hd__nor3b_1 _293_ (.A(_124_),
    .B(_113_),
    .C_N(_125_),
    .Y(_126_));
 sky130_fd_sc_hd__nor2b_1 _294_ (.A(_014_),
    .B_N(net29),
    .Y(_127_));
 sky130_fd_sc_hd__a31oi_1 _295_ (.A1(_017_),
    .A2(net18),
    .A3(_110_),
    .B1(_127_),
    .Y(_128_));
 sky130_fd_sc_hd__and3b_1 _296_ (.A_N(net29),
    .B(_015_),
    .C(net19),
    .X(_129_));
 sky130_fd_sc_hd__a21oi_2 _297_ (.A1(_111_),
    .A2(net29),
    .B1(_129_),
    .Y(_130_));
 sky130_fd_sc_hd__o22ai_1 _298_ (.A1(net19),
    .A2(_128_),
    .B1(_130_),
    .B2(net18),
    .Y(_131_));
 sky130_fd_sc_hd__nor4_1 _299_ (.A(_081_),
    .B(_040_),
    .C(_079_),
    .D(_080_),
    .Y(_132_));
 sky130_fd_sc_hd__nor2_1 _300_ (.A(_082_),
    .B(_132_),
    .Y(_133_));
 sky130_fd_sc_hd__o22a_1 _301_ (.A1(_126_),
    .A2(_131_),
    .B1(_133_),
    .B2(_078_),
    .X(net24));
 sky130_fd_sc_hd__nor4_1 _302_ (.A(net19),
    .B(_112_),
    .C(_110_),
    .D(_050_),
    .Y(_134_));
 sky130_fd_sc_hd__a211oi_1 _303_ (.A1(_183_),
    .A2(net18),
    .B1(net29),
    .C1(net19),
    .Y(_135_));
 sky130_fd_sc_hd__nor4_1 _304_ (.A(_084_),
    .B(_064_),
    .C(_134_),
    .D(_135_),
    .Y(_136_));
 sky130_fd_sc_hd__nor3_1 _305_ (.A(_051_),
    .B(_134_),
    .C(_135_),
    .Y(_137_));
 sky130_fd_sc_hd__a21oi_1 _306_ (.A1(_081_),
    .A2(_040_),
    .B1(_016_),
    .Y(_138_));
 sky130_fd_sc_hd__nand2_1 _307_ (.A(_117_),
    .B(_138_),
    .Y(_139_));
 sky130_fd_sc_hd__mux2i_1 _308_ (.A0(_136_),
    .A1(_137_),
    .S(_139_),
    .Y(_140_));
 sky130_fd_sc_hd__a2111o_1 _309_ (.A1(_051_),
    .A2(_064_),
    .B1(_077_),
    .C1(_134_),
    .D1(_135_),
    .X(_141_));
 sky130_fd_sc_hd__nor3_1 _310_ (.A(net29),
    .B(_051_),
    .C(_113_),
    .Y(_142_));
 sky130_fd_sc_hd__nor3_1 _311_ (.A(net29),
    .B(_084_),
    .C(_113_),
    .Y(_143_));
 sky130_fd_sc_hd__mux2i_1 _312_ (.A0(_142_),
    .A1(_143_),
    .S(_105_),
    .Y(_144_));
 sky130_fd_sc_hd__and3_1 _313_ (.A(_140_),
    .B(_141_),
    .C(_144_),
    .X(net25));
 sky130_fd_sc_hd__mux2i_1 _314_ (.A0(_003_),
    .A1(_006_),
    .S(net29),
    .Y(_145_));
 sky130_fd_sc_hd__xnor2_1 _315_ (.A(_021_),
    .B(_145_),
    .Y(_146_));
 sky130_fd_sc_hd__nor2_1 _316_ (.A(_023_),
    .B(net29),
    .Y(_147_));
 sky130_fd_sc_hd__a21oi_1 _317_ (.A1(net29),
    .A2(_020_),
    .B1(_147_),
    .Y(_148_));
 sky130_fd_sc_hd__a32oi_1 _318_ (.A1(net19),
    .A2(_021_),
    .A3(_064_),
    .B1(_068_),
    .B2(_148_),
    .Y(_149_));
 sky130_fd_sc_hd__o21ai_0 _319_ (.A1(_113_),
    .A2(_146_),
    .B1(_149_),
    .Y(net22));
 sky130_fd_sc_hd__a21boi_0 _320_ (.A1(_021_),
    .A2(_096_),
    .B1_N(_147_),
    .Y(_150_));
 sky130_fd_sc_hd__o311a_1 _321_ (.A1(_022_),
    .A2(_010_),
    .A3(_114_),
    .B1(_116_),
    .C1(net29),
    .X(_151_));
 sky130_fd_sc_hd__or3_1 _322_ (.A(_039_),
    .B(_150_),
    .C(_151_),
    .X(_152_));
 sky130_fd_sc_hd__o21ai_0 _323_ (.A1(_150_),
    .A2(_151_),
    .B1(_039_),
    .Y(_153_));
 sky130_fd_sc_hd__nand2b_1 _324_ (.A_N(net29),
    .B(_041_),
    .Y(_154_));
 sky130_fd_sc_hd__o21ai_0 _325_ (.A1(_038_),
    .A2(_110_),
    .B1(_154_),
    .Y(_155_));
 sky130_fd_sc_hd__nand2b_1 _326_ (.A_N(net29),
    .B(_039_),
    .Y(_156_));
 sky130_fd_sc_hd__a21oi_1 _327_ (.A1(net19),
    .A2(_156_),
    .B1(net18),
    .Y(_157_));
 sky130_fd_sc_hd__a21oi_1 _328_ (.A1(_111_),
    .A2(_155_),
    .B1(_157_),
    .Y(_158_));
 sky130_fd_sc_hd__a31oi_1 _329_ (.A1(_077_),
    .A2(_152_),
    .A3(_153_),
    .B1(_158_),
    .Y(net23));
 sky130_fd_sc_hd__inv_1 _330_ (.A(net3),
    .Y(_018_));
 sky130_fd_sc_hd__nor2_1 _331_ (.A(_051_),
    .B(_027_),
    .Y(_159_));
 sky130_fd_sc_hd__nor3_1 _332_ (.A(_033_),
    .B(_051_),
    .C(_027_),
    .Y(_160_));
 sky130_fd_sc_hd__nor2b_1 _333_ (.A(_027_),
    .B_N(_052_),
    .Y(_161_));
 sky130_fd_sc_hd__a221o_1 _334_ (.A1(_016_),
    .A2(_159_),
    .B1(_160_),
    .B2(_082_),
    .C1(_161_),
    .X(_162_));
 sky130_fd_sc_hd__nand2_1 _335_ (.A(net29),
    .B(_044_),
    .Y(_163_));
 sky130_fd_sc_hd__or2_2 _336_ (.A(_047_),
    .B(net29),
    .X(_164_));
 sky130_fd_sc_hd__a21o_1 _337_ (.A1(net19),
    .A2(net29),
    .B1(_045_),
    .X(_165_));
 sky130_fd_sc_hd__a32oi_1 _338_ (.A1(_068_),
    .A2(_163_),
    .A3(_164_),
    .B1(_165_),
    .B2(_112_),
    .Y(_166_));
 sky130_fd_sc_hd__or4_1 _339_ (.A(_034_),
    .B(_033_),
    .C(_028_),
    .D(_166_),
    .X(_167_));
 sky130_fd_sc_hd__nand2b_1 _340_ (.A_N(net29),
    .B(_045_),
    .Y(_168_));
 sky130_fd_sc_hd__a21oi_1 _341_ (.A1(net19),
    .A2(_168_),
    .B1(net18),
    .Y(_169_));
 sky130_fd_sc_hd__a22o_1 _342_ (.A1(_034_),
    .A2(_033_),
    .B1(_164_),
    .B2(_111_),
    .X(_170_));
 sky130_fd_sc_hd__o21bai_1 _343_ (.A1(_169_),
    .A2(_170_),
    .B1_N(_166_),
    .Y(_171_));
 sky130_fd_sc_hd__o21ai_1 _344_ (.A1(_162_),
    .A2(_167_),
    .B1(_171_),
    .Y(net20));
 sky130_fd_sc_hd__nand2_1 _345_ (.A(net29),
    .B(_007_),
    .Y(_172_));
 sky130_fd_sc_hd__o211ai_1 _346_ (.A1(_004_),
    .A2(net29),
    .B1(_172_),
    .C1(_112_),
    .Y(_173_));
 sky130_fd_sc_hd__nand2b_1 _347_ (.A_N(net29),
    .B(_011_),
    .Y(_174_));
 sky130_fd_sc_hd__o211ai_1 _348_ (.A1(_008_),
    .A2(_110_),
    .B1(_174_),
    .C1(net18),
    .Y(_175_));
 sky130_fd_sc_hd__and2_1 _349_ (.A(_009_),
    .B(net19),
    .X(_176_));
 sky130_fd_sc_hd__a32o_1 _350_ (.A1(_111_),
    .A2(_173_),
    .A3(_175_),
    .B1(_064_),
    .B2(_176_),
    .X(net21));
 sky130_fd_sc_hd__a2bb2oi_1 _351_ (.A1_N(net18),
    .A2_N(_146_),
    .B1(_173_),
    .B2(_175_),
    .Y(_177_));
 sky130_fd_sc_hd__nand2_1 _352_ (.A(_064_),
    .B(_176_),
    .Y(_178_));
 sky130_fd_sc_hd__o211ai_1 _353_ (.A1(net19),
    .A2(_177_),
    .B1(_178_),
    .C1(_149_),
    .Y(_179_));
 sky130_fd_sc_hd__or3_1 _354_ (.A(net24),
    .B(net23),
    .C(_179_),
    .X(_180_));
 sky130_fd_sc_hd__a31o_2 _355_ (.A1(_140_),
    .A2(_141_),
    .A3(_144_),
    .B1(net20),
    .X(_181_));
 sky130_fd_sc_hd__nor4_2 _356_ (.A(net26),
    .B(net27),
    .C(_180_),
    .D(_181_),
    .Y(net28));
 sky130_fd_sc_hd__fa_1 _357_ (.A(_000_),
    .B(_001_),
    .CIN(_002_),
    .COUT(_003_),
    .SUM(_004_));
 sky130_fd_sc_hd__fa_1 _358_ (.A(net2),
    .B(_001_),
    .CIN(_005_),
    .COUT(_006_),
    .SUM(_007_));
 sky130_fd_sc_hd__ha_1 _359_ (.A(_000_),
    .B(_001_),
    .COUT(_008_),
    .SUM(_009_));
 sky130_fd_sc_hd__ha_1 _360_ (.A(net2),
    .B(_001_),
    .COUT(_010_),
    .SUM(_184_));
 sky130_fd_sc_hd__ha_1 _361_ (.A(net2),
    .B(net10),
    .COUT(_011_),
    .SUM(_185_));
 sky130_fd_sc_hd__ha_1 _362_ (.A(_012_),
    .B(_013_),
    .COUT(_014_),
    .SUM(_015_));
 sky130_fd_sc_hd__ha_1 _363_ (.A(net5),
    .B(_013_),
    .COUT(_016_),
    .SUM(_186_));
 sky130_fd_sc_hd__ha_1 _364_ (.A(net5),
    .B(net13),
    .COUT(_017_),
    .SUM(_187_));
 sky130_fd_sc_hd__ha_1 _365_ (.A(_018_),
    .B(_019_),
    .COUT(_020_),
    .SUM(_021_));
 sky130_fd_sc_hd__ha_1 _366_ (.A(net3),
    .B(_019_),
    .COUT(_022_),
    .SUM(_188_));
 sky130_fd_sc_hd__ha_1 _367_ (.A(net3),
    .B(net11),
    .COUT(_023_),
    .SUM(_189_));
 sky130_fd_sc_hd__ha_1 _368_ (.A(_024_),
    .B(_025_),
    .COUT(_026_),
    .SUM(_027_));
 sky130_fd_sc_hd__ha_1 _369_ (.A(net7),
    .B(_025_),
    .COUT(_028_),
    .SUM(_190_));
 sky130_fd_sc_hd__ha_1 _370_ (.A(net7),
    .B(net15),
    .COUT(_029_),
    .SUM(_191_));
 sky130_fd_sc_hd__ha_1 _371_ (.A(_030_),
    .B(_031_),
    .COUT(_032_),
    .SUM(_033_));
 sky130_fd_sc_hd__ha_1 _372_ (.A(net8),
    .B(_031_),
    .COUT(_034_),
    .SUM(_192_));
 sky130_fd_sc_hd__ha_1 _373_ (.A(net8),
    .B(net16),
    .COUT(_035_),
    .SUM(_193_));
 sky130_fd_sc_hd__ha_1 _374_ (.A(_036_),
    .B(_037_),
    .COUT(_038_),
    .SUM(_039_));
 sky130_fd_sc_hd__ha_1 _375_ (.A(net4),
    .B(_037_),
    .COUT(_040_),
    .SUM(_194_));
 sky130_fd_sc_hd__ha_1 _376_ (.A(net4),
    .B(net12),
    .COUT(_041_),
    .SUM(_195_));
 sky130_fd_sc_hd__ha_1 _377_ (.A(_042_),
    .B(_043_),
    .COUT(_044_),
    .SUM(_045_));
 sky130_fd_sc_hd__ha_1 _378_ (.A(_042_),
    .B(net9),
    .COUT(_046_),
    .SUM(_196_));
 sky130_fd_sc_hd__ha_1 _379_ (.A(net1),
    .B(net9),
    .COUT(_047_),
    .SUM(_197_));
 sky130_fd_sc_hd__ha_1 _380_ (.A(_048_),
    .B(_049_),
    .COUT(_050_),
    .SUM(_051_));
 sky130_fd_sc_hd__ha_1 _381_ (.A(net6),
    .B(_049_),
    .COUT(_052_),
    .SUM(_198_));
 sky130_fd_sc_hd__ha_1 _382_ (.A(net6),
    .B(net14),
    .COUT(_053_),
    .SUM(_199_));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input1 (.A(io_inputA[0]),
    .X(net1));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input10 (.A(io_inputB[1]),
    .X(net10));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input11 (.A(io_inputB[2]),
    .X(net11));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input12 (.A(io_inputB[3]),
    .X(net12));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input13 (.A(io_inputB[4]),
    .X(net13));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input14 (.A(io_inputB[5]),
    .X(net14));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input15 (.A(io_inputB[6]),
    .X(net15));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input16 (.A(io_inputB[7]),
    .X(net16));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input17 (.A(io_op[0]),
    .X(net17));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input18 (.A(io_op[1]),
    .X(net18));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input19 (.A(io_op[2]),
    .X(net19));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input2 (.A(io_inputA[1]),
    .X(net2));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input3 (.A(io_inputA[2]),
    .X(net3));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input4 (.A(io_inputA[3]),
    .X(net4));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input5 (.A(io_inputA[4]),
    .X(net5));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input6 (.A(io_inputA[5]),
    .X(net6));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input7 (.A(io_inputA[6]),
    .X(net7));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input8 (.A(io_inputA[7]),
    .X(net8));
 sky130_fd_sc_hd__clkdlybuf4s50_1 input9 (.A(io_inputB[0]),
    .X(net9));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output20 (.A(net20),
    .X(io_result[0]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output21 (.A(net21),
    .X(io_result[1]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output22 (.A(net22),
    .X(io_result[2]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output23 (.A(net23),
    .X(io_result[3]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output24 (.A(net24),
    .X(io_result[4]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output25 (.A(net25),
    .X(io_result[5]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output26 (.A(net26),
    .X(io_result[6]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output27 (.A(net27),
    .X(io_result[7]));
 sky130_fd_sc_hd__clkdlybuf4s50_1 output28 (.A(net28),
    .X(io_zero));
 sky130_fd_sc_hd__buf_4 place29 (.A(net17),
    .X(net29));
endmodule
