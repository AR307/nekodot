// Chinese text for Hermes v0.22.6's own settings and commands, which Hermes
// ships in English only. Written from Hermes's documented config and command
// help; keep it in step when the pinned Hermes version changes.

/// Setting key → (name, note).
const hermesSettingZh = <String, (String, String)>{
  'agent.agent_cache.idle_ttl_secs': ('缓存空闲回收时间', '网关中的智能体缓存空闲超过此时长（秒）即被移除。'),
  'agent.agent_cache.max_evictions_per_pass': (
    '单次回收上限',
    '内存回收时每一轮最多释放的会话数，避免集中回收拖慢网关。',
  ),
  'agent.agent_cache.max_size': (
    '智能体缓存上限',
    '网关为各会话常驻缓存的智能体条目上限，按最近使用淘汰。每条保留提示词前缀和完整对话记录：太小会重复支付未命中缓存的费用，太大会占用较多内存。',
  ),
  'agent.agent_cache.memory_high_mb': (
    '缓存内存阈值',
    '进程内存超过此值（MB）时，按最近最少使用释放会话记录，下一轮再从磁盘读回。auto = 根据容器内存限制或总内存自动计算；0 或 off = 关闭。',
  ),
  'agent.agent_cache.protect_recent': ('保护最近会话数', '内存回收时始终保留、不被释放的最近使用会话数。'),
  'agent.api_max_retries': (
    'API 重试次数',
    '遇到连接中断、超时、5xx 等 API 错误时，Hermes 层面的重试次数。使用备用提供方并希望快速切换时可设为 1。',
  ),
  'agent.auto_recovery_cycles': (
    '自动恢复轮数',
    '重试和备用链都用完、但仍是临时故障（5xx、过载、连接超时）且尚未输出内容时，额外等待并重试的轮数，期间显示倒计时，可按 Esc 停止。认证、格式、计费或策略错误不会进入此流程。0 = 关闭。',
  ),
  'agent.bot_mode_protocol': (
    'Bot 模式协作说明',
    '在桌面应用 Bot 模式管理的 Bot 对话中，向系统提示词加入与其他智能体互发消息的说明。未使用 Bot 模式时不产生内容。',
  ),
  'agent.budget_warning_ratio': (
    '轮数预警比例',
    '设置了最大轮数时，用到此比例后向模型发出一次提醒，例如 0.75。留空 = 关闭；取值需在 0 到 1 之间。',
  ),
  'agent.build_wait_timeout': (
    '智能体准备等待超时',
    '提交消息后等待智能体完成准备（发现 MCP、读取模型信息、扫描技能）的最长时间（秒），超时会显示错误。准备完成后消息会立即发送；MCP 服务器多或响应慢时可调高。',
  ),
  'agent.clarify_timeout': (
    '澄清问题等待时长',
    '智能体向用户提出澄清问题后最长等待多久（秒），超时后注明用户未回复并继续。0 或负数 = 不限制。',
  ),
  'agent.coding_context': (
    '编程模式',
    '在代码工作区的交互界面（CLI、TUI、桌面应用）中，向系统提示词加入编程说明和 Git／工作区快照。auto = 交互界面且位于代码工作区时启用；focus = 在 auto 基础上精简为编程工具集；on = 所有场景启用；off = 关闭。',
  ),
  'agent.coding_instructions': (
    '编程附加指令',
    '编程模式下附加在编程说明后的固定指令，可填一段文字或多条，用于约定项目工作流程。下一个会话生效。',
  ),
  'agent.cron_drain_timeout': (
    '定时任务收尾时间',
    '网关停止或重启时，为进行中的定时任务和 API 服务（/v1）运行保留的最短收尾时间（秒），因为它们被中断后不会自动恢复。0 = 不单独保留，按停止前宽限时间处理。',
  ),
  'agent.disabled_toolsets': ('禁用的工具集', '在 CLI、网关、定时任务等所有入口都不提供给智能体的工具集列表。'),
  'agent.empty_response_guard.cost_threshold_usd': (
    '空回复费用阈值',
    '单次空回复尝试的预估输入费用达到此金额（美元）时，重试次数从 3 次降为 1 次。无法估算价格时不受影响。',
  ),
  'agent.empty_response_guard.enabled': (
    '空回复重试保护',
    '模型返回空回复时，若能确定是重复出现的空结果（如无提示的拒答、零输出 token），就不再按全价重复重试。关闭则固定重试 3 次。',
  ),
  'agent.environment_hint': (
    '环境说明',
    '宿主程序追加到系统提示词环境说明中的文字，用于描述代理、凭证或挂载目录等运行环境。环境变量 HERMES_ENVIRONMENT_HINT 优先。',
  ),
  'agent.environment_probe': (
    '工具链环境探测',
    '检测到 Python、pip、uv 等工具链有异常时，在系统提示词中说明；一切正常时不占用 token。Docker、Modal、SSH 后端跳过此探测。',
  ),
  'agent.execution_guidance': (
    '执行规范提示',
    '在系统提示词中加入执行规范（坚持用工具、写入后回读核对、完成前验证等）。auto = 对 gpt、codex、grok、deepseek、kimi、qwen、glm 等模型启用；true／false = 对所有模型强制开关；也可填模型名片段列表。',
  ),
  'agent.fast_auto_seconds': ('快速模式时长', '快速模式为 auto 或 cold 时，每轮开始后使用快速档的秒数。'),
  'agent.gateway_auto_continue_freshness': (
    '中断续接时效',
    '运行中途崩溃或重启后，用户下一条消息前会加上“上一轮被中断”的提示；只有最后一条记录在此时长（秒）以内才加，避免唤起无关的旧任务。0 = 总是加入。',
  ),
  'agent.gateway_notify_interval': (
    '处理中提示间隔',
    '网关运行较久时发送“仍在处理”状态提示的间隔（秒）。数值越小反馈越快、消息越多；0 = 关闭。',
  ),
  'agent.gateway_startup_restore_drain_timeout': (
    '启动恢复等待超时',
    '网关启动后等待自动恢复的对话完成的最长时间（秒），期间新消息会排队；超时后放行新消息，恢复继续在后台运行。0 = 一直等待。',
  ),
  'agent.gateway_startup_warmup_timeout': (
    '启动预热超时',
    '网关启动预热（加载工具、上下文文件等）最多阻挡新消息的时间（秒），避免早到的消息用不完整的系统提示词回复；超时后放行并在后台完成预热。0 = 关闭预热，按需初始化。',
  ),
  'agent.gateway_timeout': (
    '网关无活动超时',
    '网关中的运行完全空闲达到此时长（秒）即终止；调用工具或接收 API 响应期间不算空闲。0 = 不限制。',
  ),
  'agent.gateway_timeout_warning': (
    '无活动预警',
    '运行空闲达到此时长（秒）时发送一次警告，不会中断运行。0 = 关闭。',
  ),
  'agent.gateway_turn_lease_timeout': (
    '同会话排队等待',
    '同一会话已有一轮在运行时，新消息最多等待多久（秒）；超时会拒收并提示用户重发。非正数按 5 秒处理。',
  ),
  'agent.image_input_mode': (
    '图片输入方式',
    '用户发送的图片如何交给主模型。auto = 模型支持视觉且未单独指定视觉提供方时直接发送，否则转为文字描述；native = 总是直接发送；text = 总是先用视觉分析转为文字描述。',
  ),
  'agent.intent_ack_continuation': (
    '说而不做时催办',
    '模型只说要做某事却没有调用工具时，插入“现在就执行”的提示并继续（每轮最多 2 次）。auto = 仅 codex_responses 接口模式；true = 所有接口模式；false = 从不；也可填模型名片段列表。',
  ),
  'agent.local_stream_stale_timeout': (
    '本地模型流卡住上限',
    '本地提供方（Ollama、llama-cpp 等）流式输出卡住时判定超时的最长时间（秒），避免本地服务卡死后一直等待。环境变量 HERMES_LOCAL_STREAM_STALE_TIMEOUT 优先。',
  ),
  'agent.max_turns': ('最大轮数', '一次对话中工具调用循环的最大次数。留空、0、-1 或 none 表示不限制；填正整数则限制。'),
  'agent.max_verify_nudges': (
    '验证催办次数上限',
    '一轮中 pre_verify 钩子最多可以要求智能体继续验证的次数，防止钩子让循环无法结束。',
  ),
  'agent.parallel_tool_call_guidance': (
    '并行工具调用提示',
    '在系统提示词中引导模型把相互独立的读取、搜索、查询等工具调用合并到同一轮。约占 70 个 token；关闭则不加入。',
  ),
  'agent.reasoning_echo': (
    '推理字段回填',
    '在没有推理内容的工具调用轮次补发空推理字段。DeepSeek、Kimi、MiMo 等要求此字段，会按提供方自动识别；通过自建网关转发这些模型时可开启。',
  ),
  'agent.reconnect_attention_after': (
    '重连失败告警时长',
    '消息平台持续重连失败达到此时长（秒）后，在网关状态中标记为需要关注；重连不会停止。0 = 关闭。',
  ),
  'agent.restart_after_turn_timeout': (
    '重启前等待时长',
    '执行 /restart 时先停止接收新任务，最多等待此时长（秒）让进行中的对话、定时任务和 API 运行完成，再开始停止。0 = 立即停止。',
  ),
  'agent.restart_drain_timeout': (
    '停止前宽限时间',
    '网关开始停止后，强制中断运行中智能体前的宽限时间（秒）。0 = 立即中断；需小于系统服务的停止超时。',
  ),
  'agent.run_budget_seconds': (
    '单次运行时间预算',
    '每次运行的总时长上限（秒），用到 80% 时提醒一次收尾。留空 = 关闭。',
  ),
  'agent.sanitizer_heal_escalation_threshold': (
    '记录修复告警阈值',
    '发送前自动修复对话记录的次数在 10 分钟内达到此值时，记录一次错误并提示用户使用 /debug share 或 hermes doctor。0 = 不升级提示。',
  ),
  'agent.service_tier': (
    '快速模式',
    '部分官方接口提供的高价快速处理档。空或 normal = 关闭；fast = 每次请求都使用；auto = 每轮开始后若干秒使用；cold = 仅会话第一轮使用。',
  ),
  'agent.session_stall_timeout': (
    '会话卡顿提醒',
    '会话有待处理的后续消息、但智能体已无活动达到此时长（秒）时，提醒用户尝试 /new；不会终止当前一轮。0 = 关闭。',
  ),
  'agent.stall_guards': (
    '防卡死保护',
    '同一工具以相同参数和结果被调用 3 次以上时附加提醒；模型说要继续却没有行动时再提示一次。关闭则两项都停用。',
  ),
  'agent.stream_drain_timeout': (
    '流结束收尾等待',
    'Codex／Responses 流收到结束信号后继续读取的秒数，便于中继完成收尾，避免连接不关闭导致卡住。0 = 不等待。',
  ),
  'agent.stream_max_lifetime': (
    '单次流式输出上限',
    '单次流式回复从开始计算的总时长上限（秒），不会因收到新内容而重置。0 = 关闭。',
  ),
  'agent.task_completion_guidance': (
    '完成任务提示',
    '在系统提示词中要求模型把任务做完，不要停在半成品，也不要在受阻时编造结果。约占 80 个 token；关闭则不加入。',
  ),
  'agent.text_verbosity': (
    '回答详略',
    'Responses 接口最终回答的详略程度：low、medium 或 high；留空则不发送，使用提供方默认。仅对 Responses 系列接口生效。',
  ),
  'agent.tool_use_enforcement': (
    '工具调用强制提示',
    '在系统提示词中要求模型直接调用工具，而不是只描述要做的操作。auto = 对 gpt、codex 模型启用；true／false = 对所有模型强制开关；也可填模型名片段列表。',
  ),
  'agent.turn_liveness.poll_s': ('存活检测间隔', '轮次存活检测的采样间隔（秒）。'),
  'agent.turn_liveness.timeout_s': (
    '轮次无进展超时',
    '一轮没有任何可见进展超过此时长（秒）时，记录日志并强制中断，以便重试。小于等于 0 = 关闭。',
  ),
  'agent.verify_guidance': (
    '验证附加指引',
    '结束前验证发现改了代码但没有新的验证结果时，附加关于界面类工作和清理改动的指引。关闭则只给简短提醒。',
  ),
  'agent.verify_on_stop': (
    '结束前验证',
    '改动代码后，在有新的验证结果或说明无法验证之前不给出最终回答。默认关闭；true = 所有场景开启；auto = 交互式编程界面开启，消息平台关闭。只改文档或技能时不触发。',
  ),
  'approvals.cron_mode': (
    '定时任务审批策略',
    '定时任务遇到危险命令时的处理方式：deny = 直接拒绝，让智能体换其他办法；approve = 自动批准。',
  ),
  'approvals.denial_breaker_threshold': (
    '连续拒绝上限',
    '智能审批在一个会话中连续拒绝达到此次数后，拒绝提示升级为停止并请用户处理或使用 /approve。批准一次即重置；0 = 关闭。',
  ),
  'approvals.deny': ('命令禁止列表', '终端命令匹配规则列表（不区分大小写，支持 * 通配）。匹配的命令一律拦截，即使审批已关闭。'),
  'approvals.destructive_slash_confirm': (
    '清除类命令确认',
    '执行 /clear、/new、/reset、/undo 等会丢弃内容的命令前先确认。选择“始终批准”后会关闭此项。',
  ),
  'approvals.discord_prompt_timeout': (
    'Discord 审批按钮时长',
    'Discord 中审批按钮保持可点击的时间（秒），最少 30 秒。',
  ),
  'approvals.mcp_reload_confirm': (
    '重载 MCP 前确认',
    '执行 /reload-mcp 重建 MCP 工具前先确认，因为这会使提示词缓存失效，下一条消息需重新发送完整输入。选择“始终批准”后会关闭此项。',
  ),
  'approvals.mode': (
    '危险命令审批模式',
    'manual = 每次都询问；smart = 由辅助模型自动批准低风险命令；off = 不审批，等同 --yolo。',
  ),
  'approvals.single_query_mode': (
    '单次查询审批策略',
    '单次查询（-q）运行遇到危险命令时的处理方式，这类运行没有人回答审批。deny = 直接拒绝，让智能体换其他办法；approve = 自动批准。',
  ),
  'approvals.smart_policy': (
    '智能审批附加规则',
    '追加到智能审批系统提示词中的规则，例如“涉及 /etc 的命令一律上报”。',
  ),
  'approvals.timeout': ('审批超时', '审批请求无人回应时，等待多少秒后按拒绝处理（CLI 和网关通用）。'),
  'approvals.unattended_mode': (
    '无人值守审批策略',
    'Webhook、API 服务等无法回复审批的平台遇到危险命令时的处理方式：deny = 直接拒绝，让智能体换其他办法；approve = 自动批准。',
  ),
  'attachments.storage': (
    '附件存放位置',
    'TUI 和桌面应用上传的文件与粘贴文本的存放位置。hermes-home = profile 目录下的 attachments，沙箱内也能读取；workspace = 会话工作区的 .hermes/attachments。远程（SSH）工作区始终使用 profile 目录。',
  ),
  'auth.adopt_external_logins': (
    '借用外部登录',
    'Hermes 没有可用登录时，借用并刷新 Codex CLI 和 Claude Code 的登录。两个程序共用一个登录可能互相挤掉；关闭则只使用 Hermes 自己的登录。',
  ),
  'auth.codex_login_flow': (
    'Codex 登录方式',
    '登录 OpenAI Codex 的方式。device_code = 打开网址并输入验证码；browser = 通过本机浏览器回调登录，适用于禁用验证码登录的组织，端口被占用时退回验证码方式。',
  ),
  'auxiliary.approval.api_key': (
    '智能审批 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.approval.base_url': (
    '智能审批接口地址',
    '智能审批改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.approval.model': (
    '智能审批模型',
    '智能审批（判断命令风险的分类模型）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。建议使用快速、便宜的模型。',
  ),
  'auxiliary.approval.provider': (
    '智能审批提供方',
    '智能审批（判断命令风险的分类模型）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.approval.reasoning_effort': (
    '智能审批推理强度',
    '智能审批的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.approval.timeout': ('智能审批超时', '智能审批单次调用的超时时间（秒）。'),
  'auxiliary.background_review.api_key': (
    '后台复盘 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.background_review.base_url': (
    '后台复盘接口地址',
    '后台复盘改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.background_review.enabled': (
    '后台复盘',
    '每轮结束后按需自动派生后台复盘，保存记忆或修补技能。关闭后不再自动运行，/refine 仍可手动使用。',
  ),
  'auxiliary.background_review.model': (
    '后台复盘模型',
    '后台复盘（每轮结束后整理记忆和技能）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.background_review.provider': (
    '后台复盘提供方',
    '后台复盘（每轮结束后整理记忆和技能）使用的提供方。auto 表示由主模型回放完整对话；改用其他模型时回放精简摘要，费用更低。',
  ),
  'auxiliary.background_review.reasoning_effort': (
    '后台复盘推理强度',
    '后台复盘的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。复盘沿用主模型时此项不生效。',
  ),
  'auxiliary.background_review.timeout': ('后台复盘超时', '后台复盘单次调用的超时时间（秒）。'),
  'auxiliary.compression.api_key': (
    '上下文压缩 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.compression.base_url': (
    '上下文压缩接口地址',
    '上下文压缩改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.compression.model': (
    '上下文压缩模型',
    '上下文压缩（为长会话生成摘要）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.compression.no_progress_timeout': (
    '压缩无进展超时',
    '流式压缩调用连续多少秒没有实质内容就判定失败，转入重试或备用；留空则使用内置 60 秒。与压缩超时相互独立。',
  ),
  'auxiliary.compression.provider': (
    '上下文压缩提供方',
    '上下文压缩（为长会话生成摘要）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.compression.reasoning_effort': (
    '上下文压缩推理强度',
    '上下文压缩的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.compression.timeout': ('上下文压缩超时', '上下文压缩单次调用的超时时间（秒）。使用本地模型时可调高。'),
  'auxiliary.curator.api_key': (
    '技能整理 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.curator.base_url': (
    '技能整理接口地址',
    '技能整理改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.curator.model': (
    '技能整理模型',
    '技能整理（审查技能使用情况）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.curator.provider': (
    '技能整理提供方',
    '技能整理（审查技能使用情况）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.curator.reasoning_effort': (
    '技能整理推理强度',
    '技能整理的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.curator.timeout': (
    '技能整理超时',
    '技能整理单次调用的超时时间（秒）。推理模型审查大量技能时可能需要数分钟。',
  ),
  'auxiliary.free_only': (
    '仅用免费模型',
    '开启后，自动选择中的 OpenRouter 步骤只使用以 :free 结尾的免费模型，后台辅助任务不会走付费通道。',
  ),
  'auxiliary.goal_judge.api_key': (
    '目标判定 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.goal_judge.base_url': (
    '目标判定接口地址',
    '目标判定改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.goal_judge.model': (
    '目标判定模型',
    '目标判定（/goal 每轮后判断目标是否达成）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.goal_judge.provider': (
    '目标判定提供方',
    '目标判定（/goal 每轮后判断目标是否达成）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.goal_judge.reasoning_effort': (
    '目标判定推理强度',
    '目标判定的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.goal_judge.timeout': ('目标判定超时', '目标判定单次调用的超时时间（秒）。'),
  'auxiliary.kanban_decomposer.api_key': (
    '看板拆分 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.kanban_decomposer.base_url': (
    '看板拆分接口地址',
    '看板任务拆分改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.kanban_decomposer.model': (
    '看板拆分模型',
    '看板任务拆分（把任务拆成子任务结构）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.kanban_decomposer.provider': (
    '看板拆分提供方',
    '看板任务拆分（把任务拆成子任务结构）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.kanban_decomposer.reasoning_effort': (
    '看板拆分推理强度',
    '看板任务拆分的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.kanban_decomposer.timeout': ('看板拆分超时', '看板任务拆分单次调用的超时时间（秒）。'),
  'auxiliary.mcp.api_key': (
    'MCP 采样 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.mcp.base_url': (
    'MCP 采样接口地址',
    'MCP 采样改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.mcp.model': (
    'MCP 采样模型',
    'MCP 采样（MCP 服务器请求代为调用模型）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.mcp.provider': (
    'MCP 采样提供方',
    'MCP 采样（MCP 服务器请求代为调用模型）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.mcp.reasoning_effort': (
    'MCP 采样推理强度',
    'MCP 采样的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.mcp.timeout': ('MCP 采样超时', 'MCP 采样单次调用的超时时间（秒）。'),
  'auxiliary.memory_query_rewrite.api_key': (
    '记忆查询改写 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.memory_query_rewrite.base_url': (
    '记忆查询改写接口地址',
    '记忆查询改写改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.memory_query_rewrite.model': (
    '记忆查询改写模型',
    '记忆查询改写（把最新消息改写成记忆检索语句）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.memory_query_rewrite.provider': (
    '记忆查询改写提供方',
    '记忆查询改写（把最新消息改写成记忆检索语句）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.memory_query_rewrite.timeout': ('记忆查询改写超时', '记忆查询改写单次调用的超时时间（秒）。'),
  'auxiliary.moa_aggregator.api_key': (
    'MoA 汇总 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.moa_aggregator.base_url': (
    'MoA 汇总接口地址',
    '混合智能体（/moa）汇总步骤改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.moa_aggregator.model': (
    'MoA 汇总模型',
    '混合智能体（/moa）汇总步骤使用的模型名。汇总模型一般在 MoA 预设中指定。',
  ),
  'auxiliary.moa_aggregator.provider': (
    'MoA 汇总提供方',
    '混合智能体（/moa）汇总步骤使用的提供方。汇总模型一般在 MoA 预设中指定。',
  ),
  'auxiliary.moa_aggregator.timeout': (
    'MoA 汇总超时',
    '混合智能体（/moa）汇总步骤单次调用的超时时间（秒）。',
  ),
  'auxiliary.moa_reference.api_key': (
    'MoA 参考 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.moa_reference.base_url': (
    'MoA 参考接口地址',
    '混合智能体（/moa）参考模型改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.moa_reference.model': (
    'MoA 参考模型',
    '混合智能体（/moa）参考模型使用的模型名。各参考模型一般在 MoA 预设中逐个指定。',
  ),
  'auxiliary.moa_reference.provider': (
    'MoA 参考提供方',
    '混合智能体（/moa）参考模型使用的提供方。各参考模型一般在 MoA 预设中逐个指定。',
  ),
  'auxiliary.moa_reference.timeout': (
    'MoA 参考超时',
    '混合智能体（/moa）参考模型单次调用的超时时间（秒）；调用未单独指定超时时使用此值。',
  ),
  'auxiliary.monitor.api_key': (
    '监控评分 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.monitor.base_url': (
    '监控评分接口地址',
    '监控评分改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.monitor.model': (
    '监控评分模型',
    '监控评分（为定时监控抓取的邮件、订阅等条目评估紧急程度）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。调用量大，小模型即可。',
  ),
  'auxiliary.monitor.provider': (
    '监控评分提供方',
    '监控评分（为定时监控抓取的邮件、订阅等条目评估紧急程度）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.monitor.reasoning_effort': (
    '监控评分推理强度',
    '监控评分的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.monitor.timeout': ('监控评分超时', '监控评分单次调用的超时时间（秒）。'),
  'auxiliary.openrouter_model': (
    'OpenRouter 备用模型',
    '自动选择中 OpenRouter 步骤使用的模型，默认是付费模型；可配合“仅用免费模型”填写 :free 模型。',
  ),
  'auxiliary.profile_describer.api_key': (
    'profile 简介 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.profile_describer.base_url': (
    'profile 简介接口地址',
    'profile 简介生成改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.profile_describer.model': (
    'profile 简介模型',
    'profile 简介生成（自动写一两句 profile 介绍）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.profile_describer.provider': (
    'profile 简介提供方',
    'profile 简介生成（自动写一两句 profile 介绍）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.profile_describer.reasoning_effort': (
    'profile 简介推理强度',
    'profile 简介生成的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.profile_describer.timeout': (
    'profile 简介超时',
    'profile 简介生成单次调用的超时时间（秒）。',
  ),
  'auxiliary.review.api_key': (
    '审查 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.review.api_mode': (
    '审查接口模式',
    '强制 /review 审查使用的接口类型：chat_completions、anthropic_messages 或 codex_responses；留空则不强制。',
  ),
  'auxiliary.review.base_url': (
    '审查接口地址',
    '/review 审查改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.review.model': (
    '审查模型',
    '/review 审查子智能体使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.review.provider': (
    '审查提供方',
    '/review 审查子智能体（独立复查刚讨论的代码、文档等）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.skills_hub.api_key': (
    '技能中心 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.skills_hub.base_url': (
    '技能中心接口地址',
    '技能中心改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.skills_hub.model': (
    '技能中心模型',
    '技能中心（搜索与安装技能）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.skills_hub.provider': (
    '技能中心提供方',
    '技能中心（搜索与安装技能）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.skills_hub.reasoning_effort': (
    '技能中心推理强度',
    '技能中心的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.skills_hub.timeout': ('技能中心超时', '技能中心单次调用的超时时间（秒）。'),
  'auxiliary.stream_only_base_urls': (
    '仅流式接口',
    '不支持非流式调用的接口 URL 片段（不区分大小写）；匹配的辅助调用会改用流式请求并合并结果。',
  ),
  'auxiliary.title_generation.api_key': (
    '标题生成 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.title_generation.base_url': (
    '标题生成接口地址',
    '会话标题生成改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.title_generation.enabled': ('自动生成标题', '首轮对话后自动生成会话标题；关闭则不生成。'),
  'auxiliary.title_generation.language': (
    '标题语言',
    '生成标题使用的语言，例如 English；留空则跟随用户所用语言。',
  ),
  'auxiliary.title_generation.model': (
    '标题生成模型',
    '会话标题生成使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.title_generation.model_upgrade_enabled': (
    '模型优化标题',
    '先显示即时生成的标题，再调用模型生成更合适的标题；关闭则保留即时标题，不调用模型。',
  ),
  'auxiliary.title_generation.prefer_fast_model': (
    '优先快速模型',
    '开启后，标题生成改用当前提供方的快速档模型；关闭时 auto 沿用主模型。',
  ),
  'auxiliary.title_generation.provider': (
    '标题生成提供方',
    '会话标题生成使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.title_generation.reasoning_effort': (
    '标题生成推理强度',
    '会话标题生成的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.title_generation.timeout': ('标题生成超时', '会话标题生成单次调用的超时时间（秒）。'),
  'auxiliary.transient_retries': (
    '辅助调用临时重试',
    '辅助调用遇到连接重置、超时、5xx 等临时故障时，先在同一提供方重试的次数，之后才切换备用；范围 0 到 6。',
  ),
  'auxiliary.triage_specifier.api_key': (
    '看板细化 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.triage_specifier.base_url': (
    '看板细化接口地址',
    '看板需求细化改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.triage_specifier.model': (
    '看板细化模型',
    '看板需求细化（把一句话任务扩写成详细说明）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。便宜的模型即可。',
  ),
  'auxiliary.triage_specifier.provider': (
    '看板细化提供方',
    '看板需求细化（把一句话任务扩写成详细说明）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.triage_specifier.reasoning_effort': (
    '看板细化推理强度',
    '看板需求细化的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.triage_specifier.timeout': ('看板细化超时', '看板需求细化单次调用的超时时间（秒）。'),
  'auxiliary.tts_audio_tags.api_key': (
    '语音合成标签 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.tts_audio_tags.base_url': (
    '语音合成标签接口地址',
    '语音合成标签插入改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.tts_audio_tags.model': (
    '语音合成标签模型',
    '语音合成标签插入（为 Gemini 语音合成加入表达语气的音频标签）使用的模型名；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.tts_audio_tags.provider': (
    '语音合成标签提供方',
    '语音合成标签插入（为 Gemini 语音合成加入表达语气的音频标签）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.tts_audio_tags.reasoning_effort': (
    '语音合成标签推理强度',
    '语音合成标签插入的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.tts_audio_tags.timeout': ('语音合成标签超时', '语音合成标签插入单次调用的超时时间（秒）。'),
  'auxiliary.vision.api_key': (
    '视觉分析 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.vision.base_url': (
    '视觉分析接口地址',
    '图片分析改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.vision.download_timeout': (
    '图片下载超时',
    '下载待分析图片的 HTTP 超时时间（秒）；网络较慢或使用自建图片服务器时可调高。',
  ),
  'auxiliary.vision.model': (
    '视觉分析模型',
    '图片分析（vision_analyze 工具与浏览器截图）使用的模型名，需支持看图；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.vision.provider': (
    '视觉分析提供方',
    '图片分析（vision_analyze 工具与浏览器截图）使用的提供方。auto 表示沿用主模型。',
  ),
  'auxiliary.vision.reasoning_effort': (
    '视觉分析推理强度',
    '图片分析的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.vision.timeout': ('视觉分析超时', '视觉模型 API 单次调用的超时时间（秒）。'),
  'auxiliary.voice_chat.api_key': (
    '语音对话 API 密钥',
    '配合自定义接口地址使用的 API 密钥；留空则使用 OPENAI_API_KEY。',
  ),
  'auxiliary.voice_chat.base_url': (
    '语音对话接口地址',
    '语音对话轮次改用的 OpenAI 兼容接口 URL；填写后优先于提供方设置。',
  ),
  'auxiliary.voice_chat.model': (
    '语音对话模型',
    '语音对话轮次使用的模型名，可选比主模型更快的模型；留空则使用提供方默认模型（提供方为 auto 时即主模型）。',
  ),
  'auxiliary.voice_chat.provider': (
    '语音对话提供方',
    '语音输入的对话轮次使用的提供方，可改用比主模型更快的模型。auto 表示沿用主模型。',
  ),
  'auxiliary.voice_chat.reasoning_effort': (
    '语音对话推理强度',
    '语音对话轮次的推理强度：none、minimal、low、medium、high、xhigh、max 或 ultra；留空则使用提供方默认。',
  ),
  'auxiliary.voice_chat.timeout': ('语音对话超时', '语音对话轮次单次调用的超时时间（秒）。'),
  'bedrock.discovery.enabled': (
    '自动发现模型',
    '通过 Bedrock 的 ListFoundationModels 接口自动发现可用模型。仅在提供方为 Bedrock 时生效。',
  ),
  'bedrock.discovery.provider_filter': (
    '模型发现提供方筛选',
    '只发现这些厂商的模型，例如 anthropic、amazon。留空则不限制。',
  ),
  'bedrock.discovery.refresh_interval': ('模型发现缓存时长', '模型发现结果的缓存时间，单位为秒。'),
  'bedrock.guardrail.guardrail_identifier': (
    'Guardrails 标识符',
    '在 AWS 控制台创建的 Bedrock Guardrails 的 ID，需与版本一起设置。',
  ),
  'bedrock.guardrail.guardrail_version': (
    'Guardrails 版本',
    '要使用的 Guardrails 版本，例如 1 或 DRAFT。',
  ),
  'bedrock.guardrail.stream_processing_mode': (
    'Guardrails 流式处理方式',
    '流式输出时 Guardrails 的处理方式：sync（同步）或 async（异步）。',
  ),
  'bedrock.guardrail.trace': (
    'Guardrails 追踪',
    'Guardrails 追踪信息：enabled（开启）、disabled（关闭）或 enabled_full（完整）。',
  ),
  'bedrock.region': (
    'AWS 区域',
    'Bedrock 使用的 AWS 区域。留空则读取 AWS_REGION 环境变量，未设置时使用 us-east-1。',
  ),
  'bot_desktop.auto_start': ('自动启动屏幕', '在无显示器的主机上，操作电脑首次需要屏幕时自动启动 Bot 桌面。'),
  'bot_desktop.geometry': ('屏幕分辨率', 'Bot 桌面屏幕的尺寸，格式如 1440x900。'),
  'bot_desktop.idle_stop_minutes': (
    '闲置自动停止',
    '屏幕无人使用（没有操作电脑、浏览器、查看或接管）达到该分钟数后自动停止，下次使用时重新启动。0 = 保持运行直到手动停止。',
  ),
  'bot_desktop.min_free_memory_mb': (
    '启动所需最低空闲内存',
    '空闲内存（主机或容器限制中较紧的一个）低于该值（MB）时拒绝启动屏幕。0 = 不检查。',
  ),
  'bot_desktop.placement': (
    '屏幕运行位置',
    'Bot 桌面（以及操作电脑和 Bot 的浏览器）在哪里运行：auto = 跟随终端后端；terminal = 始终在终端沙箱内；gateway = 始终在网关主机上，此时操作发生在沙箱之外。',
  ),
  'bot_mode.envelope_ttl_seconds': (
    '待投递消息有效期',
    'Bot 之间排队等待投递的消息超过该秒数后不再投递，发送方会收到过期错误。0 = 投递时不检查过期。',
  ),
  'bot_mode.turn_wait_seconds': (
    '目标忙碌时等待时长',
    '向正在运行一轮对话的 Bot 投递消息时最多排队等待的秒数，超时返回“目标忙碌”错误。',
  ),
  'browser.allow_private_urls': (
    '允许访问内网地址',
    '允许浏览器打开局域网、localhost 等内网地址（沿用旧的 security.allow_private_urls）。本地 Chromium 和辅助 Chromium 不受此项影响。',
  ),
  'browser.auto_local_for_private_urls': (
    '内网地址改用本地浏览器',
    '使用云端浏览器服务时，局域网和 localhost 地址改在本机的 Chromium 中打开。关闭则拒绝打开内网地址。',
  ),
  'browser.cdp_url': ('CDP 连接地址', '持久的 CDP 端点地址，用于连接已在运行的 Chromium 或 Chrome。'),
  'browser.chromium_args': (
    'Chromium 启动参数',
    '本地会话启动 Chromium 时附加的参数，例如 --lang=de。',
  ),
  'browser.command_timeout': (
    '浏览器启动超时',
    '本地 Chromium 启动并打开调试端口的等待时间，单位为秒（最少 5 秒）。每次启动至少等待 120 秒。',
  ),
  'browser.dialog_policy': (
    '网页弹窗处理方式',
    '网页弹出对话框时的处理方式：must_respond（由智能体回应）、auto_dismiss（自动关闭）、auto_accept（自动确认）。仅在支持 CDP 的浏览器后端生效。',
  ),
  'browser.dialog_timeout_s': (
    '弹窗自动关闭时限',
    '在 must_respond 方式下，弹窗超过该秒数未处理则自动关闭。',
  ),
  'browser.engine': (
    '本地浏览器引擎',
    'auto = Chromium；lightpanda = 每个会话运行 Lightpanda（导航更快，但不能截图）；chrome 视同 auto。使用云端服务、cdp_url 或真实浏览器登录时忽略。',
  ),
  'browser.executable_path': (
    'Chromium 程序路径',
    '本地会话使用的 Chromium 可执行文件。留空则使用 hermes pm install chromium 安装的版本、Docker 镜像自带版本或系统中的 Chromium。',
  ),
  'browser.headed': (
    '显示浏览器窗口',
    '以可见窗口运行本地浏览器，并在各轮对话之间保持窗口打开；闲置会话仍会在 browser.inactivity_timeout 后关闭。',
  ),
  'browser.inactivity_timeout': ('浏览器闲置超时', '浏览器会话无活动超过该秒数后自动关闭（最少 30 秒）。'),
  'browser.real_profile_autoclose': (
    '关闭占用资料的浏览器',
    '仅 Windows：真实浏览器正在运行并锁定 Cookie 时，智能体先征求同意，获准后关闭该浏览器（未保存的标签页会丢失）以便复制个人资料。不会自动强制关闭。',
  ),
  'browser.real_profile_pin': (
    '指定浏览器个人资料',
    '指定要复制的源个人资料目录，例如 Profile 2。留空则使用浏览器最近使用的个人资料；指定的目录不存在时会使用未登录的新浏览器。',
  ),
  'browser.use_real_profile': (
    '使用真实浏览器登录',
    '允许在本地用你真实的登录状态浏览：复制当前默认 Chromium 个人资料（Cookie、登录信息、偏好设置）的快照来运行。关闭时会删除该快照。仅支持 Chromium 系浏览器。',
  ),
  'browser.user_data_dir': (
    '浏览器资料目录',
    '本地会话共用的持久 Chromium 个人资料目录。留空则每个会话使用一次性的临时资料。',
  ),
  'checkpoints.auto_prune': (
    '自动清理检查点',
    '后台定期删除超过保留天数的项目检查点，并控制总容量。不会删除工作目录已不存在的检查点。',
  ),
  'checkpoints.enabled': ('文件检查点', '每轮对话首次写入文件时为工作目录保存快照，可用 /rollback 恢复。'),
  'checkpoints.max_file_size_mb': ('单文件大小上限', '保存快照时跳过大于该值（MB）的文件。0 = 不过滤。'),
  'checkpoints.max_snapshots': ('每目录最多检查点', '每个工作目录保留的检查点数量上限，更早的会被清理。'),
  'checkpoints.max_total_size_mb': (
    '检查点总容量上限',
    '所有检查点占用空间的上限（MB），超出时依次删除各项目最早的检查点。0 = 不限制。',
  ),
  'checkpoints.min_interval_hours': ('自动清理间隔', '后台自动清理最多每隔多少小时运行一次。'),
  'checkpoints.retention_days': ('检查点保留天数', '超过该天数未使用的项目检查点会在自动清理时删除。'),
  'code_execution.kernel_idle_timeout': ('内核闲置回收时间', '代码执行内核闲置超过该秒数后被回收。'),
  'code_execution.max_session_kernels': (
    '最多同时保留内核数',
    '同时保留的代码执行内核数量上限，超出时回收最久未用的内核。',
  ),
  'code_execution.mode': (
    '代码执行模式',
    'project = 在会话工作目录中用当前项目的 Python 环境运行，可使用项目依赖；strict = 在隔离的临时目录中用 Hermes 自带的 Python 运行，隔离性最高但无法使用项目依赖。',
  ),
  'command_allowlist': ('永久允许的命令', '已永久允许的危险命令模式，在审批时选择“始终允许”后加入。'),
  'compression.abort_on_summary_failure': (
    '摘要失败时中止压缩',
    '自动压缩生成摘要失败时中止，而不是用“摘要不可用”占位替换中间内容；会话会停在当前大小，直到使用 /compress 或 /new。',
  ),
  'compression.checkpoint_required': (
    '压缩前要求记忆检查点',
    '只有支持检查点的记忆提供方确认已保存检查点后才进行压缩，否则保留未压缩的记录以便稍后重试。',
  ),
  'compression.codex_app_server_auto': (
    'Codex 线程压缩方式',
    'Codex app-server 运行时的线程压缩方式：native = 由 Codex 自行决定；hermes = 由 Hermes 的阈值触发；off = Hermes 不自动触发。',
  ),
  'compression.codex_gpt55_autoraise': (
    'Codex 订阅提高压缩阈值',
    '通过 ChatGPT Codex OAuth 使用 gpt-5.4、gpt-5.5、gpt-5.6 等模型时，把压缩触发点提高到 85%。关闭则使用全局触发比例。',
  ),
  'compression.codex_gpt55_autoraise_notice': (
    '提高阈值提示',
    '显示一次性的阈值提高提示。关闭只隐藏提示，仍会提高阈值。',
  ),
  'compression.codex_responses_compact_threshold': (
    '服务端压缩触发点',
    'OpenAI 服务端压缩的触发 token 数。留空则跟随本地压缩触发点并留出安全余量；填写正整数时只会向下调整。',
  ),
  'compression.codex_responses_native': (
    'OpenAI 服务端压缩',
    '在 Responses API 上启用 OpenAI 服务端压缩，仅适用于直连 api.openai.com 或 Codex 的 gpt-5.6 系列等模型；本地压缩仍作为备用。',
  ),
  'compression.context_timeout_seconds': (
    '压缩无进展超时',
    '智能体内的压缩（对话中、/compress、预检）在没有进展时最多等待的秒数。0 = 关闭此限制。',
  ),
  'compression.context_total_ceiling_seconds': (
    '压缩总等待上限',
    '智能体内的压缩在生成摘要阶段的最长总等待秒数，即使仍在输出也不超过此值。',
  ),
  'compression.enabled': ('自动上下文压缩', '对话接近模型上下文上限时，自动把中间轮次总结成摘要以腾出空间。'),
  'compression.hygiene_failure_cooldown_seconds': (
    '整理失败冷却时间',
    '网关会话整理压缩失败后，在该秒数内跳过重复尝试。',
  ),
  'compression.hygiene_hard_message_limit': ('整理强制压缩消息数', '网关会话的消息数达到该值时强制压缩。'),
  'compression.hygiene_max_turn_hold_seconds': (
    '整理时消息最长等待',
    '网关正在生成整理摘要时，新到的用户消息最多等待的秒数；超时后该轮不压缩直接继续，摘要稍后再采用。',
  ),
  'compression.hygiene_timeout_seconds': (
    '整理无进展超时',
    '网关在智能体运行前等待整理压缩的秒数，只计算没有进展的时间。',
  ),
  'compression.hygiene_total_ceiling_seconds': (
    '整理总等待上限',
    '网关整理压缩的最长总等待秒数，即使仍在输出也不超过此值。',
  ),
  'compression.idle_compact_after_seconds': (
    '闲置后压缩',
    '会话闲置超过该秒数后再次使用时，先压缩历史再回复；上下文已经很小时跳过。0 = 关闭。',
  ),
  'compression.in_place': (
    '原地压缩',
    '压缩时保留原会话 ID，不另建新会话；压缩前的内容在同一会话中归档，仍可搜索。关闭则使用旧的轮换会话方式。',
  ),
  'compression.max_attempts': ('最多压缩重试次数', '一轮对话中压缩重试的最多次数，超过后放弃。最小 1，最大 10。'),
  'compression.micro_compact': (
    '每轮微压缩',
    '每轮结束后把最早的一段对话并入滚动摘要，分摊压缩开销。每次都会使提示词缓存失效。',
  ),
  'compression.micro_compact_defrag_threshold_tokens': (
    '滚动摘要重整阈值',
    '滚动摘要超过该 token 数时，下一次会重新总结它。',
  ),
  'compression.micro_compact_every_n_turns': (
    '微压缩间隔轮数',
    '每隔多少轮执行一次微压缩（最小 1）。仅在开启微压缩时生效。',
  ),
  'compression.min_tail_user_messages': ('保留最近用户消息数', '压缩后至少原样保留的最近真实用户消息条数。'),
  'compression.prepare_ahead': (
    '提前准备摘要',
    '接近压缩触发点时在后台预先生成摘要；压缩时若仍覆盖相同消息则直接使用。',
  ),
  'compression.proactive_prune_min_reclaim_tokens': (
    '裁剪最少节省 token',
    '主动裁剪至少能节省该 token 数时才生效，以减少提示词缓存失效。0 = 不设最低节省。',
  ),
  'compression.proactive_prune_min_result_chars': (
    '裁剪结果最小长度',
    '主动裁剪只总结超过该字符数的工具结果（最小 200）。',
  ),
  'compression.proactive_prune_tokens': (
    '工具结果主动裁剪',
    '重新发送的历史超过该 token 数时，不调用模型直接去重、总结和截断旧的工具结果，最近的消息不受影响。可尝试 48000。0 = 关闭。',
  ),
  'compression.progress_notices': (
    '压缩进度提示',
    '在消息平台上也发送常规的压缩进度提示。压缩失败提示和手动 /compress 的反馈始终显示。',
  ),
  'compression.protect_first_n': (
    '保留开头消息数',
    '除系统提示词外，始终原样保留的开头消息条数。0 = 只保留系统提示词。',
  ),
  'compression.protect_last_n': ('保留最近消息数', '至少保留不压缩的最近消息条数。'),
  'compression.tail_mode': (
    '保留尾部方式',
    'lean = 保留较短的最近内容，并在摘要中加入索引和用户原话，占用 token 更少；legacy = 按触发比例原样保留较长的最近内容。',
  ),
  'compression.target_ratio': (
    '保留尾部比例',
    '压缩后按触发阈值的该比例保留最近内容，例如 0.20 表示保留阈值的 20%。范围 0.10–0.80。',
  ),
  'compression.threshold': (
    '压缩触发比例',
    '上下文用量达到模型上下文窗口的该比例时触发压缩。窗口小于 512K 的模型最低按 0.75 计算。',
  ),
  'compression.threshold_tokens': (
    '压缩触发 token 数',
    '可选的绝对 token 上限；设置后取它与触发比例中较低者触发压缩。留空则只按比例。',
  ),
  'computer_use.allow_unsigned_driver': (
    '允许未签名驱动',
    '仅 macOS：允许使用未签名的 CuaDriver.app。仅用于从源码开发驱动。',
  ),
  'computer_use.autostart': (
    '登录时启动驱动',
    '仅 Windows：注册登录时启动 cua-driver 的计划任务，通过 SSH 操控 Windows 时需要开启。关闭则按需启动。',
  ),
  'computer_use.ax_max_elements': (
    '无障碍元素读取上限',
    '每次截取界面时读取无障碍树的元素数量上限。0 = 使用驱动默认值。',
  ),
  'computer_use.capability_manifest': (
    '能力清单路径',
    '权限模式为 bounded 时使用的已审核能力清单文件路径。',
  ),
  'computer_use.capture_after_mode': (
    '操作后截取方式',
    'som = 截图并叠加标注；ax = 只读取界面元素，不截图（更快）；vision = 只截图。',
  ),
  'computer_use.cua_telemetry': (
    'cua-driver 遥测',
    '允许 cua-driver 上游的遥测。关闭时 Hermes 会为其禁用遥测。',
  ),
  'computer_use.max_image_dimension': (
    '截图最长边',
    '驱动截图最长边的像素上限，用于减小发送给模型的图片。0 = 不限制。',
  ),
  'computer_use.native_wayland': (
    '原生 Wayland 支持',
    '仅 Linux：有 Wayland 显示时让 cua-driver 使用原生 Wayland。修改后需重启网关。',
  ),
  'computer_use.no_overlay': (
    '关闭光标叠加层',
    '关闭 cua-driver 的光标叠加层（闲置时可能占满一个 CPU 核心）。留空 = 自动（macOS 和无头或 WSL2 的 Linux 上关闭）；true = 始终关闭；false = 始终开启。',
  ),
  'computer_use.permission_mode': (
    '操作电脑权限模式',
    'standard = 使用 cua-driver 自带的审批；bounded = 运行时不弹出审批，超出能力清单的操作一律拒绝。',
  ),
  'context.engine': ('上下文管理引擎', '管理对话上下文的引擎。默认使用内置的上下文压缩器，也可选择插件提供的引擎。'),
  'context.memory_trim.cooldown_seconds': ('内存释放冷却时间', '两次向系统释放空闲内存之间至少间隔的秒数。'),
  'context.memory_trim.enabled': (
    '释放空闲内存',
    '在智能体和界面清理时把已释放的内存归还给系统（仅 glibc 环境有效）。',
  ),
  'context.memory_trim.info_log_min_delta_mb': (
    '内存释放日志阈值',
    '释放的内存小于该值（MB）时不写 INFO 日志。0 = 全部记录。',
  ),
  'context.memory_trim.log_every_n': (
    '内存释放日志频率',
    '定期释放时每 N 次写一条 INFO 日志；强制释放始终记录。',
  ),
  'context_file_max_chars': (
    '上下文文件字符上限',
    '单个自动加载的上下文文件（SOUL.md、AGENTS.md 等）超过该字符数时截断首尾。留空则随模型上下文窗口自动调整。',
  ),
  'context_file_read_timeout': (
    '上下文文件读取超时',
    '读取单个上下文文件的最长等待秒数，超时则跳过并提示，避免网络文件系统卡住启动。',
  ),
  'cron.allow_agent_scheduling': (
    '允许定时任务再建任务',
    '允许定时任务中的智能体使用定时任务工具集创建任务。默认禁止，以免无人值守时循环创建。',
  ),
  'cron.catch_up_missed': ('补跑错过的任务', '停机后补跑错过的周期任务。关闭则跳过超出宽限时间的错过任务。'),
  'cron.chronos.callback_url': (
    'Chronos 回调地址',
    '本智能体可公开访问的基础 URL，Chronos 会向其 /api/cron/fire 发送触发请求。留空则 Chronos 不可用，改用内置调度。',
  ),
  'cron.chronos.expected_audience': (
    'Chronos 令牌受众',
    '触发令牌（JWT）预期的 audience，例如 agent:{instance_id}。',
  ),
  'cron.chronos.nas_jwks_url': (
    'Chronos 签名公钥地址',
    '用于验证触发令牌签名的 NAS JWKS URL。留空则拒绝所有触发请求。',
  ),
  'cron.chronos.portal_url': (
    'Chronos 门户地址',
    '负责安排和取消一次性触发并签发触发令牌的 NAS 门户基础 URL。',
  ),
  'cron.delivery.notify': (
    '投递时推送通知',
    '把定时任务结果作为需要推送提醒的消息发送（例如 Telegram）。关闭则静默发送。',
  ),
  'cron.failure_repeat_alert_hours': (
    '重复失败提醒间隔',
    '同一错误重复失败时只提醒一次，之后每隔该小时数再提醒一次。0 = 每次失败都提醒。',
  ),
  'cron.max_parallel_jobs': (
    '最多并行任务数',
    '每次调度最多同时运行的到期任务数。留空或 0 = 不限制；1 = 逐个运行。',
  ),
  'cron.media_send_timeout_seconds': ('媒体发送超时', '通过网关投递时，每个媒体附件的发送超时秒数。'),
  'cron.mirror_delivery': (
    '可接续的投递',
    '让定时任务的投递可以直接回复并带着上下文继续对话。关闭则投递只保留在任务自己的会话中。',
  ),
  'cron.model': ('定时任务模型', '定时任务默认使用的模型。留空则使用主模型；单个任务指定的模型优先。'),
  'cron.model_provider': ('定时任务模型提供方', '与定时任务模型配套的推理提供方。留空则按全局配置解析。'),
  'cron.output_retention': ('输出保留份数', '每个任务保留最近多少份输出文件。0 或负数 = 不清理。'),
  'cron.preflight': (
    '运行前检查',
    '运行前检查 API 密钥、技能和投递平台是否就绪；失败则只提醒一次，不调用模型。关闭则在运行中报错。',
  ),
  'cron.provider': (
    '调度提供方',
    '决定任务何时触发的调度器。留空则使用内置的每 60 秒检查一次的调度器；也可填写已安装的调度插件，例如 chronos。',
  ),
  'cron.require_restart_safe_scope': (
    '要求安全运行范围',
    '托管的 systemd 网关没有用户会话时：关闭则直接以子进程运行任务（无 cgroup 隔离）；开启则拒绝运行并提示启用 linger。',
  ),
  'cron.script_timeout_seconds': ('脚本任务超时', '不使用智能体的脚本型定时任务的超时秒数。'),
  'cron.session_db_timeout_seconds': (
    '会话数据库打开超时',
    '定时任务中打开会话数据库的超时秒数。0 = 不限制。',
  ),
  'cron.wrap_response': ('包装投递内容', '投递结果时加上任务名标题和“智能体看不到此消息”的页脚。关闭则只发送原始内容。'),
  'curator.archive_after_days': ('自动归档天数', '技能闲置超过该天数后移入归档（可恢复）。'),
  'curator.archive_ttl_days': (
    '归档保留天数',
    '执行 hermes curator purge 时删除归档超过该天数的技能，不会自动执行。0 = 永不删除。',
  ),
  'curator.backup.enabled': (
    '整合前备份',
    '用模型整合技能内容前先为技能目录做快照，可用 hermes curator rollback 恢复。',
  ),
  'curator.backup.keep': ('备份保留份数', '保留最近多少份备份快照。'),
  'curator.consolidate': ('用模型整合技能', '开启后用辅助模型合并整理技能；关闭则只按闲置时间清理，不产生模型费用。'),
  'curator.enabled': ('技能整理', '定期整理技能：标记过时的技能，并归档长期未用的技能。'),
  'curator.interval_hours': ('整理间隔', '两次技能整理之间间隔的小时数。'),
  'curator.min_idle_hours': ('整理前闲置时长', '智能体闲置至少该小时数后才运行整理。'),
  'curator.prune_builtins': (
    '清理内置技能',
    '让内置技能也像智能体创建的技能一样按闲置时间归档。从技能中心安装的技能永不清理。',
  ),
  'curator.stale_after_days': ('标记过时天数', '技能闲置超过该天数后标记为过时。'),
  'dashboard.basic_auth.password': (
    '登录密码',
    '控制台用户名密码登录的明文密码，会在内存中哈希；建议改用密码哈希。',
  ),
  'dashboard.basic_auth.password_hash': (
    '登录密码哈希',
    '控制台登录密码的 scrypt 哈希，优先于明文密码。',
  ),
  'dashboard.basic_auth.secret': (
    '会话签名密钥',
    '用于签名登录会话令牌的密钥。留空则每次启动随机生成，重启后需要重新登录。建议使用 32 字节以上的随机值。',
  ),
  'dashboard.basic_auth.session_ttl_seconds': (
    '登录有效期',
    '登录会话的有效秒数。0 = 使用插件默认值（12 小时）。',
  ),
  'dashboard.basic_auth.username': ('登录用户名', '控制台用户名密码登录的用户名。留空则不启用。'),
  'dashboard.compute_host_heartbeat_secs': (
    '计算子进程心跳间隔',
    '开启轮次隔离时，计算子进程发送心跳的间隔秒数。',
  ),
  'dashboard.compute_host_respawn_max': (
    '计算子进程重启上限',
    '计算子进程崩溃后，5 分钟内最多自动重启的次数。',
  ),
  'dashboard.drain_auth.min_secret_chars': (
    '排空密钥最短长度',
    '排空控制接口认证密钥的最少字符数，过弱的密钥会被拒绝。',
  ),
  'dashboard.drain_auth.scope': ('排空令牌权限范围', '排空控制令牌被授予的权限范围名称。'),
  'dashboard.oauth.client_id': (
    'OAuth 客户端 ID',
    '控制台 OAuth 登录使用的客户端 ID，由 Nous Portal 分配。留空则不启用。',
  ),
  'dashboard.oauth.portal_url': (
    'OAuth 门户地址',
    '控制台 OAuth 登录使用的 Nous Portal 地址。留空则使用正式环境。',
  ),
  'dashboard.public_url': (
    '公开访问地址',
    '控制台对外的完整地址（含协议和主机，可带路径前缀），用于 OAuth 回调和访问校验。留空则根据请求头推断。',
  ),
  'dashboard.session_token_auth.enabled': (
    '会话令牌登录',
    '允许用预置的会话令牌访问受保护的控制台。关闭则不使用此方式。',
  ),
  'dashboard.show_token_analytics': (
    '显示 token 统计',
    '显示 token 和费用统计。这些数字只是本地的偏低估算，不是账单。',
  ),
  'dashboard.startup_orphan_sweep': (
    '启动时清理遗留会话',
    '网关启动时关闭因旧网关退出而残留为“活跃”状态的会话；这些会话仍可恢复。',
  ),
  'dashboard.theme': ('控制台主题', '网页控制台的视觉主题。'),
  'dashboard.trusted_proxies': (
    '受信任的代理',
    '允许提供 X-Forwarded-Proto/-For 请求头的反向代理 IP 或 CIDR。本机地址始终受信任。',
  ),
  'dashboard.turn_isolation': ('轮次进程隔离', '在独立的计算子进程中运行智能体的对话轮次。'),
  'dashboard.ws_orphan_activity_stale_s': (
    '断开后运行轮次闲置时限',
    '客户端断开后，仍在运行的轮次闲置达到该秒数才会被中断。0 = 宽限期结束即中断。',
  ),
  'dashboard.ws_orphan_reap_grace_s': (
    '断开连接宽限时间',
    '客户端断开后，等待该秒数再中断并回收会话。0 = 一直保留。',
  ),
  'dashboard.ws_ping_interval': (
    'WebSocket 心跳间隔',
    'WebSocket 保活 ping 的间隔秒数，仅对非本机连接生效。',
  ),
  'dashboard.ws_ping_timeout': (
    'WebSocket 心跳超时',
    '等待 WebSocket ping 回应的秒数，仅对非本机连接生效。',
  ),
  'database.journal_mode': (
    '数据库日志模式',
    'SQLite 日志模式：wal 或 delete。文件系统不能安全使用 WAL 时（如 NFS、SMB）设为 delete。',
  ),
  'database.journal_size_limit': (
    '日志文件大小上限',
    'WAL 或日志文件的大小上限，单位为字节。留空则使用 SQLite 默认值。',
  ),
  'database.wal_autocheckpoint': (
    'WAL 自动检查点页数',
    '每写入多少页自动执行一次 WAL 检查点。留空则使用 SQLite 默认值（1000 页）。',
  ),
  'delegation.api_key': (
    '子智能体 API 密钥',
    '用于子智能体接口地址的 API 密钥。留空则使用 OPENAI_API_KEY。',
  ),
  'delegation.api_mode': (
    '子智能体接口协议',
    '子智能体接口地址的协议：chat_completions、codex_responses 或 anthropic_messages。留空则根据 URL 自动判断。',
  ),
  'delegation.backend': (
    '委派策略',
    '决定每个委派任务如何路由：default 使用本节设置，也可使用插件提供的策略。指定的策略不可用时会直接报错。',
  ),
  'delegation.base_url': ('子智能体接口地址', '子智能体直接使用的 OpenAI 兼容接口地址。'),
  'delegation.child_timeout_seconds': (
    '子智能体无进展超时',
    '子智能体没有任何进展超过该秒数时判定失败（最少 30 秒）。0 = 不限制。',
  ),
  'delegation.compression_threshold_tokens': (
    '子智能体压缩触发上限',
    '子智能体压缩触发点的 token 上限，取它与比例阈值中较低者；需不少于 16000 才生效。0 = 与主智能体相同。',
  ),
  'delegation.fallback_providers': (
    '子智能体备用提供方',
    '子智能体的备用提供方链，格式与顶层设置相同。留空时未固定模型的子智能体沿用主智能体的设置；设为空列表则不使用备用。',
  ),
  'delegation.gateway_mode': (
    '网关中的委派方式',
    'inline = 在本轮内等待结果；background = 在后台运行；auto = 关闭中间消息时使用 inline。',
  ),
  'delegation.independent_completions': (
    '逐个返回后台结果',
    '后台批量委派时，每个任务完成后单独返回结果。关闭则全部完成后合并为一条消息返回。',
  ),
  'delegation.inherit_mcp_toolsets': (
    '保留 MCP 工具集',
    '为子智能体缩小工具集时，仍保留主智能体已启用的 MCP 工具集。关闭则严格取交集。',
  ),
  'delegation.max_concurrent_children': (
    '最多并行子智能体',
    '每批最多同时运行的子智能体数，最少 1。数值越大费用越高。',
  ),
  'delegation.max_iterations': ('子智能体最多轮数', '每个子智能体最多可进行的工具调用轮数。'),
  'delegation.max_spawn_depth': (
    '委派最大层数',
    '委派的最大层数：1 = 子智能体不再委派；2 = 子智能体可再委派一层。每多一层费用成倍增加。',
  ),
  'delegation.max_summary_chars': (
    '结果摘要字符上限',
    '每个子智能体返回结果的最多字符数，超出部分保存到文件，不会丢失。0 = 不设上限。',
  ),
  'delegation.model': ('子智能体模型', '子智能体使用的模型。留空则沿用主智能体的模型。'),
  'delegation.oneshot_max_children': (
    '单次运行子智能体上限',
    '单次运行（hermes chat -q 或 --oneshot）中最多创建的子智能体数。0 = 不限制。',
  ),
  'delegation.orchestrator_enabled': ('允许编排者角色', '允许子智能体以编排者角色继续委派任务。'),
  'delegation.provider': ('子智能体提供方', '子智能体使用的提供方，会自动解析其凭据。留空则沿用主智能体。'),
  'delegation.reasoning_effort': ('子智能体推理强度', '子智能体的推理强度。留空则沿用主智能体。'),
  'delegation.subagent_auto_approve': (
    '子智能体自动审批',
    '子智能体遇到危险命令审批时，开启则自动批准一次，关闭则自动拒绝。只建议用于可信的批量任务。',
  ),
  'delegation.surface_child_process_notifications': (
    '转发子进程通知',
    '把子智能体后台进程的完成和匹配通知转发给主智能体。关闭则只交付子智能体的结果。',
  ),
  'desktop.auto_continue.enabled': (
    '崩溃后自动继续',
    '一轮对话因崩溃中断时，恢复后自动重新提交被中断的请求（仅限较新的中断）。',
  ),
  'desktop.auto_continue.freshness_minutes': ('自动继续时效', '中断发生在多少分钟内才自动继续。'),
  'desktop.auto_continue.max_attempts': (
    '自动继续最多次数',
    '同一轮被中断的对话最多自动重跑的次数，避免崩溃循环。',
  ),
  'desktop.disable_gpu': (
    '禁用 GPU',
    'auto = 仅在远程显示（SSH、VNC、RDP）时禁用 GPU；true = 始终使用软件渲染；false = 始终使用 GPU。',
  ),
  'desktop.electron_flags': (
    'Electron 启动参数',
    '每次启动桌面应用时附加的 Electron 参数，例如 --ozone-platform=x11。',
  ),
  'desktop.font_family': (
    '界面字体',
    '桌面应用聊天和界面文字使用的字体（CSS font-family）。留空则使用主题字体。',
  ),
  'desktop.macos_signing_identity': (
    'macOS 签名身份',
    '仅 macOS：重新签名本地构建的应用时使用的代码签名身份，使系统权限授权在更新后保留。留空则使用默认的临时签名。',
  ),
  'desktop.manage_launcher_entry': (
    '管理启动器入口',
    '仅 Linux：每次启动时更新生成的应用启动器入口。关闭则保留已有的自定义入口。',
  ),
  'desktop.ozone_platform_hint': (
    'Linux 显示后端',
    '仅 Linux：auto = Chromium 默认；x11 = 通过 XWayland 运行；wayland = 强制使用原生 Wayland。',
  ),
  'desktop.password_store': (
    'Linux 密钥存储',
    '仅 Linux：保存令牌的系统钥匙串。auto = 自动检测；也可指定 gnome-libsecret、kwallet 等；basic = 不加密。',
  ),
  'desktop.renderer_accessibility': (
    '界面无障碍支持',
    '向系统开放界面的无障碍树，便于听写和输入法工具输入文字。关闭可提升性能。',
  ),
  'desktop.renderer_max_old_space_mb': (
    '界面内存上限',
    '界面渲染进程的 V8 内存上限（MB）；超过时只重新加载界面，避免整机卡死。0 = 使用 Chromium 默认值。',
  ),
  'desktop.repo_scan_enabled': ('扫描 Git 仓库', '为项目侧栏扫描 Git 仓库。需要配置扫描目录才会扫描。'),
  'desktop.repo_scan_exclude_paths': ('扫描排除路径', '扫描 Git 仓库时跳过的路径。'),
  'desktop.repo_scan_roots': ('仓库扫描目录', '扫描 Git 仓库的根目录。留空则不扫描文件系统。'),
  'desktop.ssh_path': (
    'SSH 程序路径',
    '仅 Windows：SSH 连接和终端使用的 ssh 程序。留空则依次使用系统 OpenSSH、Git for Windows 的 ssh 或 PATH 中的版本。修改后需重启应用。',
  ),
  'discord.allow_any_attachment': (
    '允许任意附件（已废弃）',
    '已废弃的旧选项，不再起作用：附件总会被缓存，是否处理由消息授权决定。保留只为兼容旧配置。',
  ),
  'discord.allowed_channels': ('允许的频道', '填写后只在这些频道 ID 中回复（允许列表）。留空则不限制。'),
  'discord.approval_mentions': ('审批时@提及用户', '在审批提示中@提及允许的用户，方便在共享频道里及时注意到。'),
  'discord.auto_thread': ('自动创建话题', '在频道中被@提及时自动创建话题来回复。'),
  'discord.bots_require_inline_mention': (
    '机器人须在正文@提及',
    '其他机器人发的消息必须在正文里 @本机器人 才会触发回复，仅回复引用不算。只有可信的旧中继才应关闭；对真人用户无影响。',
  ),
  'discord.dm_role_auth_guild': (
    '私信按身份组授权的服务器',
    '允许的身份组通常只授权服务器内消息；填写一个服务器 ID 后，该服务器中持有允许身份组的成员也可私信使用。留空或 0 为关闭。',
  ),
  'discord.free_response_auto_thread': (
    '免@频道自动建话题',
    '免@提及频道默认直接在频道内回复；开启后每条顶层消息也会各自开一个话题（仍无需@提及）。',
  ),
  'discord.free_response_channels': ('免@提及频道', '这些频道 ID（逗号分隔）中的消息无需@提及也会回复。'),
  'discord.history_backfill': ('补充近期频道记录', '被触发时附上近期的频道消息，找回因需要@提及而被略过的内容。'),
  'discord.history_backfill_limit': ('补充记录条数上限', '补充近期频道记录时最多扫描的消息条数。'),
  'discord.max_attachment_bytes': ('附件大小上限', '单个缓存附件的最大字节数，写入时会占用内存。0 = 不限制。'),
  'discord.missed_message_backfill.channels': (
    '离线补发频道',
    '要补发离线期间消息的频道 ID（逗号分隔）。留空则使用免@提及频道。',
  ),
  'discord.missed_message_backfill.enabled': (
    '离线消息补发',
    '重新连接或启动后，补发离线期间错过的消息。',
  ),
  'discord.missed_message_backfill.limit': ('离线补发扫描上限', '每次重连时总共最多扫描的消息条数。'),
  'discord.missed_message_backfill.max_attempts': (
    '单条消息补发次数上限',
    '同一条消息累计最多重新派发的次数，无论结果如何。',
  ),
  'discord.missed_message_backfill.max_dispatches': (
    '每次补发条数上限',
    '每次重连最多派发的找回消息条数。',
  ),
  'discord.missed_message_backfill.window_seconds': (
    '离线补发时间范围',
    '只检查这段时间内的消息，单位秒。',
  ),
  'discord.reactions': ('处理状态表情回应', '处理消息时给消息添加 👀/✅/❌ 表情回应。'),
  'discord.require_mention': ('需要@提及', '在服务器频道中需要@提及机器人才会回复。'),
  'discord.server_actions': (
    '允许的服务器操作',
    'discord / discord_admin 工具可执行的操作，如 list_channels、member_info、add_role 等（逗号分隔或列表）。留空则全部允许，但受机器人权限限制。',
  ),
  'discord.thread_require_mention': ('话题内需要@提及', '在话题中也需要@提及才回复，适合多个机器人共用话题。'),
  'discord.voice_channel_inactivity_timeout_seconds': (
    '语音频道闲置超时',
    '在语音频道闲置多少秒后自动离开。0 = 一直停留，直到执行 /voice leave。',
  ),
  'discord.voice_fx.ack_enabled': ('语音应答短句', '在第一次调用工具前先说一句简短的话。'),
  'discord.voice_fx.ack_phrases': ('应答短句列表', '应答时随机选用的短句。设为空列表则不说短句。'),
  'discord.voice_fx.ambient_enabled': ('思考背景音', '工具运行期间播放“思考中”的循环背景音。'),
  'discord.voice_fx.ambient_gain': ('背景音音量', '闲置背景音的音量，范围 0.0–1.0。'),
  'discord.voice_fx.ambient_path': ('背景音文件', '自定义循环播放的音频文件。留空则使用合成音。'),
  'discord.voice_fx.duck_gain': ('说话时背景音音量', '播放语音时背景音被压低后的音量。'),
  'discord.voice_fx.enabled': (
    '语音混音器',
    '语音频道软件混音器的总开关：思考背景音、应答短句和语音合成可以叠加播放（说话时压低背景音），而不是停一个再播一个。',
  ),
  'discord.voice_fx.speech_gain': ('语音音量', '语音合成和应答短句的音量，范围 0.0–1.0。'),
  'discord.voice_playback_timeout_seconds': (
    '语音播放超时',
    '强制停止语音频道播放前的最短秒数；会根据音频时长自动延长，避免长语音被截断。',
  ),
  'discord.websocket_event_max_silence_seconds': (
    '无事件最长静默',
    '连接仍回应心跳、但这么多秒内没有收到任何事件时，视为失联。0 = 关闭这一项检查。',
  ),
  'discord.websocket_heartbeat_ack_max_age_seconds': (
    '心跳确认最长间隔',
    '健康检查时，距上次心跳确认超过此秒数即记为一次失败。设为 0 会关闭连接健康检查。',
  ),
  'discord.websocket_liveness_failure_threshold': (
    '连续失败判定次数',
    '连接健康检查连续失败多少次后强制重连。设为 0 会关闭连接健康检查。',
  ),
  'discord.websocket_liveness_interval_seconds': (
    '健康检查间隔',
    '检查 Discord 连接是否仍在接收事件的间隔秒数。设为 0 会关闭连接健康检查。',
  ),
  'discord.websocket_max_latency_seconds': (
    '心跳延迟上限',
    '心跳延迟超过此秒数即记为一次失败。设为 0 会关闭连接健康检查。',
  ),
  'display.background_process_notifications': (
    '后台进程通知',
    '仅消息平台：后台终端进程结束时的通知方式。concise 一行摘要（失败时附输出结尾）；all 包含运行中更新和最终输出；result 只发最终输出；error 仅在退出码非 0 时发送；off 不通知。',
  ),
  'display.battery': ('状态栏电量', '在状态栏最前面显示电池电量；没有电池时无效果。'),
  'display.bell_on_complete': ('回复完成时响铃', '智能体完成回复时让终端响铃，适合长任务。通过 SSH 也可用。'),
  'display.bell_on_prompt': (
    '等待输入时响铃',
    '出现需要你处理的提示（澄清问题、危险命令审批、sudo 密码、密钥输入）时让终端响铃。',
  ),
  'display.busy_input_mode': (
    '运行中输入方式',
    '智能体运行时按 Enter 的效果：interrupt 打断当前运行并改向；queue 排到下一轮；steer 在下一次工具调用后插入当前运行，不打断（附带图片时改为排队）。',
  ),
  'display.busy_steer_ack_enabled': (
    '插话确认提示',
    'steer 模式下是否显示“已插入当前运行”的提示；关闭只隐藏提示，插话照常进行。',
  ),
  'display.cli_layout': (
    '命令行布局',
    '经典命令行的外观：modern 为符号行、状态显示在输入框下方；classic 为带边框的面板。',
  ),
  'display.cli_multiline_shortcuts': (
    '多行输入快捷键',
    '经典命令行中除 Alt+Enter 外的多行输入方式：Ctrl+J 换行、行尾反斜杠加 Enter 续行、区分 Shift+Enter。关闭后，在回车被识别为换行符的终端上恢复 Ctrl+J 提交。',
  ),
  'display.cli_rebuild_scrollback_on_redraw': (
    '重绘时清除回滚记录',
    '经典命令行完全重绘或调整窗口大小时，同时清除终端回滚记录。适用于终端或 tmux 把旧提示符残留在回滚记录里的情况。',
  ),
  'display.cli_refresh_interval': (
    '命令行刷新间隔',
    '经典命令行空闲时重绘界面的间隔秒数，让状态栏的时间等信息保持更新。0 = 关闭，若与终端自动滚动冲突可关闭。',
  ),
  'display.compact': ('紧凑启动横幅', '用单行启动横幅代替完整的 ASCII 图案和工具、技能摘要。'),
  'display.copy_shortcut': (
    '复制快捷键',
    '用于复制的快捷键：auto 使用平台默认，也可选 ctrl_c、ctrl_shift_c 或 disabled（关闭）。',
  ),
  'display.credits_notices': (
    'Nous 额度提醒',
    '在状态栏显示 Nous 额度相关提示（用量档位、赠送额度用完、余额耗尽或恢复）。关闭后余额数据和 /usage 仍可用。',
  ),
  'display.ephemeral_system_ttl': (
    '系统通知自动删除',
    '在支持删除消息的平台（Telegram）上，系统通知（如“已开始新会话”）在多少秒后自动删除；不影响智能体回复。0 = 关闭。',
  ),
  'display.file_mutation_verifier': (
    '文件写入失败提醒',
    '本轮有 write_file 或 patch 写入失败、且之后没有成功写入同一路径时，在最终回复末尾追加一行提示。',
  ),
  'display.final_response_markdown': (
    '最终回复 Markdown 显示',
    '命令行中最终回复的 Markdown 处理方式：render 渲染格式，strip 去掉标记符号，raw 原样显示。',
  ),
  'display.focus_saved_tool_progress': (
    '专注视图恢复的进度级别',
    '关闭专注视图（/focus off）时恢复的工具进度显示级别。',
  ),
  'display.focus_view': (
    '专注视图',
    '只影响显示：隐藏工具进度、统计每轮隐藏的行数，并在状态栏显示 focus 标记。不会改变模型看到的内容，可用 /focus 切换。',
  ),
  'display.friendly_tool_labels': (
    '易读的工具标签',
    '内置工具的进度用自然语言描述（如“正在读取 <文件>”）；自定义、插件和 MCP 工具仍显示原始预览。',
  ),
  'display.inline_diffs': (
    '内联差异预览',
    '对 write_file、patch、skill_manage 显示内联的修改差异预览。',
  ),
  'display.interface': (
    '默认界面',
    '运行 hermes 或 hermes chat 时启动的界面：cli 为经典命令行，tui 为 Ink 终端界面。命令行参数 --cli、--tui 优先。',
  ),
  'display.interim_assistant_messages': (
    '中途进度消息',
    '消息平台：把智能体执行过程中的阶段性说明作为单独消息发出。桌面应用：保留工具调用之间的说明，而不是完成后只剩最终回复。',
  ),
  'display.language': (
    '界面语言',
    '固定界面文字（如审批提示、部分网关命令回复）的语言，不影响智能体回复、日志和工具输出。可选 en、zh、ja、de、es、fr、tr、uk。',
  ),
  'display.memory_notifications': (
    '记忆更新通知',
    '后台自我改进时在聊天中的提示：off 不提示（仍会执行），on 显示简短的“记忆已更新”，verbose 显示内容预览。',
  ),
  'display.persist_prompts': ('保留提示处理记录', '审批、澄清等弹出提示处理完后，在滚动记录中留下一行摘要。'),
  'display.persistent_output': (
    '保留命令行输出',
    '在 Ctrl+L、/redraw 或调整窗口大小清屏后，保留经典命令行最近的输出。终端显示异常时可关闭。',
  ),
  'display.persistent_output_max_lines': ('保留输出行数上限', '清屏后最多保留的最近输出行数。'),
  'display.personality': (
    '当前人格',
    '当前选用的人格名称（内置或自定义），可用 /personality 切换。留空表示不使用人格。',
  ),
  'display.pet.enabled': (
    '动画桌宠',
    '显示 Petdex 动画吉祥物，纯装饰，可在命令行、终端界面和桌面应用中显示。用 hermes pets 管理。',
  ),
  'display.pet.render_mode': (
    '桌宠渲染方式',
    'auto 自动检测 kitty、iTerm2、sixel，否则使用 Unicode 半块字符；也可指定 kitty、iterm、sixel、unicode 或 off。',
  ),
  'display.pet.scale': ('桌宠缩放比例', '相对原始 192×208 帧的大小倍数，桌面应用和终端共用。'),
  'display.pet.slug': ('当前桌宠', '已安装桌宠的标识名。留空则使用第一个已安装的桌宠。'),
  'display.pet.unicode_cols': ('桌宠终端列宽', '强制指定桌宠在终端中占用的列数。0 = 根据缩放比例计算。'),
  'display.platforms.discord.streaming': (
    'Discord 流式输出',
    '在 Discord 上流式输出回复。Discord 只能通过编辑消息实现，会有闪烁；仍受 streaming.enabled 总开关控制。',
  ),
  'display.platforms.slack.streaming': (
    'Slack 流式输出',
    '在 Slack 上流式输出回复。Slack 只能通过编辑消息实现，会有闪烁；仍受 streaming.enabled 总开关控制。',
  ),
  'display.platforms.telegram.streaming': (
    'Telegram 流式输出',
    '在 Telegram 上流式输出回复，使用原生草稿，效果流畅；仍受 streaming.enabled 总开关控制。',
  ),
  'display.platforms.wecom.streaming': (
    '企业微信流式输出',
    '在企业微信上使用原生流式消息输出回复；仍受 streaming.enabled 总开关控制。',
  ),
  'display.reasoning_full': (
    '完整推理回顾',
    '回复后的推理回顾默认折叠为 10 行；开启后完整显示。实时流式显示始终是完整的。',
  ),
  'display.reasoning_style': (
    '推理摘要样式',
    '推理摘要的呈现方式：code 为代码块，blockquote 为引用块，subtext 为 Discord 的灰色小字（Discord 默认）。',
  ),
  'display.resume_display': (
    '恢复会话显示',
    '恢复会话时如何显示之前的对话：full 显示近期对话回顾，minimal 不显示回顾。',
  ),
  'display.resume_exchanges': ('回顾对话轮数', '恢复会话时回顾中最多显示的用户与助手对话轮数。'),
  'display.resume_last_session': ('启动时打开上次会话', '桌面应用冷启动时重新打开上次的聊天或页面。'),
  'display.resume_max_assistant_chars': (
    '回顾助手消息字数上限',
    '回顾中除最后一条外的助手消息超过此字符数会被截断。',
  ),
  'display.resume_max_assistant_lines': (
    '回顾助手消息行数上限',
    '回顾中除最后一条外的助手消息超过此行数会被截断。',
  ),
  'display.resume_max_user_chars': ('回顾用户消息字数上限', '回顾中的用户消息超过此字符数会被截断。'),
  'display.resume_skip_tool_only': (
    '回顾跳过纯工具调用',
    '回顾中跳过只有工具调用的助手消息，避免被“[2 tool calls: …]”之类的行占满；关闭则一并显示。',
  ),
  'display.runtime_footer.enabled': (
    '运行信息页脚',
    '在消息平台的最终回复末尾附上运行信息，例如模型、上下文占用和工作目录。',
  ),
  'display.runtime_footer.fields': (
    '页脚字段',
    '页脚显示的字段及顺序，如 model、context_pct、cwd，也可加入 latency、served_model。删去某项即隐藏。',
  ),
  'display.show_commentary': (
    '显示解说内容',
    'Codex Responses 的解说内容：开启时作为过程中的阶段性消息发出；关闭则归入推理，只在显示推理时可见。',
  ),
  'display.show_cost': ('显示费用', '在状态栏显示以美元计的费用。'),
  'display.show_reasoning': (
    '显示推理过程',
    '在回复之前实时显示模型的推理内容；关闭后思考型模型在推理期间只显示加载动画。可用 /reasoning show 或 /reasoning hide 切换。',
  ),
  'display.skin': ('界面主题', '命令行的视觉主题，包括启动横幅颜色、加载动画和回复框样式。可用 /skin 切换。'),
  'display.spinner_token_flow': (
    '加载动画显示 token 数',
    '仅命令行：在加载动画上实时显示本轮累计输出的 token 数。',
  ),
  'display.status_bar.fields': (
    '状态栏字段',
    '命令行和终端界面状态栏显示的字段：填写后只显示列出的项（按内置顺序排列），留空使用默认集合。可选如 model、context_pct、latency、git_branch、battery 等。',
  ),
  'display.streaming': ('终端流式输出', '回复逐 token 显示在终端，而不是等完整回复后一次显示。'),
  'display.suppress_warning_notifications': (
    '隐藏警告通知',
    '隐藏自动发出的警告和诊断通知（如上下文压缩、重试、备用切换、停滞提醒）。请求的结果、审批、澄清和命令结果不会被隐藏，日志也不受影响。',
  ),
  'display.timestamp_format': (
    '时间戳格式',
    '时间戳的 strftime 格式，例如 %H:%M 或 %b-%d %H:%M。',
  ),
  'display.timestamps': ('显示时间戳', '在命令行标签、终端界面消息行和桌面应用对话中显示消息时间。'),
  'display.tool_preview_length': ('工具预览长度', '工具调用预览的最大字符数。0 = 不限制。'),
  'display.tool_progress_command': ('网关 /verbose 命令', '在消息平台中启用 /verbose 命令。'),
  'display.tool_progress_grouping': (
    '工具进度分组',
    '在支持编辑消息的平台上：accumulate 把进度合并到一条消息中持续编辑；separate 每个工具单独一条（更嘈杂）。需开启工具进度显示。',
  ),
  'display.tui_agents_nudge': (
    '子智能体提示',
    '首次委派时在终端界面显示一次提示：子智能体正在工作，可用 /agents 实时查看。',
  ),
  'display.tui_auto_resume_recent': (
    '终端界面自动恢复会话',
    'hermes --tui 启动时自动恢复最近的会话，类似 hermes -c。',
  ),
  'display.tui_native': ('终端界面原生模式', '终端界面使用终端自身的主缓冲区和回滚记录，而不是自定义的全屏视图。'),
  'display.tui_status_indicator': (
    '忙碌指示样式',
    '终端界面忙碌时的指示样式：kaomoji、emoji、unicode（盲文点阵）或 ascii。可用 /indicator 切换。',
  ),
  'display.turn_completion_explainer': (
    '无回复原因说明',
    '一轮结束却没有可用回复时（重试后仍为空、输出被截断、达到轮数或预算上限等），附上一行原因说明，而不是只显示“(empty)”。',
  ),
  'display.turn_summary': (
    '每轮摘要',
    '仅命令行：每轮结束后显示一行摘要，如耗时、编辑的文件和行数、读取的文件数、执行的命令数。',
  ),
  'display.user_message_preview.first_lines': (
    '用户消息预览开头行数',
    '命令行把你提交的消息回显到滚动记录时，保留开头的行数。',
  ),
  'display.user_message_preview.last_lines': (
    '用户消息预览结尾行数',
    '命令行把你提交的消息回显到滚动记录时，保留结尾的行数。',
  ),
  'display.vim_mode': (
    'Vim 按键模式',
    '在命令行输入框中使用 Vi/Vim 按键绑定；关闭时使用标准 emacs 风格按键。',
  ),
  'doctor.live_probe_timeout': (
    '实时检测超时',
    'hermes doctor --live 每项真实调用检测的超时秒数。',
  ),
  'fallback.min_switch_reset_seconds': (
    '限流切换最短等待',
    '主模型被限流、且声明的恢复时间短于此秒数时，留在主模型上等待重试，而不切换到备用模型。0 = 关闭。',
  ),
  'fallback_providers': ('备用模型链', '主模型调用失败时按顺序尝试的备用提供方和模型列表。'),
  'file_read_max_chars': (
    '单次读取文件字符上限',
    'read_file 单次最多读取的字符数，更大的读取会被拒绝并提示分段读取。10 万字符约合 2.5–3.5 万 token。',
  ),
  'gateway.allow_all_users': ('允许所有用户', '不设允许列表也允许所有用户使用。涉及安全，需主动开启。'),
  'gateway.api_server.history_tool_output_max_chars': (
    '历史工具输出字符上限',
    'OpenAI 兼容 API 服务保存 /v1/responses 对话历史时，每条工具输出和工具参数的最大字符数。0 = 原样保存。',
  ),
  'gateway.api_server.max_concurrent_runs': (
    '最大并发运行数',
    'OpenAI 兼容 API 服务同时运行的智能体上限，超出的请求返回 HTTP 429。0 = 不限制。',
  ),
  'gateway.auto_multiplex_migration': (
    '自动合并到共享网关',
    'hermes update 后是否自动把多 profile 安装合并到默认 profile 的共享网关。关闭后需手动运行 hermes gateway migrate --multiplex。',
  ),
  'gateway.bot_loop_guard.cooldown_seconds': (
    '机器人循环冷却时间',
    '触发机器人循环保护后暂停接收机器人消息的秒数。',
  ),
  'gateway.bot_loop_guard.enabled': (
    '机器人循环保护',
    '防止机器人之间互相回复形成循环：同一对话中接收的机器人消息过多时进入冷却。',
  ),
  'gateway.bot_loop_guard.max_events': (
    '机器人消息数上限',
    '时间窗口内同一对话可接收的机器人消息条数，超过即进入冷却。',
  ),
  'gateway.bot_loop_guard.window_seconds': ('机器人循环统计窗口', '统计机器人消息条数的时间窗口，单位秒。'),
  'gateway.delivery_ledger': (
    '回复投递记录',
    '把最终回复的投递状态记录到数据库；网关在发送途中崩溃后，下次启动会补发（可能重复）。关闭则崩溃或重启时会丢失正在发送的回复。',
  ),
  'gateway.loop_watchdog': (
    '事件循环看门狗',
    '后台线程检测网关事件循环是否卡住；连续多次无响应后输出线程堆栈并退出，由系统服务重新拉起。',
  ),
  'gateway.loop_watchdog_max_strikes': ('看门狗最大失败次数', '连续多少次检测无响应后强制退出。'),
  'gateway.loop_watchdog_probe_interval_s': ('看门狗检测间隔', '两次事件循环检测之间的秒数。'),
  'gateway.loop_watchdog_probe_timeout_s': ('看门狗检测超时', '一次检测在多少秒内未被处理即记为失败。'),
  'gateway.max_inbound_media_bytes': (
    '接收媒体大小上限',
    '网关接收图片、音频、视频时会先完整读入内存再缓存，此为允许的最大字节数，防止超大文件耗尽内存。0 = 不限制。',
  ),
  'gateway.media_delivery_allow_dirs': (
    '允许发送文件的目录',
    '额外允许直接发送其中文件的目录（绝对路径列表）；Hermes 缓存目录始终可信。',
  ),
  'gateway.message_timestamps.enabled': (
    '消息附加时间戳',
    '在模型看到的上下文中给用户消息加上发送时间，帮助感知时间；保存的对话记录不受影响。',
  ),
  'gateway.multiplex_profiles': (
    '单网关服务所有 profile',
    '默认 profile 的网关同时连接本机各 profile 的机器人。这是目前唯一支持的方式，设为 false 会被忽略。',
  ),
  'gateway.platform_connect_timeout': (
    '平台连接超时',
    '启动或重连时等待单个消息平台连接完成的秒数；Discord 斜杠命令很多时可调大。0 或负数 = 无限等待。',
  ),
  'gateway.profile_routes': (
    'profile 路由规则',
    '把默认 profile 的机器人收到的指定聊天转给其他 profile 处理，可按平台、聊天、用户、服务器等匹配，最具体的规则优先。',
  ),
  'gateway.respawn_storm.max_starts': (
    '频繁重启次数上限',
    '时间窗口内允许的启动次数，超过后每次启动前按指数退避等待。0 或负数 = 关闭。',
  ),
  'gateway.respawn_storm.window_seconds': ('频繁重启统计窗口', '统计启动次数的滑动时间窗口，单位秒。'),
  'gateway.restart_loop_guard.max_gap_seconds': (
    '重启循环最大间隔',
    '两次启动相隔不超过此秒数即视为连续重启。',
  ),
  'gateway.restart_loop_guard.max_restarts': (
    '重启循环次数上限',
    '网关被重新拉起后会自动恢复被中断的会话；连续重启达到此次数后，本次启动跳过自动恢复（仍正常处理新消息）。0 = 关闭。',
  ),
  'gateway.restart_loop_guard.window_seconds': (
    '重启循环最小窗口',
    '判断连续重启所用间隔的下限，单位秒。',
  ),
  'gateway.scale_to_zero.idle_timeout_minutes': (
    '缩容闲置超时',
    '启用缩容到零后，闲置多少分钟让连接休眠，以便平台挂起机器。0 或负数 = 使用默认值。',
  ),
  'gateway.service_install_choice': (
    '网关服务安装选择',
    '记录是否安装开机自启的网关服务：install 安装，decline 不安装，留空则在设置时询问。',
  ),
  'gateway.signal_interrupt_grace_timeout': (
    '中断宽限时间',
    '网关收到 SIGTERM 后，等待运行中的智能体收尾的秒数，之后开始关闭。',
  ),
  'gateway.startup_watchdog': ('启动看门狗', '网关启动后，若事件循环在限定时间内仍未就绪，则强制退出。'),
  'gateway.startup_watchdog_timeout_seconds': ('启动看门狗超时', '启动看门狗等待事件循环就绪的秒数。'),
  'gateway.strict': (
    '严格文件发送',
    '开启后只能发送 Hermes 缓存、允许目录中或最近生成的文件，防止提示词注入窃取主机密钥，适合公开使用的网关。关闭时除系统和凭证目录外的文件都可发送。',
  ),
  'gateway.trust_env': (
    '使用环境代理设置',
    '允许平台适配器读取环境中的 HTTP_PROXY、HTTPS_PROXY、NO_PROXY 等代理设置及系统代理。网关继承了不该使用的代理时可关闭；各平台专用代理变量仍然有效。',
  ),
  'gateway.trust_recent_files': (
    '信任最近生成的文件',
    '严格文件发送模式下，也允许发送修改时间在信任时长内的文件，系统路径仍禁止。关闭则只按允许目录判断。',
  ),
  'gateway.trust_recent_files_seconds': (
    '最近文件信任时长',
    '多少秒内修改过的文件视为最近生成。仅在严格文件发送开启时生效。',
  ),
  'gateway.unmanaged_idle_exit_seconds': (
    '自启网关闲置退出',
    '由客户端自动启动、未由系统服务管理的网关，闲置多少秒后退出。0 = 关闭。',
  ),
  'gateway.write_sessions_json': (
    '写入 sessions.json',
    '继续写入旧版 sessions.json 路由索引副本（主数据在 state.db），供外部工具和降级使用。',
  ),
  'goals.max_turns': ('目标最大续跑轮数', '/goal 目标循环自动暂停前最多继续的轮数，防止判断失误和无限消耗。'),
  'hooks_auto_accept': (
    '自动接受 Hook',
    '无需终端确认，自动接受 shell 脚本 Hook 的注册。网关、定时任务等非交互运行需要开启它才能使用新添加的 Hook。',
  ),
  'hosted_rooms.discussion.max_messages': (
    '讨论消息总数上限',
    '托管房间每次讨论中所有成员可见回复的总条数上限，不是每人。只接受正整数，修改后需重启所属服务。',
  ),
  'hosted_rooms.discussion.max_rounds': (
    '讨论轮数上限',
    '托管房间每次讨论最多进行的轮数。只接受正整数，修改后需重启所属服务。',
  ),
  'human_delay.max_ms': ('最大延迟', '模拟人工延迟的最大毫秒数，仅在 custom 模式下生效。'),
  'human_delay.min_ms': ('最小延迟', '模拟人工延迟的最小毫秒数，仅在 custom 模式下生效。'),
  'human_delay.mode': ('模拟打字延迟', '在消息平台分段发送回复时加入随机延迟，模拟人工节奏。off 为关闭。'),
  'kanban.auto_decompose': (
    '自动拆解分拣任务',
    '每次调度时自动拆解 Triage 列中的任务；关闭则需手动运行 hermes kanban decompose 或在控制台点击拆解。',
  ),
  'kanban.auto_decompose_per_tick': (
    '每次拆解任务数',
    '每次调度最多拆解的 Triage 任务数，超出的顺延到下一次。',
  ),
  'kanban.auto_subscribe_on_create': (
    '创建任务时自动订阅',
    '在有固定投递渠道的会话中创建看板任务时，自动订阅该任务的完成和阻塞通知。',
  ),
  'kanban.default_assignee': (
    '默认负责人',
    '编排时无法匹配到已安装 profile 时使用的负责人。留空则使用默认 profile。',
  ),
  'kanban.dispatch_in_gateway': (
    '在网关中调度',
    '在网关进程内运行看板调度器。单独运行调度器或不希望网关启动工作进程时可关闭。',
  ),
  'kanban.dispatch_interval_seconds': (
    '调度间隔',
    '调度器两次检查之间的秒数；越小接单越快，越大数据库压力越小。',
  ),
  'kanban.dispatch_profiles': (
    '可认领的 profile',
    '多个 Hermes 主目录共享看板时，本机调度器可认领的 profile 名单（列表或逗号分隔）。留空则可认领任意 profile；填写后只认领列出的。',
  ),
  'kanban.dispatch_stale_timeout_seconds': (
    '无心跳回收时间',
    '运行中的任务超过此秒数没有心跳，下次调度时收回为就绪。0 = 关闭。',
  ),
  'kanban.done_sub_retention_days': (
    '已完成订阅保留天数',
    '已完成且这么多天没有活动的任务，其通知订阅会被清理。0 = 关闭。',
  ),
  'kanban.failure_limit': (
    '连续失败上限',
    '同一任务和 profile 连续失败（启动失败、超时、崩溃）达到此次数后自动阻塞。重新分配会重置计数。',
  ),
  'kanban.max_in_progress': (
    '全局并发上限',
    '整台主机同时运行的任务上限，跨所有看板计算。留空则按内存自动推算（约每 512 MiB 一个，限制在 2–8 之间）；无法读取内存时不限制。',
  ),
  'kanban.max_in_progress_per_profile': (
    '每个 profile 并发上限',
    '单个 profile 同时运行的工作进程上限。留空则不限制。',
  ),
  'kanban.notify_in_gateway': (
    '在网关中发送看板通知',
    '由此网关轮询并投递看板订阅通知；不负责通知的 profile 可关闭。',
  ),
  'kanban.orchestrator_profile': (
    '编排 profile',
    'Triage 拆解后负责根任务（编排任务）的 profile。留空则使用默认 profile。',
  ),
  'kanban.reconcile_orphans': (
    '修复孤立任务',
    '每次调度时，把认领记录损坏且工作进程已退出的运行中任务重新排队。关闭则保留原状以便人工排查。',
  ),
  'kanban.review_dispatch': (
    '自动调度评审',
    '自动认领评审列中的任务，并用内置的 sdlc-review 技能启动指定的 profile。评审都在控制台手动完成时可关闭。',
  ),
  'kanban.worker_log_backup_count': ('工作日志备份数', '工作进程日志轮转时保留的备份数量。'),
  'kanban.worker_log_rotate_bytes': ('工作日志轮转大小', '工作进程的输出日志达到此字节数时轮转。'),
  'local_runtime.backend': (
    '计算后端',
    '托管 llama.cpp 运行时使用的后端：auto 自动选择（NVIDIA 用 CUDA、macOS 用 Metal、其他 GPU 用 Vulkan，否则用 CPU），也可指定 cuda、metal、vulkan、hip、cpu。',
  ),
  'local_runtime.detect_ports': (
    '额外检测端口',
    '检测外部 llama-server 时，除 8080 外还要探测的端口。',
  ),
  'local_runtime.enabled': (
    '托管本地运行时',
    '由 Hermes 管理一个 llama.cpp 服务（llama-server）来运行本地模型。关闭时只检测你自己运行的外部服务。',
  ),
  'local_runtime.models_max': ('同时加载模型数', '可以同时加载的模型数量上限。'),
  'local_runtime.port': ('服务端口', '托管服务使用的端口。0 = 启动时自动选择空闲端口。'),
  'logging.backup_count': ('日志备份数', '日志轮转时保留的旧文件数量。'),
  'logging.level': ('日志级别', '写入 agent.log 的最低日志级别。'),
  'logging.max_size_mb': ('日志文件大小上限', '单个日志文件轮转前的最大大小，单位 MB。'),
  'loops.max_ticks': ('最大执行次数', '/loop 循环唤醒这么多次后自动暂停（除非指定了 --times）。0 = 不限制。'),
  'loops.min_interval_seconds': ('最小间隔', '/loop 固定间隔的最小秒数，更短的间隔会被提高到此值。'),
  'loops.self_paced_ceiling_seconds': (
    '自动节奏最长间隔',
    '未指定间隔时，循环从起始间隔开始，回复不再变化时逐渐拉长，最长到此秒数。',
  ),
  'loops.self_paced_floor_seconds': ('自动节奏起始间隔', '未指定间隔时循环的起始（最短）间隔秒数。'),
  'lsp.broken_retry_seconds': (
    '故障服务重试间隔',
    '语言服务器启动失败或超时后，隔多少秒再重试该工作区。0 = 本次进程内不再重试（直到运行 hermes lsp restart）。',
  ),
  'lsp.enabled': (
    'LSP 诊断',
    '在 write_file、patch 写入后的检查中使用语言服务器诊断（如 pyright、gopls）。只在 Git 工作树中运行；关闭则完全停用。',
  ),
  'lsp.exclude_roots': (
    '排除的工作区',
    '不运行语言服务器的工作区根目录（支持 glob 模式），例如超大的单体仓库。必须是列表。',
  ),
  'lsp.idle_timeout': ('闲置关闭时间', '语言服务器闲置多少秒后关闭，需要时再重新启动。0 = 一直保留。'),
  'lsp.install_strategy': (
    '安装方式',
    '缺少语言服务器时：auto 在首次使用时通过 npm、go 或 pip 自动安装；manual 只使用 PATH 中已有的；off 等同于 manual。',
  ),
  'lsp.package_manager': (
    'Node 包管理器',
    '安装基于 npm 的语言服务器所用的包管理器：npm、pnpm 或 yarn。指定的管理器未安装时会跳过安装。',
  ),
  'lsp.trusted_workspaces': (
    '信任的工作区',
    '允许语言服务器加载项目代码（如项目虚拟环境、node_modules、构建文件）的目录。启动目录和会话工作区始终受信任。',
  ),
  'lsp.wait_mode': ('诊断等待方式', 'document 只等待当前文件的诊断；full 同时请求整个工作区的诊断，较慢。'),
  'lsp.wait_timeout': ('诊断等待超时', '等待诊断结果的最长秒数。'),
  'lsp.warmup_timeout': (
    '首次启动等待时间',
    '工作区的语言服务器尚未运行时，首次请求的等待秒数（含启动和初始构建）。0 = 与诊断等待超时相同。',
  ),
  'matrix.allowed_rooms': ('允许的房间', '填写后只在这些房间 ID 中回复（允许列表）；留空则不限制。'),
  'matrix.free_response_rooms': ('免@提及房间', '在这些房间 ID 中无需 @提及也会回复；多个用英文逗号分隔。'),
  'matrix.require_mention': ('房间内需要 @提及', '开启后，在房间里只有被 @提及时才回复。'),
  'mattermost.allowed_channels': ('允许的频道', '填写后只在这些频道 ID 中回复（允许列表）；留空则不限制。'),
  'mattermost.free_response_channels': (
    '免@提及频道',
    '在这些频道 ID 中无需 @提及也会回复；多个用英文逗号分隔。',
  ),
  'mattermost.require_mention': ('频道内需要 @提及', '开启后，在频道里只有被 @提及时才回复。'),
  'max_concurrent_sessions': (
    '最大同时活跃会话数',
    'CLI、终端界面、控制台聊天和消息网关合计可同时活跃的会话上限；留空或 0 表示不限制。达到上限时新会话会收到错误提示，已有会话不受影响。',
  ),
  'max_live_sessions': (
    '内存中会话上限',
    '终端界面、桌面应用和控制台在内存中保留的会话软上限。超过时网关会释放最久未活动且无人查看的会话，重新打开时从磁盘恢复；0 表示关闭。',
  ),
  'mcp.auto_reload_on_config_change': (
    '配置变更时重载 MCP',
    'config.yaml 中的 mcp_servers 变化时自动重新连接 MCP。每次重载都会让提供方的提示词缓存失效；关闭后只提示手动执行 /reload-mcp。',
  ),
  'mcp.discovery_concurrency': (
    'MCP 并发连接数',
    '每轮发现时最多同时连接（并启动进程）的 MCP 服务器数量，避免启动时资源占用突增；0 表示不限制。',
  ),
  'mcp_discovery_timeout': (
    'MCP 首轮发现等待',
    '首次构建智能体时等待后台 MCP 发现的秒数。只影响第一条回复的延迟，未赶上的服务器会在之后的轮次之间补上。',
  ),
  'mcp_single_query_discovery_timeout': (
    '单次查询 MCP 等待',
    '单次查询模式（hermes -q/-z）等待 MCP 发现的秒数。该模式只有一轮，未赶上的服务器整个会话都不可用，因此等待更久。',
  ),
  'memory.memory_char_limit': (
    '记忆字符上限',
    '智能体个人笔记记忆的字符上限（约 2.75 字符 = 1 token）。达到上限时智能体需要合并或替换条目。',
  ),
  'memory.memory_enabled': ('启用智能体记忆', '开启后，智能体会记录环境信息、约定和学到的经验，并注入系统提示词。'),
  'memory.nudge_interval': ('记忆提醒间隔', '每隔多少轮用户对话提醒智能体考虑保存记忆；0 表示关闭。仅在启用记忆时生效。'),
  'memory.prefetch_spill_enabled': (
    '外部召回截断预览',
    '仅作用于外部记忆提供方的预取召回：开启后按 hooks.output_spill 只保留首尾预览；关闭则保留提供方排序后的完整召回。修改后需重启。',
  ),
  'memory.provider': ('外部记忆提供方', '选择一个外部记忆插件；留空则只使用内置记忆。'),
  'memory.user_char_limit': (
    '用户画像字符上限',
    '用户画像记忆（偏好、沟通风格、期望）的字符上限（约 2.75 字符 = 1 token）。',
  ),
  'memory.user_profile_enabled': ('启用用户画像', '开启后，智能体会记录用户的偏好、沟通风格和期望。'),
  'memory.write_approval': (
    '记忆写入需审批',
    '开启后，写入记忆都需要确认：前台对话中直接询问，后台回顾产生的写入会暂存，用 /memory pending、approve、reject 处理。',
  ),
  'moa.active_preset': ('当前启用的预设', '配置中标记为当前使用的混合智能体（MoA）预设；留空表示未启用。'),
  'moa.default_preset': ('默认预设', '未指定预设名时使用的 MoA 预设；该预设不存在时使用第一个预设。'),
  'moa.presets.default.aggregator.model': (
    '汇总模型',
    'default 预设中汇总模型的模型名。汇总模型负责撰写回复和调用工具，整次运行的费用主要计在它的提供方。',
  ),
  'moa.presets.default.aggregator.provider': (
    '汇总模型提供方',
    'default 预设中汇总模型使用的提供方，例如 openrouter。',
  ),
  'moa.presets.default.enabled': (
    '启用参考模型',
    '关闭后 default 预设不再调用参考模型，由汇总模型单独回答，等同于直接选用该模型。',
  ),
  'moa.presets.default.reference_models': (
    '参考模型列表',
    'default 预设中先运行、为汇总模型提供分析的模型列表，每项包含提供方和模型名。',
  ),
  'moa.privacy_filter': (
    '参考输出隐私过滤',
    '对参考模型输出中的个人信息和凭据做脱敏：留空为关闭；display 只处理界面显示和保存的记录；full 还会处理发给汇总模型的内容。',
  ),
  'moa.save_traces': (
    '保存 MoA 记录',
    '开启后，把每轮 MoA 中参考模型和汇总模型的完整输入、输出和用量以 JSONL 保存，便于审计。',
  ),
  'moa.trace_dir': ('记录保存目录', 'MoA 记录的保存目录；留空则使用 Hermes 主目录下的 moa-traces。'),
  'model': ('默认模型', '默认使用的模型，例如 anthropic/claude-sonnet-4.6。'),
  'model_catalog.enabled': (
    '在线模型目录',
    '从远程清单获取 OpenRouter 和 Nous Portal 的精选模型列表；关闭后始终使用随版本附带的列表，也不再后台刷新。',
  ),
  'model_catalog.ttl_minutes': (
    '目录缓存时长',
    '模型目录磁盘缓存的有效期（分钟）。网关按此间隔在后台刷新；网络失败时继续使用旧缓存。',
  ),
  'model_catalog.url': ('目录地址', '模型目录清单的下载 URL。'),
  'model_context_length': ('上下文窗口覆盖', '手动指定上下文窗口大小（token）；0 表示根据模型元数据自动检测。'),
  'models_dev.url': (
    'models.dev 地址',
    'models.dev 模型信息库（上下文窗口、能力、价格等）的地址；留空使用默认地址，可改为镜像地址。',
  ),
  'monitoring.export.otlp.enabled': (
    '启用 OTLP 导出',
    '开启后把网关监控数据通过 OTLP 发送到指定端点。',
  ),
  'monitoring.export.otlp.endpoint': (
    'OTLP 端点',
    '接收监控数据的 OTLP 地址，例如 OTEL Collector 或 DataDog。',
  ),
  'monitoring.gateway_health_export.diagnostic_events_enabled': (
    '导出诊断事件',
    '导出网关健康数据时包含脱敏后的诊断事件。',
  ),
  'monitoring.gateway_health_export.enabled': (
    '网关健康导出',
    '导出网关服务健康状况和脱敏后的运行诊断。不含提示词、消息、工具参数或会话历史；配置端点后才会发送。',
  ),
  'monitoring.gateway_health_export.export_interval_seconds': (
    '指标导出间隔',
    '健康指标的导出间隔（秒）。',
  ),
  'monitoring.gateway_health_export.logs_export_interval_seconds': (
    '日志导出间隔',
    '诊断日志的导出间隔（秒）。',
  ),
  'monitoring.gateway_health_export.metrics_enabled': (
    '导出指标',
    '导出网关健康数据时包含指标。',
  ),
  'monitoring.gateway_health_export.resource_attributes.deployment.environment.name':
      ('部署环境名', '附在导出数据上的部署环境名称（deployment.environment.name），默认 production。'),
  'monitoring.gateway_health_export.resource_attributes.service.name': (
    '服务名',
    '附在导出数据上的服务名称（service.name），默认 hermes-gateway。',
  ),
  'monitoring.gateway_health_export.warning_error_events_enabled': (
    '导出警告和错误事件',
    '导出网关健康数据时包含警告和错误事件。',
  ),
  'monitoring.install_id': (
    '安装标识',
    '附在导出数据上的固定安装 ID，用于区分不同实例；留空则首次使用时生成新的 UUID，清空可重新生成。不含账号信息。',
  ),
  'network.force_ipv4': ('强制使用 IPv4', '开启后完全跳过 IPv6。适合 IPv6 不可用、连接常卡到超时的网络。'),
  'nous.anthropic_wire': (
    'Anthropic 模型线路',
    'Nous Portal 上 anthropic/* 模型走哪条接口：chat 为 /v1/chat/completions；native 为 Anthropic Messages 接口；auto 先用 chat，已知可靠时按会话切换到 native。',
  ),
  'nous.guest': ('Nous 免费版', '未配置其他提供方时，首次使用会自动建立免费的 Nous 身份；关闭后完全不使用免费版。'),
  'nous.keepalive_interval_seconds': (
    'Nous 登录保活间隔',
    'Nous 登录保活检查的最长间隔（秒），实际间隔由凭据有效期决定；0 表示关闭保活。',
  ),
  'onboarding.profile_build': (
    '首次对话建立画像',
    '第一条消息时的处理：ask 表示主动询问是否建立简短的用户画像；off 只做简单的自我介绍。',
  ),
  'onboarding.run': (
    '桌面首次引导',
    '桌面应用首次运行引导的状态（仅默认 profile）：留空表示新安装，true 表示下次启动时运行，false 表示已完成。',
  ),
  'openrouter.min_coding_score': (
    '最低编程评分',
    '仅在模型为 openrouter/pareto-code 时生效（0.0–1.0）：数值越高，选出的编程模型越强也越贵；0.65 为中档；留空由 OpenRouter 选最强的。',
  ),
  'openrouter.response_cache': (
    '响应缓存',
    '开启后，相同请求直接返回 OpenRouter 缓存的响应且不计费。与 Anthropic 提示词缓存相互独立。',
  ),
  'openrouter.response_cache_ttl': (
    '响应缓存时长',
    '响应缓存的有效期（秒，1–86400），仅在启用响应缓存时生效。',
  ),
  'paste_collapse_char_threshold': (
    '单行粘贴折叠长度',
    '单行粘贴达到这么多字符时折叠为文件引用；0 表示关闭。适用于终端界面和 CLI。',
  ),
  'paste_collapse_threshold': (
    '粘贴折叠行数',
    '粘贴内容的换行数达到该值时折叠为文件引用；0 表示关闭。适用于终端界面和 CLI。',
  ),
  'paste_collapse_threshold_fallback': (
    '兼容终端粘贴折叠行数',
    '用于不支持括号粘贴的终端：换行数达到该值时折叠为文件引用；0 表示关闭。',
  ),
  'plugins.auto_apply': (
    '自动应用插件更新',
    '开启后，定期检查发现更新时自动应用（仅限 Git 类插件），并经过与手动更新相同的安全扫描和确认流程。',
  ),
  'plugins.auto_update_check_hours': (
    '插件更新检查间隔',
    '检查插件更新的间隔（小时），只检查不安装；0 表示关闭。',
  ),
  'plugins.clone_timeout_seconds': (
    '插件下载超时',
    '安装插件时每次 Git 克隆、拉取或检出的超时（秒），最长 3600。仓库较大或网络较慢时可调高。',
  ),
  'plugins.hook_callback_timeout': (
    '插件钩子超时',
    '进程内 Python 插件钩子回调的最长运行时间（秒）。pre_tool_call 超时视为拒绝；0 表示不限制，超过 600 按 600 处理。',
  ),
  'plugins.host.launcher': ('插件宿主启动前缀', '插件宿主进程的启动命令前缀，例如沙箱运行器；留空则作为普通子进程运行。'),
  'plugins.isolation': (
    '插件运行方式',
    '第三方 Python 插件的运行位置：in_process 直接载入 Hermes；host 在每个 profile 独立的插件宿主进程中运行，插件崩溃不影响 Hermes。内置插件始终在进程内运行。',
  ),
  'plugins.load_timeout_seconds': (
    '插件加载超时',
    '单个插件导入和注册的最长时间（秒）。超时的插件会被跳过，其他插件继续加载；0 表示不限制，超过 600 按 600 处理。',
  ),
  'prefill_messages_file': (
    '预置消息文件',
    'JSON 文件路径，其中的消息在每次调用模型时插在系统提示词之后（不保存到会话），常用于少样本示例；相对路径基于 Hermes 主目录。',
  ),
  'privacy.redact_pii': (
    '隐藏个人信息',
    '开启后，发给模型前会去掉电话号码，并把用户和聊天 ID 替换为哈希值。名字和用户名不受影响。',
  ),
  'prompt_caching.cache_ttl': (
    '提示词缓存时长',
    'Anthropic 提示词缓存的有效期：5m 或 1h；auto 表示人工对话用 1h、子智能体和定时任务等用 5m；off 表示关闭缓存。',
  ),
  'proxy.allow_env_fallback': (
    '环境变量作为备用',
    '凭据来源为 bitwarden 时，如果缺少令牌、项目 ID 或获取结果为空：开启则改用主机环境变量，关闭则直接报错。',
  ),
  'proxy.auto_install': (
    '自动安装出口代理',
    '自动把固定版本的 iron-proxy 下载到 Hermes 的 bin 目录；关闭则需自行放到 PATH 中。',
  ),
  'proxy.credential_source': (
    '上游凭据来源',
    'iron-proxy 启动时从哪里读取真实的上游密钥：env 为进程环境变量；bitwarden 在每次重启代理时从 Bitwarden 重新获取（需启用 secrets.bitwarden）。',
  ),
  'proxy.enabled': (
    '出口凭据防火墙',
    '仅适用于 Docker 的出口凭据防火墙。需先运行 hermes egress setup 和 hermes egress start；Modal、SSH、Daytona 暂不支持。',
  ),
  'proxy.enforce_on_docker': (
    '强制 Docker 走代理',
    '已启用代理但未配置或未运行时，拒绝启动 Docker 沙箱；关闭则直接带真实凭据访问外网。',
  ),
  'proxy.extra_allowed_hosts': (
    '额外允许的主机',
    '除内置的主流提供方外，再允许访问的上游主机；支持通配符，如 *.foo.com。',
  ),
  'proxy.tunnel_port': ('代理隧道端口', '代理隧道的监听端口，沙箱通过 HTTPS_PROXY 经此端口访问外网。'),
  'proxy.upstream_deny_cidrs': (
    '禁止访问的网段',
    '防 SSRF 的禁止网段列表；留空则默认禁止本机回环、链路本地（含云元数据地址）和私有网段。',
  ),
  'runtime.malloc_arena_max': (
    '内存分配区上限',
    '网关或 hermes serve 进程的 glibc 内存分配区（arena）上限，仅 Linux 有效；0 表示使用 glibc 默认值。设置了 MALLOC_ARENA_MAX 环境变量时以其为准。',
  ),
  'runtime.nofile_soft_limit': (
    '打开文件数上限',
    '长期运行的 Hermes 服务进程会把可同时打开的文件数软上限提高到该值（不超过系统硬上限，也不会调低）；0 表示不调整。',
  ),
  'secrets.bitwarden.access_token_env': (
    'Bitwarden 令牌变量名',
    '保存 Bitwarden 机器账户令牌的环境变量名。令牌放在 .env 或 shell 中，不写入 config.yaml。',
  ),
  'secrets.bitwarden.auto_install': (
    '自动安装 bws',
    '首次使用时自动把 bws 下载到 Hermes 的 bin 目录；关闭则需 bws 已在 PATH 中。',
  ),
  'secrets.bitwarden.cache_ttl_seconds': (
    'Bitwarden 缓存时长',
    '在多少秒内复用缓存，不重复访问 Bitwarden；0 表示不复用。',
  ),
  'secrets.bitwarden.enabled': (
    '启用 Bitwarden',
    '从 Bitwarden Secrets Manager 同步密钥到环境变量；关闭时不会连接 Bitwarden，也不会自动安装 bws。',
  ),
  'secrets.bitwarden.encrypted_cache.enabled': (
    'Bitwarden 加密备用缓存',
    '网络中断或超时时，使用本地 AES-GCM 加密缓存中上次成功获取的值；认证失败时不会使用。',
  ),
  'secrets.bitwarden.encrypted_cache.max_stale_seconds': (
    '加密缓存最长可用时长',
    '加密备用缓存最多可沿用多久（秒）；0 表示关闭备用缓存。',
  ),
  'secrets.bitwarden.override_existing': (
    'Bitwarden 覆盖已有变量',
    '开启后，Bitwarden 的值会覆盖已有的同名环境变量，轮换密钥后无需清理 .env。',
  ),
  'secrets.bitwarden.project_id': (
    'Bitwarden 项目 ID',
    '要同步的 Bitwarden Secrets Manager 项目 UUID。',
  ),
  'secrets.bitwarden.server_url': (
    'Bitwarden 服务器地址',
    '传给 bws 的服务器地址；留空为美国云，欧盟填 https://vault.bitwarden.eu，自托管填自己的地址。',
  ),
  'secrets.onepassword.account': (
    '1Password 账户',
    'op read --account 使用的账户简称或登录地址；留空使用默认账户。',
  ),
  'secrets.onepassword.binary_path': (
    'op 程序路径',
    'op 命令行工具的绝对路径，原样使用以免依赖 PATH；留空则从 PATH 查找。',
  ),
  'secrets.onepassword.cache_ttl_seconds': (
    '1Password 缓存时长',
    '在进程内和磁盘上缓存所取值的秒数；0 同时关闭两层缓存。',
  ),
  'secrets.onepassword.enabled': (
    '启用 1Password',
    '通过 op 命令行工具读取 1Password 中的密钥；关闭时不会调用 op。',
  ),
  'secrets.onepassword.override_existing': (
    '1Password 覆盖已有变量',
    '开启后，1Password 的值覆盖已有的同名环境变量；关闭则 .env 中的值优先。',
  ),
  'secrets.onepassword.service_account_token_env': (
    '1Password 服务账户令牌变量',
    '保存服务账户令牌的环境变量名，用于无界面认证；未设置时使用交互式或桌面版 op 会话。',
  ),
  'security.acked_advisories': (
    '已确认的安全通告',
    '已阅读并处理的供应链安全通告 ID；已确认的通告不再在启动时提示。可用 hermes doctor --ack <id> 添加。',
  ),
  'security.allow_data_training_tiers_noninteractive': (
    '无人值守时允许训练档位',
    '记录对无人值守运行所用模型的确认：这类模型的服务档位允许厂商用提示词训练。启动检查仍会每次警告，费用保护不受影响。',
  ),
  'security.allow_lazy_installs': (
    '允许按需安装依赖',
    '首次启用需要额外依赖的后端（如 elevenlabs）时自动从 PyPI 安装；关闭则基础包以外的依赖都需手动 pip 安装。',
  ),
  'security.allow_private_urls': (
    '允许访问内网地址',
    '允许网页提取、图片和媒体下载以及云端浏览器访问私有或内部地址（如 localhost、192.168.x.x）。云元数据地址始终被阻止；本地 Chromium 不受此项影响。',
  ),
  'security.approval.transport': (
    '审批界面通道',
    '人工审批请求的展示方式：builtin 使用 CLI、终端界面、网关等内置界面；也可填写已启用的插件通道名。',
  ),
  'security.approval.transport_fallback': (
    '审批通道失败处理',
    '审批通道超时、出错或返回无效时：deny 直接拒绝；builtin 改用内置界面审批。',
  ),
  'security.fake_ip_ranges': (
    '代理虚拟 IP 网段',
    '本地 TUN 代理（如 Mihomo/Clash 的 fake-ip、Surge 增强模式）用于 DNS 应答的网段。落在这些网段的地址不会被当作内网地址拦截；留空按常规判断。',
  ),
  'security.protected_instruction_extra_patterns': (
    '额外受保护文件模式',
    '除默认文件外，还需审批才能写入的指令文件名通配符（按文件名匹配，如 *.mdc）。',
  ),
  'security.protected_instruction_files': (
    '保护指令文件',
    '智能体写入 AGENTS.md、CLAUDE.md、SOUL.md、.cursorrules 等指令文件或项目内 .hermes 配置时，始终需要人工审批，免审批模式下也一样。',
  ),
  'security.redact_secrets': ('隐藏密钥', '在工具输出和本地日志中隐藏密钥、令牌等凭据值。'),
  'security.website_blocklist.domains': ('屏蔽的网站', '禁止访问的网站列表，可填写域名或网址。'),
  'security.website_blocklist.enabled': (
    '启用网站屏蔽',
    '开启后，可访问网址的工具会拒绝访问屏蔽列表中的网站。',
  ),
  'security.website_blocklist.shared_files': (
    '共享屏蔽列表文件',
    '额外读取屏蔽规则的文件路径列表；相对路径基于 Hermes 主目录。',
  ),
  'session.terminal_continue': (
    '按终端继续会话',
    '开启后，在某个终端执行 hermes -c 会继续该终端自己的上一个会话；关闭则继续全局最近的会话。',
  ),
  'sessions.auto_archive': ('自动归档会话', '自动归档（隐藏而非删除）长时间无活动的会话；置顶会话除外。'),
  'sessions.auto_archive_days': ('自动归档天数', '会话无活动多少天后被自动归档，仅在启用自动归档时生效。'),
  'sessions.auto_prune': (
    '自动清理旧会话',
    '定期删除已结束、且超过保留天数无活动的会话历史。打开中、置顶或正在运行的会话不会被删除。',
  ),
  'sessions.cjk_fts': (
    '中日韩搜索索引',
    '已编译对应扩展时，使用中日韩双字索引，让 1–2 个字的中日韩搜索直接命中索引；关闭则不加载。',
  ),
  'sessions.fts_optimize_notice': (
    '搜索索引优化提示',
    '检测到旧版搜索索引时的提示方式：advise 在 hermes update 时提示可回收的空间；require 以必须处理的措辞提示；off 不提示。',
  ),
  'sessions.max_export_messages': (
    '导出消息上限',
    '导出单个会话时允许的最大消息数，防止超大会话耗尽内存；0 表示不限制。',
  ),
  'sessions.max_resume_messages': (
    '恢复消息上限',
    '交互恢复会话时允许的最大活跃消息数，防止超大会话耗尽内存；0 表示不限制。',
  ),
  'sessions.min_interval_hours': ('维护最短间隔', '自动清理和归档等维护任务两次运行之间的最短间隔（小时）。'),
  'sessions.min_vacuum_interval_days': (
    '压缩数据库最短间隔',
    '两次 VACUUM 重写数据库之间的最短间隔（天）；不影响清理频率。',
  ),
  'sessions.orphan_end_grace_s': (
    '无人查看会话结束等待',
    '本地会话无人查看后，在当前轮结束多少秒后将其结束（仍可恢复）；0 表示从不结束。',
  ),
  'sessions.retention_days': ('会话保留天数', '自动清理时保留已结束会话历史的无活动天数。'),
  'sessions.search_slow_ms': ('慢搜索日志阈值', '会话搜索耗时达到该毫秒数时记录一条日志；0 表示记录每次搜索。'),
  'sessions.show_subagents': ('显示子智能体会话', '在会话列表中显示委派子智能体的运行记录，嵌套在父会话下。'),
  'sessions.vacuum_after_prune': (
    '清理后压缩数据库',
    '清理删除会话后执行 VACUUM 回收磁盘空间。只在启动时、且可回收空间超过 25% 时进行，期间会短暂阻塞写入。',
  ),
  'skills.auto_load': ('自动加载的技能', '每个新会话都完整加载的技能名称列表；不存在或已停用的技能会被跳过并提示。'),
  'skills.create_dir': (
    '新技能保存目录',
    '智能体新建技能的保存位置；留空则使用 profile 本地目录。相对路径基于 Hermes 主目录。',
  ),
  'skills.external_dirs': ('外部技能目录', '额外读取技能的目录，可在多个工具间共享；只读，名称冲突时本地技能优先。'),
  'skills.guard_agent_created': (
    '扫描智能体创建的技能',
    '对智能体写入的技能做安全扫描，判定危险时作为工具错误返回。从技能中心安装的技能始终会扫描。',
  ),
  'skills.inline_shell': (
    '执行技能内联命令',
    '预先执行 SKILL.md 中的 !`cmd` 片段，并把输出插入内容（如日期、Git 状态）。社区安装的技能不会自动执行。',
  ),
  'skills.inline_shell_timeout': ('内联命令超时', '每个 !`cmd` 片段的超时（秒）。'),
  'skills.ledger': (
    '技能变更记录',
    '每次修改技能都记录修改前后的哈希，可用 hermes curator ledger 查看和回滚；记录失败不会阻止修改。',
  ),
  'skills.ledger_max_bytes': (
    '变更记录大小上限',
    '技能变更记录文件的大小上限（字节），超过时先去重、仍超出则删除最早的条目；0 表示一直追加不限制。',
  ),
  'skills.project_discovery': (
    '加载项目技能',
    '在 Git 仓库中以最高优先级加载 .hermes/skills/ 和 .agents/skills/ 下的项目技能（仅限受信任的项目目录）；关闭则不扫描。',
  ),
  'skills.template_vars': (
    '技能模板变量',
    '替换 SKILL.md 中的 \${HERMES_SKILL_DIR}、\${HERMES_SESSION_ID} 变量。',
  ),
  'skills.tier1_advisory': (
    'NVIDIA 技能安全检查',
    '安装技能时，若已安装 skillevaluator，额外运行 NVIDIA SkillEvaluator Tier 1 扫描；仅作提示，不阻止安装。',
  ),
  'skills.trusted_project_dirs': (
    '受信任项目目录',
    '允许加载项目技能的项目根目录；由 hermes skills trust / untrust 管理。',
  ),
  'skills.write_approval': (
    '技能修改需审批',
    '开启后，智能体对技能的修改都会先暂存，需用 /skills pending、diff、approve、reject 处理。',
  ),
  'slack.allowed_channels': ('允许的频道', '填写后只在这些频道 ID 中回复（允许列表）；留空则不限制。'),
  'slack.free_response_channels': ('免@提及频道', '在这些频道 ID 中无需 @提及也会回复；多个用英文逗号分隔。'),
  'slack.ignore_other_user_mentions': (
    '忽略@他人的消息',
    '消息开头 @提及了其他用户、且没有同时 @提及本 Bot 时，忽略这条消息。',
  ),
  'slack.require_mention': ('频道内需要 @提及', '开启后，在频道里只有被 @提及时才回复。'),
  'slack.require_mention_channels': ('始终需 @提及的频道', '在这些频道 ID 中始终需要 @提及才回复。'),
  'slack.thread_require_mention': ('话题内需要 @提及', '开启后，话题中的回复也需要 @提及才回复。'),
  'streaming.buffer_threshold': ('刷新字符阈值', '累计这么多字符后立即更新一次消息，让短回复显得更及时。'),
  'streaming.cursor': ('输出中光标', '流式输出过程中附在消息末尾的光标符号。'),
  'streaming.edit_interval': ('编辑最短间隔', '两次更新消息之间的最短间隔（秒）。'),
  'streaming.enabled': ('启用流式输出', '开启后在消息平台上边生成边更新消息；关闭时每条回复作为一条完整消息发送。'),
  'streaming.fresh_final_after_seconds': (
    '最终消息另发阈值',
    '仅 Telegram：大于 0 时，若预览已显示至少这么多秒，最终内容作为新消息发送，使时间戳反映完成时间。',
  ),
  'streaming.transport': (
    '流式输出方式',
    'auto 在支持时用原生草稿（Telegram 私聊），其他平台用编辑消息；draft 用草稿，不支持时改为编辑；edit 只编辑消息；off 关闭。',
  ),
  'stt.cloud_trim_keep_ms': ('保留停顿时长', '裁剪静音时每段停顿保留的毫秒数，用于保持自然节奏。'),
  'stt.cloud_trim_silence': (
    '上传前裁剪静音',
    '上传到云端语音识别前用 ffmpeg 压缩静音，减少上传时间和费用；短于 12 秒的片段不裁剪，失败时上传原始音频。',
  ),
  'stt.cloud_trim_threshold_db': ('静音判定阈值', '低于该分贝值（dB）的声音视为静音。'),
  'stt.deepinfra.model': (
    'DeepInfra 模型',
    'DeepInfra 语音识别模型；留空则使用在线目录中第一个语音识别模型。',
  ),
  'stt.echo_transcripts': ('回显识别文本', '把消息平台语音消息的识别原文作为一条单独的消息发回。'),
  'stt.elevenlabs.diarize': (
    'ElevenLabs 区分说话人',
    '让 ElevenLabs 在识别结果中区分不同的说话人。',
  ),
  'stt.elevenlabs.language_code': (
    'ElevenLabs 语言',
    '强制使用的语言代码，如 eng、spa；留空则自动检测。',
  ),
  'stt.elevenlabs.model_id': ('ElevenLabs 模型', 'ElevenLabs Scribe 语音识别模型。'),
  'stt.elevenlabs.tag_audio_events': (
    'ElevenLabs 标注声音事件',
    '让 ElevenLabs 在识别结果中标注非语音的声音事件。',
  ),
  'stt.enabled': ('启用语音识别', '自动识别消息平台上的语音消息。'),
  'stt.groq.language': ('Groq 语言', '强制使用的语言代码，如 en、es；留空则沿用全局识别语言，再不行则自动检测。'),
  'stt.groq.model': ('Groq 模型', 'Groq Whisper 语音识别模型。'),
  'stt.language': ('识别语言', '所有语音识别提供方的全局语言提示，各提供方单独设置的语言优先；留空表示自动检测。'),
  'stt.local.initial_prompt': (
    '本地识别提示词',
    '传给 faster-whisper 的初始提示词，例如让中文输出偏向简体。',
  ),
  'stt.local.language': ('本地识别语言', '强制使用的语言代码，如 en、es；留空则自动检测。'),
  'stt.local.logprob_threshold': (
    '平均对数概率阈值',
    '过滤静音误识别：片段的平均对数概率低于该值、且无语音概率高于其阈值时才会被丢弃。',
  ),
  'stt.local.model': ('本地模型大小', '本地 faster-whisper 模型的规格。'),
  'stt.local.no_speech_prob_threshold': (
    '无语音概率阈值',
    '过滤静音误识别：片段的无语音概率高于该值、且平均对数概率低于其阈值时才会被丢弃。',
  ),
  'stt.local.unload_after_idle_seconds': (
    '空闲后卸载模型',
    '空闲多少秒后释放本地模型（在 GPU 上可释放显存），下次识别时重新加载；0 表示从不卸载。',
  ),
  'stt.local.vad': ('语音活动检测', '用 Silero VAD 过滤静音，避免静音被误识别成文字；识别音乐或环境声时可关闭。'),
  'stt.local.vad_min_silence_ms': ('最短静音间隔', '开启语音活动检测时，用于切分语音段的最短静音时长（毫秒）。'),
  'stt.mistral.language': ('Mistral 语言', '强制使用的语言代码，如 en、es；留空则自动检测。'),
  'stt.mistral.model': ('Mistral 模型', 'Mistral Voxtral 语音识别模型。'),
  'stt.openai.language': ('OpenAI 语言', '强制使用的语言代码，如 en、es；留空则自动检测。'),
  'stt.openai.max_retries': ('OpenAI 重试次数', 'OpenAI SDK 传输层的重试次数；0 表示不重试。'),
  'stt.openai.model': ('OpenAI 模型', 'OpenAI 语音识别模型。'),
  'stt.openai.streaming_model': (
    'OpenAI 实时识别模型',
    '开启实时识别（stt.streaming）时使用的 OpenAI 模型；gpt-live-transcribe 是唯一能在说话中途返回文字的模型。',
  ),
  'stt.openai.timeout': ('OpenAI 请求超时', '请求超时（秒）；自托管模型冷启动较慢时可调高。'),
  'stt.streaming': (
    '实时识别',
    '说话时实时显示识别出的文字（支持 OpenAI、xAI、ElevenLabs）；实时识别失败时改为录音结束后整体识别。',
  ),
  'stt.xai.language': ('xAI 语言', '强制使用的语言代码，如 en、es；留空则沿用全局识别语言，再不行则自动检测。'),
  'stt.xai.model': ('xAI 模型', 'xAI 语音识别模型。'),
  'telegram.allowed_chats': ('允许的群组', '填写后只在这些群组或超级群组的聊天 ID 中回复；留空则不限制。'),
  'telegram.extra.allow_cjk_rich_messages': (
    '中日韩内容用富文本',
    '中日韩内容默认使用旧版 MarkdownV2，因为 Telegram 桌面版和 macOS 版会显示错乱；客户端不受影响时可开启，以显示原生富文本表格。',
  ),
  'telegram.extra.dm_topic_auto_transfer': (
    '私聊自动开新话题',
    '仅在 /topic 模式下生效：在私聊主界面发送普通消息时，自动新建一个话题并在其中开始新会话。',
  ),
  'telegram.extra.rich_drafts': (
    '富文本草稿预览',
    '实验功能：私聊流式输出时使用富文本草稿预览。Telegram 桌面版和 macOS 版可能出现草稿画面重叠。',
  ),
  'telegram.extra.rich_messages': (
    '原生富文本消息',
    '使用 Bot API 10.1 原生富文本消息（表格、任务列表、数学公式）；关闭则使用便于复制的旧版 MarkdownV2。',
  ),
  'telegram.reactions': ('处理状态表情', '处理消息期间给消息添加 👀、✅、❌ 表情回应。'),
  'telemetry.shared_metrics.enabled': (
    '收集用量统计',
    '在本机汇总 Hermes 的使用统计，用于与 Nous 共享。只开启此项不会上传，需同时开启“上传用量统计”。',
  ),
  'telemetry.shared_metrics.endpoint': (
    '统计上传地址',
    '接收用量统计的服务地址，一般无需修改。非 HTTPS 地址会被拒绝（localhost 除外）。',
  ),
  'telemetry.shared_metrics.send': (
    '上传用量统计',
    '每天把汇总的用量统计发送给 Nous。需先开启“收集用量统计”；只发送完整处于已同意时段内的数据。',
  ),
  'terminal.auto_source_bashrc': (
    '自动加载 bash 配置文件',
    '准备会话的 shell 环境时，依次加载 ~/.profile、~/.bash_profile 和 ~/.bashrc，以获取其中的 PATH、函数和别名。若某个配置文件在非交互方式下加载会出错，可关闭。',
  ),
  'terminal.backend': (
    '终端运行环境',
    '智能体执行命令的位置：local 为本机，docker 为本机 Docker 容器，ssh 为远程服务器，modal、daytona、vercel_sandbox 为对应的云端沙箱。',
  ),
  'terminal.client_env_passthrough': (
    '客户端工具链变量',
    'CLI/TUI 客户端与网关在同一台机器上时，额外随会话传给本机工具的非机密环境变量名（如 GEM_HOME）。名称像凭据的变量和 HERMES_* 变量不会传递，密钥请改用“传入沙箱的环境变量”。',
  ),
  'terminal.container_cpu': (
    '容器 CPU 核数',
    '分配给容器沙箱的 CPU 核心数。适用于 docker、modal、daytona、vercel_sandbox 等容器后端，本机和 SSH 后端不受影响。',
  ),
  'terminal.container_disk': (
    '容器磁盘空间',
    '分配给容器沙箱的磁盘空间（MB），例如 51200 = 50GB。Daytona 每个沙箱最多 10GB；本机和 SSH 后端不受影响。',
  ),
  'terminal.container_memory': (
    '容器内存',
    '分配给容器沙箱的内存（MB），例如 5120 = 5GB。本机和 SSH 后端不受影响。',
  ),
  'terminal.container_persistent': (
    '保留容器文件',
    '开启后容器沙箱的文件系统在会话之间保留；关闭则每次都是全新环境。',
  ),
  'terminal.cwd': ('工作目录', '命令执行的起始目录。本机后端中“.”表示当前目录；SSH 和容器后端填写远程服务器或容器内的路径。'),
  'terminal.daemon_term_grace_seconds': (
    '进程强制结束等待',
    '结束本机后台进程树（如浏览器守护进程）时，发送终止信号后等待多少秒再强制结束。0 = 只发送终止信号。',
  ),
  'terminal.daytona_image': ('Daytona 镜像', 'Daytona 云沙箱使用的镜像。'),
  'terminal.degraded_mode': (
    '远程环境故障处理',
    '远程后端连接失败（如 SSH 主机不可达、Docker 未运行）时的处理：warn = 返回说明原因和重试建议的结果，fail = 直接报错。',
  ),
  'terminal.docker_extra_args': (
    'Docker 额外参数',
    '原样附加到 docker run 的额外参数，排在默认安全参数之后，例如添加 Linux 权能。',
  ),
  'terminal.docker_forward_env': (
    '转发到 Docker 的变量',
    '把指定的环境变量传入 Docker 容器，值先从当前 shell 读取，再从 ~/.hermes/.env 读取。转发的值对容器内运行的命令可见。',
  ),
  'terminal.docker_image': ('Docker 镜像', 'Docker 沙箱使用的镜像。'),
  'terminal.docker_mount_cwd_to_workspace': (
    '挂载当前目录到容器',
    '把启动时所在的目录挂载到容器的 /workspace。默认关闭，开启会削弱隔离。',
  ),
  'terminal.docker_network': (
    '容器联网',
    '允许容器内的命令访问网络。关闭后以 --network=none 运行，无法联网。',
  ),
  'terminal.docker_run_as_host_user': (
    '以本机用户运行容器',
    '以本机用户的 uid:gid 运行容器，挂载目录中写入的文件归你所有而不是 root。镜像需要以 root 启动时请保持关闭。',
  ),
  'terminal.docker_shared_container_key': (
    '共享容器标识',
    '多个可信 profile 填写相同的值时共用同一个 Docker 容器。留空则每个 profile 各自独立。',
  ),
  'terminal.docker_shm_size': (
    '容器共享内存大小',
    'Docker 沙箱的 /dev/shm 大小，例如 1g。Docker 默认的 64 MB 会让 Chromium、Playwright 等出错。留空或 0 = 使用 Docker 默认值。',
  ),
  'terminal.docker_snap_compat': (
    'Snap 版 Docker 兼容',
    'Ubuntu 上通过 Snap 安装的 Docker 在 AppArmor 下会拒绝 --init 和 no-new-privileges。开启后去掉这两个参数，其余加固保持不变。',
  ),
  'terminal.docker_volumes': (
    'Docker 挂载卷',
    '要挂载到容器的目录，格式为“本机路径:容器路径”（同 docker -v）。',
  ),
  'terminal.env_passthrough': (
    '传入沙箱的环境变量',
    '传入终端和代码执行沙箱的环境变量名；技能声明需要的变量会自动加入。',
  ),
  'terminal.font_family': (
    '终端字体',
    '桌面应用内置终端使用的字体，可填 CSS 字体列表，需先在本机安装。留空则使用内置的 JetBrains Mono。',
  ),
  'terminal.home_mode': (
    '工具 HOME 目录',
    '工具子进程使用的 HOME：auto = 本机用真实 HOME、容器用 profile 目录下的 home；real = 始终用真实 HOME；profile = 始终用 profile 目录下的 home，实现严格隔离。',
  ),
  'terminal.modal_image': ('Modal 镜像', 'Modal 云沙箱使用的镜像。'),
  'terminal.modal_mode': (
    'Modal 接入方式',
    '使用 Nous 托管的 Modal 还是你自己的 Modal 账号。运行时识别 auto、managed、direct：auto 在托管可用时优先使用托管，否则使用自己的凭据。',
  ),
  'terminal.oneshot_completion_wait_seconds': (
    '单次运行等待时长',
    '单次运行的命令行（-q/-Q/-z）退出前，最多等待多少秒让设置了完成通知的后台进程结束，以免结果丢失。0 = 不等待。',
  ),
  'terminal.persistent_shell': (
    '保持 shell 状态',
    'SSH 后端中，命令之间保留已导出的环境变量（工作目录始终保留）。关闭后每条命令都从登录环境重新开始。',
  ),
  'terminal.process_wait_auto_notify': (
    '后台进程自动通知',
    '连续两次查看运行中的后台进程都没有新输出时，自动改为完成后通知，并让智能体停止反复查看。关闭则照常轮询。',
  ),
  'terminal.shell_init_files': (
    '额外 shell 初始化文件',
    '准备会话环境时额外加载的文件，用于引入 nvm、pyenv、asdf 等登记的 PATH。支持 ~ 和 \${VAR}，不存在的文件会跳过。留空且使用 bash 时，自动加载 ~/.profile、~/.bash_profile、~/.bashrc。',
  ),
  'terminal.sync_back_max_bytes': (
    '同步回传大小上限',
    '远程后端回传状态压缩包时允许的最大字节数，超过则拒绝解压。~/.hermes 确实超过 2 GiB 时可调大。',
  ),
  'terminal.temp_dir': (
    '终端临时目录',
    '终端会话临时文件（后台日志、代码执行沙箱等）的存放位置，须为已存在的绝对 POSIX 路径。留空则使用 TMPDIR/TMP/TEMP，均未设置时使用 Hermes 缓存目录（72 小时后自动清理）。',
  ),
  'terminal.timeout': ('命令超时', '命令未指定超时时，默认最长运行的秒数。'),
  'terminal.vercel_image': (
    'Vercel 沙箱镜像',
    'vercel_sandbox 后端使用的镜像：Vercel 托管镜像（如 vercel/sandbox/universal:latest）或 VCR 仓库[:tag]。',
  ),
  'terminal.vercel_runtime': (
    'Vercel 旧版运行时',
    '已被 Vercel 弃用的旧版运行时。设置后会覆盖镜像设置，清空则使用镜像。',
  ),
  'timezone': ('时区', '使用 IANA 时区名（如 Asia/Shanghai）。留空则使用系统时区。'),
  'tool_loop_guardrails.hard_stop_after.exact_failure': (
    '重复失败拦截次数',
    '本轮中同一工具以相同参数失败达到此次数后，拦截该调用。仅在强制停止生效的会话中起作用。',
  ),
  'tool_loop_guardrails.hard_stop_after.idempotent_no_progress': (
    '无进展拦截次数',
    '本轮中只读工具反复返回相同结果达到此次数后，拦截该调用。仅在强制停止生效的会话中起作用。',
  ),
  'tool_loop_guardrails.hard_stop_after.same_tool_failure': (
    '同工具失败停止次数',
    '本轮中同一工具失败（参数可不同）达到此次数后，停止调用该工具。仅在强制停止生效的会话中起作用。',
  ),
  'tool_loop_guardrails.hard_stop_enabled': (
    '交互会话强制停止',
    '在 CLI、TUI、桌面应用等交互会话中，达到强停次数时拦截重复的工具调用。默认关闭，只给出提醒。',
  ),
  'tool_loop_guardrails.loop_caps.max_subagents': (
    '每轮子智能体上限',
    '每轮最多创建的子智能体数量，每轮重新计数，不受其他开关影响。0 = 不限制。',
  ),
  'tool_loop_guardrails.loop_caps.max_web_searches': (
    '每轮网页搜索上限',
    '每轮最多调用网页搜索的次数，每轮重新计数，不受其他开关影响。0 = 不限制。',
  ),
  'tool_loop_guardrails.non_interactive_hard_stop_enabled': (
    '无人值守强制停止',
    '在网关、定时任务等无人值守会话中，达到强停次数时拦截重复的工具调用，因为没有人能手动停止。',
  ),
  'tool_loop_guardrails.warn_after.exact_failure': (
    '重复失败提醒次数',
    '本轮中同一工具以相同参数失败达到此次数后，提醒模型换个方法。',
  ),
  'tool_loop_guardrails.warn_after.idempotent_no_progress': (
    '无进展提醒次数',
    '本轮中只读工具反复返回相同结果达到此次数后，提醒模型使用已有结果或换个查询。',
  ),
  'tool_loop_guardrails.warn_after.same_tool_failure': (
    '同工具失败提醒次数',
    '本轮中同一工具失败（参数可不同）达到此次数后，提醒模型换个方法。',
  ),
  'tool_loop_guardrails.warnings_enabled': (
    '循环提醒',
    '模型反复失败或无进展地调用工具时，在工具结果中附加提醒，但仍允许执行。',
  ),
  'tool_output.max_bytes': ('终端输出上限', '终端命令输出返回给模型的最大字符数，超出时保留开头和结尾，中间省略。'),
  'tool_output.max_line_length': ('单行长度上限', '读取文件时每行最多保留的字符数，超出部分标记为已截断。'),
  'tool_output.max_lines': ('单次读取行数上限', '读取文件时一次最多返回的行数，更多内容需分页读取。'),
  'tools.connectors.enabled': (
    '远程连接器',
    '通过 Nous 工具网关发现和管理远程连接器。还需登录 Nous Portal 才能使用。',
  ),
  'tools.tool_search.defer': (
    '延后加载的工具',
    '这些工具不直接提供给模型，需通过工具搜索按需调出。填写后会整体替换默认列表；空列表则所有工具都直接提供。',
  ),
  'tools.tool_search.enabled': (
    '工具搜索',
    '用一个搜索入口代替部分工具，节省上下文。auto 或 on = 存在延后加载的工具时启用；off = 关闭。',
  ),
  'tools.tool_search.listing': (
    '工具目录清单',
    '是否在工具搜索入口中附上可用工具的名称和简介：auto = 放得下时附上，on = 效果同 auto 但明确开启，off = 不附。',
  ),
  'tools.tool_search.listing_max_tokens': (
    '目录清单 token 上限',
    '工具目录清单最多占用的 token 数，不随上下文大小变化。范围 200 至 60000。',
  ),
  'tools.tool_search.max_search_limit': (
    '单次搜索结果上限',
    '模型每次搜索工具时最多可请求的结果数。范围 1 至 50。',
  ),
  'tools.tool_search.search_default_limit': ('默认搜索结果数', '模型搜索工具且未指定数量时返回的结果数。'),
  'tools.tool_search.threshold_pct': (
    '目录清单上下文占比',
    '工具目录清单可占用的上下文窗口百分比，实际预算取此比例与 token 上限中较小者。范围 0 至 100。',
  ),
  'toolsets': ('工具集（旧版）', '旧版的顶层工具集列表，已弃用并被忽略。工具集现在按消息平台分别设置。'),
  'tts.deepinfra.model': (
    'DeepInfra 模型',
    'DeepInfra 语音合成使用的模型。留空则使用在线目录中的第一个语音合成模型。',
  ),
  'tts.deepinfra.voice': ('DeepInfra 音色', 'DeepInfra 语音合成使用的音色。'),
  'tts.edge.voice': ('Edge 音色', 'Edge 语音合成的音色名，例如 en-US-AriaNeural。'),
  'tts.elevenlabs.model_id': (
    'ElevenLabs 模型',
    'ElevenLabs 语音合成使用的模型 ID，例如 eleven_multilingual_v2。',
  ),
  'tts.elevenlabs.voice_id': ('ElevenLabs 音色', 'ElevenLabs 语音合成使用的音色 ID。'),
  'tts.gemini.audio_tags': (
    'Gemini 音频标签',
    '开启后由辅助模型改写朗读稿，插入 [音频标签]（Gemini 3.1），只影响语音合成的文本。',
  ),
  'tts.gemini.model': ('Gemini 模型', 'Gemini 语音合成使用的模型。'),
  'tts.gemini.persona_prompt_file': (
    'Gemini 表演指示文件',
    '可选的本地文本文件，写明朗读的语气和风格。可包含 {transcript} 占位符，否则会在末尾附上实际朗读的文本。',
  ),
  'tts.gemini.voice': ('Gemini 音色', 'Gemini 语音合成使用的音色，例如 Kore。'),
  'tts.keep_warm_seconds': (
    '本地引擎保温时长',
    '关闭语音后，本地引擎（Piper、KittenTTS）继续保持加载的秒数，便于很快再次使用时无需重新加载。0 = 立即卸载。',
  ),
  'tts.kittentts.model': ('KittenTTS 模型', 'KittenTTS 本地语音合成使用的模型。'),
  'tts.kittentts.voice': ('KittenTTS 音色', 'KittenTTS 使用的音色，例如 Jasper。'),
  'tts.minimax.model': ('MiniMax 模型', 'MiniMax 语音合成使用的模型。'),
  'tts.minimax.voice_id': ('MiniMax 音色', 'MiniMax 语音合成使用的音色 ID。'),
  'tts.mistral.model': ('Mistral 模型', 'Mistral 语音合成使用的模型。'),
  'tts.mistral.voice_id': ('Mistral 音色', 'Mistral 语音合成使用的音色 ID。'),
  'tts.neutts.device': ('NeuTTS 运行设备', 'NeuTTS 在哪个设备上运行：cpu、cuda 或 mps。'),
  'tts.neutts.model': ('NeuTTS 模型', 'NeuTTS 使用的 HuggingFace 模型仓库。'),
  'tts.neutts.ref_audio': ('NeuTTS 参考音频', '参考音色的音频文件路径。留空则使用内置默认音色。'),
  'tts.neutts.ref_text': ('NeuTTS 参考文本', '参考音频对应文字稿的文件路径。留空则使用内置默认值。'),
  'tts.openai.consent_attestation': (
    'OpenAI 声音授权声明',
    '部分 OpenAI 兼容服务的克隆音色要求在请求中附带授权声明，此值会原样发送。留空则不发送。',
  ),
  'tts.openai.model': ('OpenAI 模型', 'OpenAI 语音合成使用的模型，例如 gpt-4o-mini-tts。'),
  'tts.openai.pcm_sample_rate': (
    'OpenAI PCM 采样率',
    '流式播放时原始 PCM 音频的采样率（Hz）。OpenAI 输出 24 kHz；兼容服务若在响应中报告采样率，会自动覆盖此值。',
  ),
  'tts.openai.voice': ('OpenAI 音色', 'OpenAI 语音合成使用的音色，例如 alloy。'),
  'tts.piper.voice': ('Piper 音色', 'Piper 的音色名（首次使用时下载），或 .onnx 文件的绝对路径。'),
  'tts.provider': (
    '语音合成提供方',
    '用哪个服务把文字转成语音。edge 免费；neutts、kittentts、piper 在本机运行。',
  ),
  'tts.streaming.min_len': (
    '流式朗读首句最短长度',
    '流式语音合成时，首句至少多少字符才单独朗读，更短的会与下一句合并。英文适合 20，中文等约 6。',
  ),
  'tts.xai.auto_speech_tags': ('xAI 自动语气标签', '开启后由模型改写文本，插入表现语气的音频标签。'),
  'tts.xai.bit_rate': ('xAI 码率', 'MP3 码率（bps），仅在输出格式为 MP3 时生效。'),
  'tts.xai.language': ('xAI 朗读语言', 'BCP-47 语言代码（如 en、pt-BR），或填 auto 自动识别。'),
  'tts.xai.optimize_streaming_latency': (
    'xAI 流式延迟优化',
    '取值 0 至 2，数值越高延迟越低，但音质会下降。',
  ),
  'tts.xai.sample_rate': (
    'xAI 采样率',
    '输出音频的采样率（Hz），可选 22050、24000、44100、48000。',
  ),
  'tts.xai.speed': ('xAI 语速', '朗读速度倍率，范围 0.7 至 1.5。'),
  'tts.xai.voice_id': ('xAI 音色', 'xAI 语音合成的音色，如 eve，也可填自定义音色 ID。'),
  'updates.auto_switch_parked_branch': (
    '自动切回更新分支',
    'Hermes 源码停在其他分支且没有未提交改动时，自动切换到更新目标分支，原分支上的提交保留。有未提交改动时会跳过代码更新。关闭则从不自动切换。',
  ),
  'updates.backup_keep': ('保留完整备份数', '更新前完整备份最多保留的份数，每次成功后清理更早的，至少保留最新一份。'),
  'updates.check': (
    '检查更新',
    '被动检查新版本并在启动横幅等处提示。手动执行 hermes update --check 不受影响。',
  ),
  'updates.non_interactive_local_changes': (
    '后台更新时的本地改动',
    '在聊天应用或网关中更新 Hermes（不弹出终端提示）时，如何处理未提交的源码改动：stash = 保留并在更新后恢复，discard = 丢弃。在终端中更新时总会询问。',
  ),
  'updates.parked_branch_strategy': (
    '停留分支处理方式',
    '源码停在含未合并提交的分支时：switch = 切换到更新目标分支，提交留在原分支；update_in_place = 先打标签再把上游合并进当前分支，有冲突则停止更新。',
  ),
  'updates.pre_update_backup': (
    '更新前备份',
    '更新前的安全备份：quick = 快速保存关键状态（配置、定时任务、配对信息等），full = 另外打包完整备份，off = 不备份。超过 1 GiB 的文件会跳过。',
  ),
  'updates.refresh_cua_driver': (
    '更新时刷新 cua-driver',
    '执行 hermes update 时刷新已安装的 cua-driver（仅 macOS）。在 /Applications 不可写的非管理员 macOS 账户上请关闭。',
  ),
  'vault.bitwarden.binary_path': (
    'Bitwarden 程序路径',
    'bw 命令行程序的绝对路径。留空则从 PATH 查找。',
  ),
  'vault.bitwarden.enabled': (
    '使用 Bitwarden',
    '允许浏览器密码库从 Bitwarden（bw 命令行，密码管理器版）取用登录项。首次使用前需执行一次 bw login。',
  ),
  'vault.key_storage': (
    '密码库密钥存放',
    '新建本地密码库时加密密钥的存放方式：file = 仅本人可读的密钥文件，keychain = 系统钥匙串（不可用时改用文件）。',
  ),
  'vault.onepassword.account': (
    '1Password 账户',
    '传给 op --account 的账户简称。留空则使用默认账户。',
  ),
  'vault.onepassword.binary_path': (
    '1Password 程序路径',
    'op 命令行程序的绝对路径。留空则从 PATH 查找。',
  ),
  'vault.onepassword.enabled': (
    '使用 1Password',
    '允许浏览器密码库从 1Password（op 命令行）取用登录项，带网址的登录项可用于填写。',
  ),
  'vault.onepassword.service_account_token_env': (
    '1Password 服务账户变量',
    '存放服务账户令牌的环境变量名，设置后无需解锁提示即可使用，适合无人值守。未设置则提示解锁。',
  ),
  'vertex.project_id': (
    'Vertex 项目 ID',
    'Google Cloud 项目 ID。留空则从服务账号 JSON（或应用默认凭据）中读取。',
  ),
  'vertex.region': (
    'Vertex 区域',
    'Vertex AI 调用的区域。Gemini 3.x 预览模型需要 global；仅当模型限定区域时才填写如 us-central1。',
  ),
  'vision.embed_target_bytes': (
    '单张图片大小预算',
    '嵌入给模型的单张图片目标大小（字节），限制在 64 KiB 至 4 MiB 之间。手机截图中的表格看不清时可调大。',
  ),
  'vision.max_calls_per_image': (
    '同一图片分析次数上限',
    '每个会话中同一张图片（含局部裁剪）可被图像分析的次数。留空 = 子智能体内为 3、主智能体不限；填数字则统一生效；0 = 不限。',
  ),
  'vision.replay_recent_images': (
    '重发最近图片数',
    '从历史记录重建会话时，重新发送给模型的最近用户图片数量。0 = 关闭。',
  ),
  'voice.auto_tts': ('语音输入自动朗读回复', '收到语音输入时，默认用语音合成朗读回复。各聊天可用 /voice 单独开关。'),
  'voice.barge_in': ('说话打断', '用户开始说话时打断智能体并停止朗读。'),
  'voice.barge_in_grace_seconds': ('打断保护时长', '开始朗读后的这段时间（秒）内不触发打断，麦克风仍保持开启。'),
  'voice.barge_in_threshold_multiplier': (
    '打断音量倍数',
    '触发打断的音量 = 安静环境底噪 × 此倍数，底噪在播放前测定。数值越大越不容易触发。',
  ),
  'voice.beep_enabled': ('录音提示音', 'CLI 语音模式下开始和结束录音时播放提示音。'),
  'voice.beep_volume': ('提示音音量', '提示音的音量倍数，范围 0.0 至 1.0。思考音效也使用此音量。'),
  'voice.client_direct': ('客户端直连语音服务', '桌面远程客户端直接调用语音识别和语音合成服务，不经网关中转。'),
  'voice.gpt_live.instructions': (
    'GPT-Live 附加指示',
    '追加到实时语音模型对话人设中的额外说明，例如语气、节奏、语言。',
  ),
  'voice.gpt_live.model': ('GPT-Live 模型', 'gpt-live 语音对话方式使用的模型。'),
  'voice.gpt_live.voice': ('GPT-Live 音色', '实时语音模型的音色，例如 marin。'),
  'voice.max_recording_seconds': ('单次录音最长时长', '单次录音最多持续的秒数。'),
  'voice.record_key': ('录音快捷键', '终端界面中用于语音录音的快捷键，例如 ctrl+b。'),
  'voice.silence_duration': ('静音自动停止时长', '静音持续多少秒后自动停止录音。'),
  'voice.silence_threshold': ('静音判定阈值', '音量（RMS）低于此值视为静音，范围 0 至 32767。'),
  'voice.stop_phrases': (
    '结束语音聊天口令',
    '完整说出其中一句（不区分大小写，忽略标点）即结束语音聊天，这句话不会发给智能体。空列表则停用。',
  ),
  'voice.submit_mode': (
    '语音提交方式',
    'TUI 中：direct = 识别后立即发送，draft = 先放入输入框，可修改后再发送。',
  ),
  'voice.thinking_sound': ('思考音效', '智能体工作时播放轻微的气泡音效，音量同提示音。'),
  'voice.voice_chat_mode': (
    '语音对话方式',
    '桌面应用语音对话的方式：chained = 语音识别 → Hermes → 语音合成；gpt-live = 由 OpenAI GPT-Live 全双工语音模型负责收听和说话，实际请求交给 Hermes，需要 OpenAI API 密钥，语音层按每分钟 0.05 美元计费。',
  ),
  'wake_word.capture': (
    '唤醒词收音方式',
    '麦克风音频的来源：local = 本机直接收音，client = 由桌面应用传入，auto = 自动选择。',
  ),
  'wake_word.confirmation_frames': (
    '唤醒确认帧数',
    '仅 openWakeWord：连续多少帧超过阈值才触发。越大误触越少但响应越慢；1 = 单帧即触发。',
  ),
  'wake_word.enabled': ('唤醒词', '始终在本机监听唤醒词，听到后开始语音会话。可用 /wake 切换。'),
  'wake_word.input_device': ('唤醒词输入设备', 'PortAudio 输入设备的编号或名称。留空则使用默认设备。'),
  'wake_word.openwakeword.model': (
    'openWakeWord 模型',
    '填 hey_hermes、openWakeWord 内置唤醒词名（如 hey_jarvis），或自定义 .tflite 模型的路径。',
  ),
  'wake_word.phrase': ('唤醒短语', '在 sherpa 引擎中即为实际检测的短语；其他引擎仅作显示，检测取决于所选模型或关键词。'),
  'wake_word.porcupine.keyword': (
    'Porcupine 关键词',
    'Porcupine 内置关键词（如 jarvis），或自定义 .ppn 文件的路径。',
  ),
  'wake_word.profile_routing': (
    '按 profile 分流唤醒',
    '仅 sherpa：同时监听所有开启唤醒词的 profile 的短语，并转到对应的 profile。',
  ),
  'wake_word.provider': (
    '唤醒词引擎',
    'auto 自动选择当前平台支持的引擎；Porcupine 需要 PORCUPINE_ACCESS_KEY。',
  ),
  'wake_word.sensitivity': ('唤醒灵敏度阈值', '0.0 至 1.0 的检测阈值，各引擎含义一致；数值越高越严格。'),
  'wake_word.sherpa.model_dir': (
    'sherpa 模型目录',
    'sherpa-onnx 关键词识别模型所在的目录。留空则自动下载小型英文模型。',
  ),
  'wake_word.start_new_session': ('唤醒时新建会话', '唤醒后开始新会话；关闭则继续当前会话。'),
  'wake_word.surface': (
    '唤醒词响应界面',
    '由哪个界面响应唤醒词：auto = 最先认领的界面，也可指定 cli、tui 或 gui。',
  ),
  'web.backend': ('网页工具后端', '网页搜索和网页提取共用的后端，可分别用搜索后端和提取后端覆盖。'),
  'web.cache_enabled': (
    '网页结果缓存',
    '有效期内重复的搜索和提取直接使用缓存结果，相同的并发搜索合并为一次请求。只缓存成功的结果。',
  ),
  'web.cache_exempt_hosts': (
    '不缓存的网站',
    '这些网站总是实时获取，不使用提取缓存。可写完整域名、*. 通配或域名后缀；localhost 和内网地址始终不缓存。',
  ),
  'web.cache_ttl_minutes': ('缓存有效期', '网页搜索和提取结果的缓存时长（分钟）。'),
  'web.extract_backend': ('网页提取后端', '网页提取单独使用的后端，例如 native。留空则使用网页工具后端。'),
  'web.extract_char_limit': (
    '网页提取字符上限',
    '每个网页提取最多返回的字符数，更长的页面会被截断，完整文本保存在缓存中。',
  ),
  'web.keyless_fallback': (
    '免密钥备用搜索',
    '未配置任何网页后端时，网页搜索和提取轮流使用 exa、parallel、firecrawl、keenable 的免费额度，遇到限流自动切换。不会取代已配置的后端。',
  ),
  'web.keyless_rescue': (
    '失败时免密钥重试',
    '所选后端调用失败时，该次调用改用免费额度重试一次，下次仍先用所选后端。关闭“免密钥备用搜索”时此项不生效。',
  ),
  'web.search_backend': ('网页搜索后端', '网页搜索单独使用的后端，例如 searxng。留空则使用网页工具后端。'),
  'webapp.enabled': ('网页应用', '在网关自己的 HTTP 端口上提供浏览器版的桌面应用。'),
  'webapp.host': (
    '网页应用监听地址',
    '可填 127.0.0.1、::1、localhost 等仅本机地址，或 0.0.0.0、:: 等通配地址；通配地址需要控制台登录才能访问。',
  ),
  'webapp.port': ('网页应用端口', '网页应用监听的端口。端口固定，浏览器中的地址在重启后保持不变。'),
  'webapp.public_url': ('网页应用公开地址', '通过反向代理或隧道对外提供网页应用时的地址。设置后即使只监听本机也会要求登录。'),
  'worktrees.archive_dirty': (
    '清理前归档改动',
    '闲置的工作树有未提交改动或未推送提交时，先完整归档再删除，归档失败则保留。关闭则从不删除这类工作树。',
  ),
  'worktrees.archive_max_file_mb': (
    '归档单文件上限',
    '大于此大小（MB）的未跟踪文件不会归档，含有这类文件的工作树会被保留。',
  ),
  'worktrees.archive_retention_days': ('归档保留天数', '超过此天数的归档会被清理。0 = 永久保留。'),
  'worktrees.install_state_retention_days': (
    '安装状态保留天数',
    '工作树已不存在时，其依赖安装状态闲置超过此天数即删除。0 = 永不删除。',
  ),
  'worktrees.max_total_gb': (
    '闲置工作树空间上限',
    '闲置工作树的总大小上限（GB），超出时先归档并删除最旧的。正在使用的、较新的和看板的工作树不计入也不处理。0 = 关闭。',
  ),
  'x_search.model': ('X 搜索模型', 'X 搜索使用的 xAI 模型，任何支持 x_search 的 Grok 模型均可。'),
  'x_search.reasoning_effort': ('X 搜索推理强度', '支持推理的模型使用的推理强度。留空则使用模型默认值。'),
  'x_search.retries': ('X 搜索重试次数', '遇到服务器错误、读取超时或连接错误时的重试次数。'),
  'x_search.timeout_seconds': (
    'X 搜索超时',
    '单次请求的超时时间（秒），最少 30。复杂查询可能需要 60 至 120 秒。',
  ),
};

/// Command → what it does.
const hermesCommandZh = <String, String>{
  '/agents': '列出原生子智能体和进程的 ID；可查看子智能体的最新输出、引导或停止它，结束进程，暂停或恢复创建子智能体。',
  '/approvals': '查看或设置危险命令的审批模式，设置会长期保留。用法：/approvals [manual|smart|off]',
  '/architecture-diagram': '生成深色主题的 SVG 架构图、云和基础设施图，以 HTML 呈现。',
  '/arxiv': '按关键词、作者、分类或 ID 搜索 arXiv 论文。',
  '/ascii-video': '把视频或音频转换成彩色 ASCII 风格的 MP4 或 GIF。',
  '/autoprune':
      '开启或关闭旧会话的自动清理，later 表示一周后再提醒。用法：/autoprune [on|off|later|status]',
  '/baoyu-infographic': '制作信息图，提供 21 种布局和 21 种风格。',
  '/battery': '在状态栏中显示或隐藏按颜色区分的电量指示。用法：/battery [on|off|status]',
  '/bg': '在单独的后台会话中运行一条提示词。用法：/bg <提示词>',
  '/blocked-page-recovery': '网页抓取失败（403/429、付费墙、WAF、机器人拦截）时，改从存档等其他途径获取内容。',
  '/blueprint': '用蓝图模板设置一项自动化。用法：/blueprint [名称] [槽位=值 ...]',
  '/branch': '为此 Bot 的原生会话创建分支，并在这里继续使用该分支。用法：/branch [名称]',
  '/browser': '通过 CDP 把浏览器工具连接到你正在使用的 Chromium 系浏览器。用法：/browser [connect|disconnect|status]',
  '/btw': '就当前对话顺带问个问题，不会打断正在进行的对话。用法：/btw <问题>',
  '/bundles': '列出技能组合（用 /<名称> 一次调用多个技能）。',
  '/busy': '设置 Hermes 工作期间新消息的处理方式（排队、引导或打断）。用法：/busy [queue|steer|interrupt|status]',
  '/claude-code': '把编码工作委派给 Claude Code CLI（开发功能、提交 PR）。',
  '/claude-design': '设计一次性的 HTML 作品（落地页、演示文稿、原型）。',
  '/clear': '重新开始一个全新的 Hermes 上下文；App 中已有的消息和工具已产生的结果都会保留。',
  '/codebase-inspection': '用 pygount 分析代码库：代码行数、语言构成和各类占比。',
  '/codex': '把编码工作委派给 OpenAI Codex CLI（开发功能、提交 PR）。',
  '/codex-runtime': '为 OpenAI/Codex 模型切换 Codex app-server 运行时。用法：/codex-runtime [auto|codex_app_server]',
  '/competitor-news-monitor': '关注指定公司的重要新闻，生成附带出处的摘要。',
  '/compress': '压缩对话上下文（加上 here [N] 可保留最近 N 轮；--preview 可预览压缩效果）。用法：/compress [here [N] | focus 主题 | --preview|--dry-run]',
  '/computer-use': '在后台操作桌面，不干扰你的鼠标和键盘；收到需要的信号时才切换到前台操作。',
  '/config': '显示当前配置。',
  '/context': '详细查看上下文窗口：用量仪表、分类明细、上下文压缩统计和吞吐量。用法：/context [all]',
  '/copy': '把最近一条助手回复复制到剪贴板。用法：/copy [序号]',
  '/cron': '管理定时任务。用法：/cron [子命令]',
  '/curator': '后台技能整理（状态、运行、固定、归档、查看已归档）。用法：/curator [子命令]',
  '/debug': '上传调试报告（系统信息和日志），并获取可分享的链接。用法：/debug [nous|local]',
  '/density': '切换紧凑显示模式。',
  '/diff': '显示工作目录中的 Git 改动。用法：/diff [staged|all|session] [--stat] [路径...]',
  '/document-to-action-items': '从文档中提取义务、截止日期和待办事项，并注明出处。',
  '/dogfood': '对网页应用做探索式测试：发现问题、保留证据并撰写报告。',
  '/egress': '显示 Docker 出站代理的状态。用法：/egress [status]',
  '/email-inbox-triage': '整理收件箱：为邮件排出优先级，并稳妥地起草回复。',
  '/export': '把此 Bot 可分享的 profile 导出为文件卡片。用法：/export',
  '/fast': '快速模式，使用 OpenAI 优先处理或 Anthropic 快速模式。用法：/fast [normal|fast|auto|cold|ultrafast|status] [--global]',
  '/focus': '开关专注视图，只显示你的提示词和最终回复。用法：/focus [on|off|status]',
  '/footer': '开关网关最终回复末尾的运行信息脚注。用法：/footer [on|off|status]',
  '/github': '通过 gh CLI 使用 GitHub：PR、Issue、代码审查、仓库和身份验证。',
  '/goal': '设置一个长期目标，Hermes 会跨多轮持续推进，直到达成。用法：/goal [文本 | -- <文本> | draft <文本> | show | gate add <命令> | pause | resume | clear | status | wait <pid> | unwait]',
  '/google-workspace': '通过 gws CLI 或 Python 使用 Gmail、Google 日历、云端硬盘、文档和表格。',
  '/grounded-citations': '让回答和文档以可核实的来源为依据，并附上引用。',
  '/handoff': '把此会话转交到消息平台（Telegram、Discord 等）继续。用法：/handoff <平台>',
  '/hatch': '根据描述生成一只新的 petdex 宠物。用法：/hatch [描述]',
  '/heartbeat': '查看、暂停或停止原生心跳（会话空闲时定期重新执行的提示词）。Hermes v0.22.5 不会为本地网关会话触发心跳。用法：/heartbeat [status|pause|stop]',
  '/help':
      '显示可用命令（/help skills 列出技能命令，/help <文字> 按文字筛选）。用法：/help [skills|<筛选词>]',
  '/hermes-agent': '使用、配置、更换主题、扩展和编排 Hermes Agent。',
  '/himalaya': 'Himalaya CLI：在终端中通过 IMAP/SMTP 收发邮件。',
  '/history': '显示对话历史。',
  '/humanizer': '让文字更像人写的：去掉 AI 腔，加入真实的语气。',
  '/image': '添加本设备上的图片作为附件；不填路径时打开系统文件选择器。用法：/image [Windows 路径]',
  '/import': '打开 App 表单，把 profile 压缩包导入为新 Bot。用法：/import',
  '/indicator':
      '选择终端界面（TUI）中忙碌指示的样式。用法：/indicator [ascii|emoji|kaomoji|unicode]',
  '/init': '扫描代码仓库，生成或更新 AGENTS.md 项目说明。用法：/init [备注]',
  '/insights': '显示用量洞察和统计分析。用法：/insights [天数]',
  '/journey': '浏览或编辑原生学习记录。用法：/journey [list | edit <记录 ID>]',
  '/kanban': '多 profile 协作看板（任务、关联、评论）。用法：/kanban [子命令]',
  '/learn': '从你描述的任何内容（目录、URL、这段对话、笔记）中学习一个可复用的技能。用法：/learn <学习来源>',
  '/login': '打开模型授权和自定义 API 来源。用法：/login',
  '/logs': '显示最近的网关日志。',
  '/loop': '在此会话中按固定间隔重复运行一条提示词。用法：/loop [间隔] <提示词> [--times N] [--until <条件>] | status | pause | resume | stop',
  '/manim-video': '用 Manim CE 制作 3Blue1Brown 风格的数学和算法动画视频。',
  '/maps': '通过 OpenStreetMap/OSRM 进行地理编码、查找地点、规划路线和查询时区。',
  '/meeting-action-items': '把会议记录整理成附带出处的决定、负责人和工单。',
  '/memory': '审查待写入的记忆，或开关记忆写入前的审批。用法：/memory [pending|approve|reject|approval] [ID|on|off]',
  '/microsoft-office': '创建、读取和编辑 Word、PowerPoint 和 Excel 文件。',
  '/moa': '用此 profile 的原生多模型协作（MoA）预设运行一条提示词，下一轮恢复常规模型。预设可在 Bot 设置中配置。用法：/moa <提示词>',
  '/model': '打开 Bot 模型设置，或为本会话选择模型。用法：/model <模型 ID> [--provider 提供方] [--reasoning 级别]',
  '/mouse': '设置终端的鼠标跟踪预设。用法：/mouse [on|off|toggle|wheel|buttons|all]',
  '/nekodot-routine-status': '读取原生例行任务的执行记录。',
  '/nekodot-routines': '在 nekodot 中创建 Webhook 例行任务，并为定时任务添加 Webhook 触发器。',
  '/nekodot-secrets': '通过加密聊天卡片请求 API 密钥、密码或私钥；配置服务和浏览器登录，不会把这些值暴露给模型。',
  '/new': '开始一个新会话（新的会话 ID 和历史记录）。用法：/new [名称]',
  '/obsidian': '在 Obsidian 库中读取、搜索、创建和编辑笔记。',
  '/p5js': '用 p5.js 创作草图：生成艺术、着色器、交互作品和 3D。',
  '/palette': '打开模糊搜索命令面板（也可按 Ctrl+P）。',
  '/paste': '把剪贴板中的图片添加为附件。',
  '/pdf': '处理 PDF 文件：创建、读取、合并、填写、OCR 识别和编辑文字。',
  '/personality': '设置一个预设人格。用法：/personality [名称]',
  '/pet': '显示、隐藏或领养一只 petdex 宠物（/pet、/pet list、/pet <标识>）。用法：/pet [toggle|list|scale <n>|<标识>]',
  '/plan': '把实施计划写成 Markdown 文件保存到 .hermes/plans/，不执行任何操作。用法：/plan [任务]',
  '/platforms': '显示网关和各消息平台的状态。',
  '/plugins': '列出已安装的插件及其状态。',
  '/popular-web-designs': '以 HTML/CSS 呈现 54 套真实的设计系统（Stripe、Linear、Vercel 等）。',
  '/product-price-monitor': '关注商品、机票或房源价格，达到目标价时提醒你。',
  '/profile': '显示当前 profile 的名称和主目录。',
  '/prompt': '在 App 输入框中预先填入内容，但不发送。用法：/prompt [文本]',
  '/queue': '把一条原生输入加入队列，可查看、取消、编辑，或把某条转为引导消息。编辑过的条目会移到队尾。用法：/queue <提示词> | list | rm N | edit N <提示词> | steer N',
  '/quit': '退出 Windows App，或让 Android App 转到后台；服务器上的任务和历史记录会保留。用法：/quit',
  '/reasoning':
      '管理推理强度和推理内容的显示方式。用法：/reasoning [级别|show|hide|full|clamp] [--global]',
  '/redraw': '刷新本应用并同步消息，不会重新执行任务。',
  '/refine': '立即回顾这段对话，把经验保存到记忆或技能中。用法：/refine [重点说明]',
  '/reload': '把 .env 中的变量重新加载到正在运行的会话。',
  '/reload-mcp': '按配置重新加载 MCP 服务器。',
  '/reload-skills': '重新扫描 ~/.hermes/skills/，识别新安装或已移除的技能。',
  '/requesting-code-review': '提交前审查代码：安全扫描、质量把关和自动修复。',
  '/resume': '恢复一个之前命名过的会话。用法：/resume [名称]',
  '/retry': '重试上一条消息（重新发送给智能体）。',
  '/review': '启动一个独立的子智能体，审查刚才讨论的工作（PR、代码、文档）。用法：/review [审查要求]',
  '/rollback': '查看文件系统检查点，不提供恢复功能。用法：/rollback [list | diff <检查点>]',
  '/save': '导出当前对话（只输入 /save 会显示用法）。用法：/save <json|md|html> [文件名] [redact]',
  '/sessions': '浏览并恢复以前的会话。',
  '/simplify-code': '用 4 个智能体并行清理最近的代码改动。',
  '/skills': '搜索、安装、查看或管理技能。',
  '/skin': '设置本应用的外观（浅色、深色或跟随系统），终端皮肤不适用。用法：/skin [light|dark|system]',
  '/snapshot': '创建一份私有的原生备份，不提供恢复和清理功能。用法：/snapshot [create]',
  '/songwriting-and-ai-music': '歌曲创作技巧和 Suno AI 音乐提示词。',
  '/spike': '在正式开发前做一次性实验，验证想法是否可行。',
  '/status': '显示会话、模型、token 和上下文信息。',
  '/statusbar': '显示或隐藏上下文和模型状态栏。',
  '/steer': '在下一次工具调用后插入一条消息，不打断当前任务。用法：/steer <提示词>',
  '/stop': '停止此会话的后台进程和子智能体。要停止当前这一轮回复，请使用聊天中的停止按钮。',
  '/subgoal': '为当前目标添加或管理额外的完成条件。用法：/subgoal [文本 | remove N | clear]',
  '/subscription': '查看你的 Nous 订阅方案，并在浏览器中更改。',
  '/suggestions':
      '查看建议的自动化，可接受或忽略。用法：/suggestions [accept|dismiss N | catalog]',
  '/systematic-debugging': '四阶段根因调试：先弄清问题再动手修复。',
  '/teams-meeting-pipeline': '处理 Teams 会议摘要、任务重放和 Microsoft Graph 订阅。',
  '/test-driven-development': '测试驱动开发：严格遵循红-绿-重构，先写测试再写代码。',
  '/timestamps':
      '在消息和 /history 中显示或隐藏 [HH:MM] 时间戳。用法：/timestamps [on|off|status]',
  '/title': '为当前会话设置标题。用法：/title [名称]',
  '/tools': '管理工具：列出、停用或启用。用法：/tools [list|disable|enable] [名称...]',
  '/toolsets': '列出可用的工具集。',
  '/topup': '显示你的 Nous 余额，并在门户网站管理账单。',
  '/undo': '回退最近 N 轮你的发言并重新提问（默认 1 轮）。用法：/undo [N]',
  '/update': '检查 Hermes 原生更新，安装更新通过托管的 Node 发布流程进行。用法：/update [check]',
  '/usage':
      '显示 token 用量和速率限制；reset 可使用一次已攒下的 Codex 限额重置。用法：/usage [reset [--force]]',
  '/verbose': '切换工具进度的显示方式，按 off → new → all → verbose 依次循环。',
  '/version': '显示 Hermes Agent 版本。',
  '/voice': '开关语音模式。用法：/voice [on|off|tts|status]',
  '/wake': '打开本设备的麦克风和 Hermes 原生唤醒词控制，页面会列出缺少的原生依赖。用法：/wake [status]',
  '/weekly-review-planning': '每周复盘：梳理承诺事项和停滞的工作，制定下周计划。',
  '/whoami': '显示你的斜杠命令权限（管理员或普通用户）。',
  '/worktree':
      '查看、列出、创建或清理独立的 Git 工作树。用法：/worktree [new [名称]|list|prune [--dry-run]]',
  '/yolo': '开关 YOLO 模式（跳过所有危险命令的审批）。',
  '/youtube-content': '把 YouTube 视频字幕整理成摘要、推文串或博客文章。',
};

/// Command → why the App does not run it.
const hermesUnavailableZh = <String, String>{
  '/handoff': 'Hermes v0.22.5 的网关会话还不支持转交，App 暂时无法使用。',
  '/indicator': '这是终端提示符里的状态指示；App 有自己的运行状态显示。',
  '/mouse': '这是终端里的鼠标捕获开关；App 直接使用系统的鼠标和触控。',
};
