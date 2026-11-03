# 自主检索审查：来源信息含错时的固定预算工具问答

结论：建议保留为窄范围实证问题，不把“去重、来源分组、冲突后补搜”作为新机制。原始引用的题名与标识均已核对；新增工作进一步压缩可主张的贡献。

## 已读原始文献与对应关系

| 文献                                                                                                 | 作者、年份、标识                                                                                                                                                                        | 已有覆盖与本题边界                                                                                                                                                                                                              |
| ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tools Fail: Detecting Silent Errors in Faulty Tools                                                  | Jimin Sun; So Yeon Min; Yingshan Chang; Yonatan Bisk。2024，arXiv:2406.19228，EMNLP 2024，DOI:10.18653/v1/2024.emnlp-main.790                                                           | 已研究静默工具错误检测，正文包含故障计算器与具身代理；不能主张首次让模型质疑工具。正文和 ACL 出版页均已读取。[8]                                                                                                                |
| Epistemic Sybil Resistance: Multiplying AI Agents Without Multiplying Evidence                       | Marc Bara。2026，arXiv:2609.01873v1，提交日 2026-09-01                                                                                                                                  | 已研究报告数与证据根数的区别、共享来源及相关提取误差，并检验文本相似度与来源谱系的分离。同根不等于所有提取均完全冗余，不能一律作为精确复制处理。[5][12]                                                                         |
| Replication or Corroboration? An Axiomatic Framework for Evidential Dependence in Multi-Agent Debate | Hoang-Loc Cao; Truong Thanh Hung Nguyen; Phuc Truong Loc Nguyen; Vo Thanh Khang Nguyen; Phuc Ho; Hung Nguyen; Duc Pham; Long Tran-Thanh; Hung Cao。2026，arXiv:2610.36151v1，2026-10-26 | PDF 的 Trust Boundary 明确使用给定来源分区，不推断分区；不同根也不保证统计独立。第8节明确指出假拆分抬高聚合、假合并压低聚合，现实错误率下的量化仍开放。因此“发现分组错误”本身已有讨论。[13]                                     |
| Corrective Retrieval Augmented Generation                                                            | Shi-Qi Yan; Jia-Chen Gu; Yun Zhu; Zhen-Hua Ling。2024，arXiv:2401.15884v3                                                                                                               | 原始摘要已明确质量评估触发不同检索动作，并用网页搜索扩充检索。只声称“检测不可靠结果后补搜”与其重叠。本次 HTML/PDF 提取仅返回摘要及引言片段，未据此认定其全部正文没有来源分组或成本控制。[9]                                     |
| Integrating Conflicting Data: The Role of Source Dependence                                          | Xin Luna Dong; Laure Berti-Equille; Divesh Srivastava。2009，PVLDB 2(1)，原始 PDF vldb09-pvldb47                                                                                        | 原文已用贝叶斯分析推断来源依赖，迭代检测复制与发现真值，考虑来源准确率及值相似性。来源依赖并非总要由 oracle 给定；“推断来源依赖再折扣”有更早先例。[14]                                                                          |
| GraphEcho: Structural Redundancy and Evidence Provenance in LLM Graph Agents                         | Sikun Wang; Yixi Zhou; Lei Fan; Fan Zhang。2026，arXiv:2609.17695v1，2026-09-15                                                                                                         | 原始第4节已研究预算内获取不同证据，比较便宜干预与训练策略；正文区分来源覆盖、重复访问、准确率、成本。局限指出文档 ID 不证明研究独立，科学任务的 gold rationale 设置省略检索错误。因此不能把“固定预算探索不同来源”当作空白。[17] |
| Copies or Sources? Measuring How LLM Aggregators Count Restated Evidence in Multi-Agent Systems      | Jianxin Gao; Runze Li; Tianyi Yu; Liangwei Ren; Bohan Chen; Zining Wang。2026，arXiv:2610.06192v1，2026-10-05                                                                           | 原始页面摘要已研究重复观察的权重、网页附加复制与代理日志，并使用声明复制贡献的短提示、以引用代替复述的协议。必须加入轻量提示基线；本次此页正文提取只到引言开头，不声称完成全文排查。[18][19]                                    |

2026 文献在此仅标为 arXiv 预印本，未验证同行评审状态；所有论文中的性能数值均属于作者报告，本轮未复现实验。

## 建议收窄的问题与待验假设

建议题目：**来源元数据缺损下，保守分组何时值得消耗一次核验预算？**

检验：在冻结模型、相同工具调用上限及上下文 token 上限下，来源元数据的缺失、假拆分和假合并分别达到何种程度时，“可观察元数据的保守分组＋一次定向补搜”相对 URL/文本去重及普通补搜仍有收益？这是建议检验的交互效应，未证明新颖性或有效性。GraphEcho 已覆盖预算与来源探索，Replication or Corroboration 已指出分区错误，CRAG 已覆盖条件补搜；可检验的余量在这些因素联合受控后的增量效果。[13][17][9]

建议最小输入为 claim、passage、URL、可见引用链接及时间信息。只对显式转载/引用关系作高置信合并，其余标为未知；不同域名不直接增加“独立”计数。真实根标签只用于评估及 oracle 上界。缺失与错误必须分别干预；同一个混合来源页面不能强行假定只有一个证据根。此段为实验设计建议，不是论文已证结论。

建议基线：URL 去重、词面相似度去重、一个短“重复不增加佐证”提示、普通补搜、只分组、只定向补搜、分组加补搜，以及 oracle 分组。普通补搜和定向补搜使用同一候选快照、同一返回条数和调用上限；补搜失败仍计入成本。

建议主要报告错误采纳率—覆盖率曲线、相同覆盖率下风险、来源分组误拆/误并、根覆盖率、输入输出 token、工具调用及费用。阈值仅在开发集选择；事实及来源家族隔离。若收益只来自拒答增加、额外预算、oracle 根标签，或被短提示/普通去重解释，应判失败。若真实来源关系不能核实，只能报告可观察溯源代理指标与受控干预，不能宣称发现了统计独立来源。

## 工具实录与材料

实际执行了独立 web_search、并行 web_extract、原始 arXiv/ACL/PVLDB 页面与 PDF 读取，并用 terminal 运行引用登记及证据匹配。证据保存到当前 profile 的 research-tool-qa；未读取其他项目、凭据或私有日志，未修改系统配置。

提取限制：一个猜测的 VLDB 路径只返回站点说明，已废弃并通过独立搜索找到原始 PDF；多份 arXiv HTML 提取不完整，已为 Replication or Corroboration 改读完整 PDF，为 Epistemic Sybil Resistance 补读作者公开 LaTeX，为 GraphEcho 读取正文。CRAG 和 Copies or Sources 仅据实际取回的摘要/片段作有限判断。

尚未验证：相同预算条件下的收益、最佳阈值、真实网页谱系标签、API 总费用及近邻文献是否完全覆盖此联合设置。本轮只交付文献审查，没有本项目模型实验结果。

## Sources

[5] https://arxiv.org/abs/2609.01873
[8] https://aclanthology.org/2024.emnlp-main.790
[9] https://arxiv.org/abs/2401.15884
[12] https://raw.githubusercontent.com/marcbara/epistemic-sybil-resistance/master/paper/latex-src/main.tex
[13] https://arxiv.org/pdf/2610.36151v1
[14] https://www.vldb.org/pvldb/vol2/vldb09-pvldb47.pdf
[17] https://arxiv.org/html/2609.17695v1
[18] https://arxiv.org/abs/2610.06192
[19] https://arxiv.org/html/2610.06192v1
