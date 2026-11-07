import 'package:flutter/material.dart';

import '../data/client.dart';
import '../data/json.dart';
import '../ui/design.dart';

class ReasoningSlider extends StatefulWidget {
  final NekodotClient client;
  final String botId;
  final bool enabled;
  final int revision;
  final ValueChanged<bool> onSaving;
  const ReasoningSlider({
    super.key,
    required this.client,
    required this.botId,
    required this.enabled,
    required this.revision,
    required this.onSaving,
  });
  @override
  State<ReasoningSlider> createState() => _ReasoningSliderState();
}

class _ReasoningSliderState extends State<ReasoningSlider> {
  final menu = MenuController();
  Json? data;
  String? selected;
  bool saving = false;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ReasoningSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.botId != widget.botId ||
        oldWidget.revision != widget.revision ||
        (!oldWidget.enabled && widget.enabled)) {
      menu.close();
      load();
    }
    if (!widget.enabled) menu.close();
  }

  Future<void> load() async {
    if (!widget.client.online) return;
    final current = ++request;
    try {
      final result = await widget.client.rpc('models.reasoning.get', {
        'botId': widget.botId,
      });
      if (mounted && current == request) {
        setState(() {
          data = result;
          selected = result['effort'] as String?;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && current == request) {
        setState(() {
          data = null;
          error = '$e';
        });
      }
    }
  }

  Future<void> save(String? value) async {
    final before = data;
    if (before == null) return;
    setState(() => saving = true);
    widget.onSaving(true);
    try {
      final result = await widget.client.rpc('models.reasoning.set', {
        'botId': widget.botId,
        'sessionId': before['sessionId'],
        'effort': value,
      });
      if (mounted) {
        setState(() {
          data = result;
          selected = result['effort'] as String?;
        });
        menu.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() => selected = before['effort'] as String?);
        showNotice(context, '$e');
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
        widget.onSaving(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return IconButton(
        tooltip: widget.client.tr('目录获取失败', 'Catalog unavailable'),
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: widget.enabled ? load : null,
      );
    }
    final levels = (data?['levels'] as List?)?.cast<String>() ?? [];
    if (levels.isEmpty) return const SizedBox.shrink();
    final options = <String?>[null, ...levels];
    final at = options.indexOf(selected);
    final disabled = saving || !widget.enabled;
    String label(String? value) => value ?? 'omit';
    if (context.tone.glass) {
      return TextButton(
        key: const ValueKey('reasoning-toggle'),
        onPressed: disabled
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                useSafeArea: true,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (sheet) => SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(sheet).height * .6,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      children: [
                        for (final value in options)
                          ListTile(
                            title: Text(label(value)),
                            trailing: value == selected
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () {
                              Navigator.pop(sheet);
                              save(value);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        child: Text(
          label(selected),
          key: const ValueKey('reasoning-current'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final slider = SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                activeTrackColor: context.tone.ink,
                inactiveTrackColor: context.tone.line,
                thumbColor: context.tone.ink,
                tickMarkShape: const RoundSliderTickMarkShape(
                  tickMarkRadius: 1.4,
                ),
              ),
              child: Slider(
                key: const ValueKey('reasoning-slider'),
                min: 0,
                max: (options.length - 1).toDouble(),
                divisions: options.length - 1,
                value: (at < 0 ? 0 : at).toDouble(),
                semanticFormatterCallback: (v) =>
                    '${widget.client.tr('思考等级', 'Reasoning effort')}: ${label(options[v.round()])}',
                onChanged: disabled
                    ? null
                    : (v) => setState(() => selected = options[v.round()]),
                onChangeEnd: disabled ? null : (v) => save(options[v.round()]),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final value in options)
                TextButton(
                  onPressed: disabled ? null : () => save(value),
                  style: TextButton.styleFrom(
                    minimumSize: Size(48, context.tone.glass ? 48 : 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: value == selected
                        ? context.tone.hover
                        : null,
                  ),
                  child: Text(
                    label(value),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: value == selected
                          ? context.tone.ink
                          : context.tone.ink3,
                      fontWeight: value == selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return MenuAnchor(
      controller: menu,
      consumeOutsideTap: true,
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.fromLTRB(10, 4, 10, 10),
        ),
        backgroundColor: WidgetStatePropertyAll(context.tone.menu),
      ),
      menuChildren: [slider],
      builder: (context, controller, child) => TextButton(
        key: const ValueKey('reasoning-toggle'),
        onPressed: disabled
            ? null
            : () => controller.isOpen ? controller.close() : controller.open(),
        style: TextButton.styleFrom(
          minimumSize: Size(48, context.tone.glass ? 48 : 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(
          label(selected),
          key: const ValueKey('reasoning-current'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
