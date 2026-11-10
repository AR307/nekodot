import '../data/chat_models.dart';

import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
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
String? _said(ChatMessage m) {
  if (!_canContainProgress(m)) return null;
  final words = '${m.content['text'] ?? ''}'
      .split('\n')
      .where(_progressLine)
      .lastOrNull
      ?.trim()
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'[。.：:…!！]+$'), '')
      .trim();
  return words == null || words.isEmpty ? null : words;
}

bool _canContainProgress(ChatMessage message) =>
    message.kind == 'commentary' ||
    (message.kind == 'text' && message.status == 'streaming');

bool _progressLine(String line) {
  final words = line.trim().replaceAll(RegExp(r'^[*_`#>]+\s*'), '');
  return words.isNotEmpty &&
      words.length <= 180 &&
      RegExp(
        r'^(正在|(?:Reading|Checking|Opening|Searching|Writing|Running|Loading|Preparing|Reviewing|Thinking|Browsing|Updating|Analyzing|Analysing|Organizing|Watching)\b)',
        caseSensitive: false,
      ).hasMatch(words);
}

/// Keep an acknowledgement even when Hermes streams it beside a progress line.
String visibleMessageText(ChatMessage message) {
  final text = '${message.content['text'] ?? ''}';
  if (!_canContainProgress(message)) return text;
  return text
      .split('\n')
      .where((line) => !_progressLine(line))
      .join('\n')
      .trim();
}

bool isProgressMessage(ChatMessage message) =>
    _said(message) != null && visibleMessageText(message).isEmpty;

/// The command frame used by approval cards.
class StepFrame extends StatelessWidget {
  final Widget child;
  const StepFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return Material(
      color: tone.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tone.line, width: .5),
      ),
      child: child,
    );
  }
}

/// One line in a step frame: a mark, the words, and what sits at the end.
class StepLine extends StatelessWidget {
  final Widget leading;

  /// Facts about the step, shown side by side.
  final List<String> label;
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
      constraints: BoxConstraints(minHeight: context.tone.glass ? 48 : 32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 16, child: Center(child: leading)),
            const SizedBox(width: 8),
            Expanded(
              child: MetaText(label, maxLines: maxLines, style: style),
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
  final ChatMessage message;
  final bool initiallyOpen;
  const StepRow({
    super.key,
    required this.client,
    required this.message,
    this.initiallyOpen = false,
  });
  @override
  State<StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<StepRow> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final m = widget.message, body = object(m.content);
    final running = m.status == 'streaming',
        failed = m.status == 'failed' || body['error'] == true;
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
          label: [stepLabel(widget.client, body)],
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
            decoration: ShapeDecoration(
              color: tone.bubble,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: SelectableText(detail, style: mono),
          ),
      ],
    );
  }
}
