# 作业2：基于 Claude Code 的 RTL 到布局布线自动化 Agent 开发
**交付日期**：2026年4月13日24:00前（每晚一天扣15%）
**作业上传**：https://elearning.fudan.edu.cn

## 核心任务
以第一次作业中已生成并验证通过的 RTL 为输入，围绕 Claude Code 构建基于 **sky130hd** 平台的数字后端自动化 Agent。

需完成：
1. 开发 MCP Server，将后端工具链的 Docker 操作封装为 Claude Code 可调用工具；
2. 编写 Skill，编排多阶段后端流程执行逻辑；
3. 配置 Rules 和 Hooks，定义流程规范与自动化检查。

**最终目标**：用户在 Claude Code 中给出已验证 RTL 设计及必要顶层信息后，Agent 自动完成输入检查、约束生成、配置生成、工具调用、日志分析和报告输出。

---

## 1 任务内容

### A 基础工具搭建
#### a) 必备工具
- Docker Desktop / Docker Engine（运行后端工具容器）
  验证：`docker --version`
- Node.js 18+ 及 Claude Code CLI Agent 平台
  验证：`claude --version`

#### b) Docker 镜像
使用 OpenROAD 官方镜像（内置 Yosys、OpenROAD、KLayout、sky130hd 平台文件）：
```bash
docker pull openroad/orfs:latest
```
验证镜像：
```bash
docker run --rm openroad/orfs:latest yosys -version
docker run --rm openroad/orfs:latest openroad -version
```

#### c) 容器使用模式
长驻容器运行，挂载本地设计目录到容器：
```bash
docker run -d --name orfs-agent \
  -v $(pwd)/design:/workspace \
  openroad/orfs:latest sleep infinity
```
后续通过 `docker exec` 执行操作：
```bash
docker exec orfs-agent yosys -version
```
通过 MCP Server 封装 `docker exec` 调用，使 Claude Code 可直接操作容器内 EDA 工具。

---

### B 工艺平台与输入文件
#### a) 平台要求
统一基于 **sky130hd** 平台，文件位于 Docker 镜像内：
```
/OpenROAD-flow-scripts/flow/platforms/sky130hd/
```
关键目录：
- `lef/`：标准单元版图抽象
- `lib/`：时序库文件
- `gds/`：标准单元版图

#### b) config.mk
ORFS 设计配置文件，需适配 ALU 设计。
参考：https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/designs/sky130hd/gcd/config.mk

#### d) constraint.sdc
时序约束文件（Synopsys Design Constraints）。
参考：https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/designs/sky130hd/gcd/constraint.sdc

---

### C ORFS 流程检查（MCP 参考）
ORFS（OpenROAD-flow-scripts）为开源数字后端自动化流程框架，通过 `make` 驱动完整后端流程，容器内执行目录：
```
/OpenROAD-flow-scripts/flow/
```
一键全跑：
```bash
make DESIGN_CONFIG=/workspace/config.mk
```

#### a) 阶段与命令
| 阶段 | make target | 说明 | 关键输出 |
|------|-------------|------|----------|
| 逻辑综合 | synth | RTL → 门级网表 | 门数、面积 |
| 布局规划 | floorplan | 确定芯片尺寸和引脚位置 | 核心面积、利用率 |
| 布局 | place | 标准单元摆放 | 布局密度、拥塞 |
| 时钟树综合 | cts | 构建时钟分配网络 | 时钟偏斜（skew） |
| 布线 | route | 完成信号连线 | DRC 违例数、WNS/TNS |
| 收尾 | finish | 最终检查与输出 | 最终报告、版图图片 |

单独执行示例：
```bash
cd /OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=/workspace/config.mk synth
```
各阶段按顺序执行，前一阶段输出为后一阶段输入。

#### b) 结果目录
容器内路径：
- `results/sky130hd/<DESIGN_NAME>/base/`：各阶段结果文件
- `logs/sky130hd/<DESIGN_NAME>/base/`：各阶段日志
- `reports/sky130hd/<DESIGN_NAME>/base/`：各阶段报告

#### c) 关键指标
- 面积：综合报告中 cell count、design area
- 时序：WNS（最差负裕量）、TNS（总负裕量），负值表示时序违例
- DRC：布线后设计规则违例数，0 为理想值
- 拥塞：布局阶段 congestion 百分比

流程结束生成 `metadata.json`，便于程序化提取指标。

---

### D Agent 框架指引
采用三层协作模式：
1. **MCP Server（工具层）**：封装底层 Docker 操作，提供 Claude Code 可调用工具，明确输入/输出/职责。
2. **Skill（编排层）**：定义流程编排逻辑，连接用户意图与工具调用。
   - 执行顺序：synth → floorplan → place → CTS → route
   - 阶段后检查逻辑
   - 阶段间决策规则（继续/重试/上报）
   - 最终报告输出格式
3. **Rules 与 Hooks（规范层）**
   - Rules（CLAUDE.md）：项目说明、流程规范、输入输出目录约定
   - Hooks：特定事件前后自动执行检查脚本（如文件完整性检查）

---

### E 验收标准
#### 基础要求
- Docker 环境就绪，可运行 Yosys、OpenROAD
- MCP Server 至少封装 2 个工具（如 `run_stage`、`get_report`）
- Skill 完成 synthesis 阶段编排
- Agent 自动识别顶层模块，使用/生成 `constraint.sdc`、`config.mk`
- 输出综合结果报告（门数、面积等）

#### 进阶要求
- MCP 工具覆盖完整后端流程
- Skill 自动推进全部 5 个阶段
- 每阶段自动提取关键指标（面积、WNS/TNS、DRC）
- 生成 PPA（Performance, Power, Area）汇总报告

#### 满分要求
- 流程失败自动诊断错误类型（时序违例、拥塞、DRC 等）
- 按错误类型实施参数重试（调整 `PLACE_DENSITY`、`CLOCK_PERIOD`）
- 支持多轮 QoR 优化，对比不同配置结果

---

## 2 提交物

### 2.1 作业报告（PDF，50分）
1. 封面页：组号、姓名
2. 环境搭建说明（10分）
3. 工艺平台与输入文件说明（10分）
4. Agent 配置说明（15分）
5. 交互日志与问题分析（5分）
6. QoR 结果分析（面积、时序、布线等，10分）

### 2.2 配置文件与代码（附件，50分）
#### 目录结构
```
作业2(序号_姓名)/
├── .claude/
│   ├── .mcp.json
│   ├── CLAUDE.md
│   ├── skills/
│   └── hooks/
├── mcp-server/        # MCP Server 源码
│   ├── src/
│   ├── package.json
│   └── README.md
├── design/
│   ├── rtl/           # alu.v
│   ├── constraint.sdc
│   └── config.mk
├── logs/              # 容器提取日志
├── reports/           # 容器提取报告
├── results/            # 容器提取结果
└── README.md
```

#### 内容要求
1. `.claude/` 配置文件（10分）
2. 后端流程输入（RTL、SDC、config.mk）（5分）
3. MCP Server 源码与运行脚本（10分）
4. 运行脚本、日志、报告、结果（10分）
5. 实验关键中间结果（5分）
6. 助教自动化测试验证（10分）：自动化程度、结果完整性、日志可读性、失败分析能力

---

## 3 注意事项
1. 必须基于 **sky130hd** 平台，不得替换。
2. 以第一次作业的 **ALU** 为测试对象。
3. 报告自主撰写，禁止直接使用未整理 AI 生成内容，引用公开资料需注明来源。
4. API Key 不得提交至仓库或泄露。
5. 参考资源：
   - MCP 官方文档：https://modelcontextprotocol.io
   - Claude Code MCP 配置：https://docs.anthropic.com/en/docs/claudecode/mcp
   - ORFS 官方仓库：https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts

要不要我帮你把这份 Markdown 导出成 **可直接保存的 .md 文件** 或整理成**可直接提交的作业目录模板**？
