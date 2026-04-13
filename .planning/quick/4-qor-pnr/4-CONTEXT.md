# Quick Task 4: 多轮QoR参数对比优化PnR流程 - Context

**Gathered:** 2026-04-13
**Status:** Ready for planning

<domain>
## Task Boundary

修改 skills/pnr/SKILL.md 和 mcp-server/tools/compare-runs.ts，实现：
1. 强制跑完所有 QoR 对比轮次（不因第一轮 pass 跳过）
2. 基于 synth 结果动态生成参数组合（3-5 轮）
3. QoR 推荐策略加入 power 排序（clock > area > power）
</domain>

<decisions>
## Implementation Decisions

### 强制完成全部轮次
- 在 SKILL.md Step 3 加入醒目 "MANDATORY" 规则，禁止提前退出
- 加入轮次进度指示器，每轮完成时显示 `Round X/N completed`
- 在 Anti-Patterns 加入 "DO NOT skip rounds even if earlier rounds passed"

### 动态参数策略（基于 synth 结果）
- Round 1: baseline（spec.json 原始参数）
- Round 2: tighter clock (-20% from baseline)
- Round 3: lower utilization (35%) + gpl_timing_driven
- [if cell_count > 1000]: Round 4: lower density (0.55) + gpl_routability_driven
- [if cell_count > 1000]: Round 5: aggressive timing + low utilization (30%)
- 最少 3 轮，大设计扩展到 5 轮

### QoR 推荐策略
- compare_runs recommend 加入 power 排序
- 固定优先级：clock_period (最小) > area (最小) > power (最小)
- 只在 timing 和 area 相近时才比较 power

### Claude's Discretion
- SKILL.md 中具体的措辞和格式细节
- 动态参数的边界值调整
</decisions>

<specifics>
## Specific Ideas

- 当前 SKILL.md 的 round_plans 在 Step 2 是静态定义的，需要改为 Step 3 中根据 synth 结果动态追加
- Step 3 的循环逻辑需要确保 outer loop（轮次）和 inner loop（重试）清晰分离
- compare_runs.ts 的 recommendBest 需要加入 total_power_w 排序维度
</specifics>
