import 'package:flutter/material.dart';

import '../data/client.dart';
import '../ui/design.dart';

/// Hermes's own friendly verbs for its built-in tools (`display.verb` in its
/// zh and en locales). Other tools are named as they are.
const _verbs = {
  'web_search': ('搜索网页', 'Searching the web'),
  'web_extract': ('读取网页', 'Reading'),
  'browser_navigate': ('浏览', 'Browsing'),
  'browser_click': ('点击', 'Clicking'),
  'browser_type': ('输入', 'Typing'),
  'read_file': ('读取文件', 'Reading'),
  'write_file': ('写入文件', 'Writing'),
  'patch': ('编辑', 'Editing'),
  'search_files': ('搜索文件', 'Searching files'),
  'terminal': ('运行命令', 'Running'),
  'execute_code': ('运行代码', 'Running code'),
  'image_generate': ('生成图片', 'Generating image'),
  'video_generate': ('生成视频', 'Generating video'),
  'text_to_speech': ('生成语音', 'Generating speech'),
  'vision_analyze': ('查看图片', 'Looking at the image'),
  'session_search': ('搜索历史会话', 'Searching past sessions'),
  'skill_view': ('阅读技能', 'Reading skill'),
  'skills_list': ('列出技能', 'Listing skills'),
  'skill_manage': ('更新技能', 'Updating skill'),
  'delegate_task': ('委派任务', 'Delegating'),
  'cronjob_manage': ('安排定时任务', 'Scheduling'),
  'clarify': ('提问', 'Asking'),
  'memory': ('更新记忆', 'Updating memory'),
  'todo_list': ('更新任务', 'Updating tasks'),
};

/// Verbs that read better alone, as Hermes shows them.
const _alone = {'skills_list', 'session_search'};

/// The first line of a text, trimmed: a step's words in one line.
String firstLine(String text) => text.trim().split('\n').first.trim();

/// One step as Hermes labels it: its verb and the call's main argument.
String stepLabel(NekodotClient c, Json body) {
  final tool = '${body['tool']}';
  final verb = _verbs[tool];
  final name = verb == null ? tool : c.tr(verb.$1, verb.$2);
  final subject = firstLine('${body['context'] ?? ''}');
  return subject.isEmpty || _alone.contains(tool) ? name : '$name $subject';
}

/// A line the Bot wrote, cleaned for one line of status: no markup, no
/// closing punctuation.
String? _said(Json m) {
  if (m['kind'] != 'commentary' && m['kind'] != 'text') return null;
  final words = firstLine('${m['content']?['text'] ?? ''}')
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'[。.：:…!！]+$'), '')
      .trim();
  return words.isEmpty ? null : words;
}

/// What the Bot says it is doing in this turn: the newest line it wrote
/// (one line may announce several steps), else Hermes's own label of the
/// running step. Null before it has done or said anything.
String? botPhrase(NekodotClient c, List<Json> turn) {
  for (final m in turn.reversed) {
    final words = _said(m);
    if (words != null) return words;
  }
  final running = turn
      .where((m) => m['kind'] == 'tool' && m['status'] == 'streaming')
      .lastOrNull;
  if (running == null) return null;
  final tool = '${running['content']['tool']}';
  final label = stepLabel(c, object(running['content']));
  return _verbs.containsKey(tool)
      ? c.tr('正在$label', label)
      : c.tr('正在使用 $tool', 'Using $tool');
}

/// The line above the composer while a Bot works: its name and what it says
/// it is doing, e.g. "Lumi 正在查看推文" or "Lumi is checking the tweets".
String workingLine(NekodotClient c, String name, List<Json> turn) {
  final phrase = botPhrase(c, turn) ?? c.tr('正在思考', 'Thinking');
  if (RegExp(r'^[A-Za-z]').hasMatch(phrase)) {
    final verb = phrase.split(RegExp(r'\s')).first.toLowerCase();
    return verb.endsWith('ing')
        ? '$name is ${phrase[0].toLowerCase()}${phrase.substring(1)}'
        : '$name: $phrase';
  }
  return phrase.startsWith('正在') ? '$name $phrase' : '$name：$phrase';
}

/// Everything a Bot did between your message and its reply, folded under one
/// line: while it works, what it is doing; afterwards, how many steps it took.
class WorkBlock extends StatefulWidget {
  final NekodotClient client;
  final List<Json> steps;
  final bool live;
  const WorkBlock({
    super.key,
    required this.client,
    required this.steps,
    required this.live,
  });
  @override
  State<WorkBlock> createState() => _WorkBlockState();
}

class _WorkBlockState extends State<WorkBlock> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.client, tone = context.tone;
    final text = Theme.of(context).textTheme.bodySmall!;
    final tools = widget.steps.where((m) => m['kind'] == 'tool').toList();
    // An allowed command is the step its tool call runs; it shows only when no call came with it.
    final hasTool = tools.isNotEmpty;
    final failed = tools
        .where((m) => m['status'] == 'failed' || m['content']['error'] == true)
        .length;
    final seconds =
        tools.fold<num>(
          0,
          (sum, m) => sum + ((m['content']['durationMs'] as num?) ?? 0),
        ) /
        1000;
    // What it is doing is said under the box, beside its avatar; the box
    // only counts.
    final status = [
      c.tr('${tools.length} 个步骤', '${tools.length} steps'),
      if (!widget.live) '${seconds.toStringAsFixed(1)}s',
      if (failed > 0) c.tr('$failed 个失败', '$failed failed'),
    ].join(' · ');
    return StepFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepLine(
            key: const ValueKey('work-status'),
            leading: widget.live
                ? const Breathing(size: 8)
                : Icon(
                    failed > 0 ? Icons.error_outline : Icons.check,
                    size: 14,
                    color: failed > 0 ? tone.danger : tone.ink3,
                  ),
            label: status,
            style: text.copyWith(
              color: widget.live ? tone.ink : tone.ink2,
              fontWeight: widget.live ? FontWeight.w600 : null,
            ),
            trailing: Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: tone.ink3,
            ),
            onTap: () => setState(() => open = !open),
          ),
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final step in widget.steps)
                        if (step['kind'] == 'tool')
                          StepRow(
                            key: ValueKey('step-${step['messageId']}'),
                            client: c,
                            message: step,
                          )
                        else if (step['kind'] == 'approval' && !hasTool)
                          ApprovalStep(
                            key: ValueKey('step-${step['messageId']}'),
                            client: c,
                            message: step,
                          )
                        else if ('${step['content']?['text'] ?? ''}'
                            .trim()
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(28, 4, 12, 4),
                            child: Text(
                              '${step['content']['text']}'.trim(),
                              style: text.copyWith(color: tone.ink2),
                            ),
                          ),
                      const SizedBox(height: 4),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The frame every step sits in: the working box and an approval's command.
class StepFrame extends StatelessWidget {
  final Widget child;
  const StepFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Material(
      color: tone.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tone.line),
      ),
      child: child,
    );
  }
}

/// One line in a step frame: a mark, the words, and what sits at the end.
class StepLine extends StatelessWidget {
  final Widget leading;
  final String label;
  final TextStyle style;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int maxLines;
  const StepLine({
    super.key,
    required this.leading,
    required this.label,
    required this.style,
    this.trailing,
    this.onTap,
    this.maxLines = 1,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.tone.glass ? 38 : 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 16, child: Center(child: leading)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    ),
  );
}

/// One tool call: Hermes's label and how long it took; open it for the full
/// call and its result.
class StepRow extends StatefulWidget {
  final NekodotClient client;
  final Json message;
  const StepRow({super.key, required this.client, required this.message});
  @override
  State<StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<StepRow> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final m = widget.message, body = object(m['content']);
    final running = m['status'] == 'streaming',
        failed = m['status'] == 'failed' || body['error'] == true;
    final duration = ((body['durationMs'] as num?) ?? 0) / 1000;
    final detail = [
      '${body['preview'] ?? ''}'.trim(),
      '${body['resultPreview'] ?? ''}'.trim(),
    ].where((text) => text.isNotEmpty).join('\n\n');
    final text = Theme.of(context).textTheme.bodySmall!;
    final mono = TextStyle(
      fontFamily: monoFont,
      fontSize: 12,
      color: tone.ink2,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepLine(
          leading: running
              ? const Breathing(size: 6)
              : StatusDot(size: 6, color: failed ? tone.danger : tone.ink3),
          label: stepLabel(widget.client, body),
          style: text.copyWith(color: tone.ink2),
          trailing: running
              ? null
              : Text(
                  '${duration.toStringAsFixed(1)}s',
                  style: mono.copyWith(color: tone.ink3),
                ),
          onTap: detail.isEmpty ? null : () => setState(() => open = !open),
        ),
        if (open)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tone.bubble,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(detail, style: mono),
          ),
      ],
    );
  }
}

/// A command you allowed: one line in the box, like any other step.
class ApprovalStep extends StatelessWidget {
  final NekodotClient client;
  final Json message;
  const ApprovalStep({super.key, required this.client, required this.message});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final command = firstLine('${object(message['content'])['command'] ?? ''}');
    return StepLine(
      leading: Icon(Icons.check, size: 14, color: tone.ink3),
      label: client.tr('运行命令 $command', 'Running $command'),
      style: TextStyle(fontFamily: monoFont, fontSize: 12, color: tone.ink2),
    );
  }
}
