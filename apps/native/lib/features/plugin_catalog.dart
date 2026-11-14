import 'package:flutter/material.dart';

import '../ui/design.dart';

/// Shared directory layout; each source keeps its own search and lifecycle.
class PluginCatalog extends StatelessWidget {
  final ScrollController scroll;
  final Widget search;
  final List<Widget> actions;
  final Widget? filters, notice, empty, footer;
  final bool loading;
  final int count;
  final Widget Function(int index, bool wide) itemBuilder;
  const PluginCatalog({
    super.key,
    required this.scroll,
    required this.search,
    required this.count,
    required this.itemBuilder,
    this.actions = const [],
    this.filters,
    this.notice,
    this.empty,
    this.footer,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          !context.tone.glass &&
          constraints.maxWidth >= 560 &&
          MediaQuery.textScalerOf(context).scale(14) <= 20;
      final columns = wide ? 2 : 1;
      return CustomScrollView(
        controller: scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: search),
                      ...actions,
                    ],
                  ),
                  if (filters != null) ...[
                    const SizedBox(height: 12),
                    filters!,
                  ],
                  ?notice,
                ],
              ),
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (count == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: empty),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: (count / columns).ceil(),
                itemBuilder: (context, row) {
                  final at = row * columns;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: wide
                        ? IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: itemBuilder(at, true)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: at + 1 < count
                                      ? itemBuilder(at + 1, true)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          )
                        : itemBuilder(at, false),
                  );
                },
              ),
            ),
          if (footer != null) SliverToBoxAdapter(child: footer!),
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ),
        ],
      );
    },
  );
}

class PluginTile extends StatelessWidget {
  final Widget icon;
  final String name, description;
  final Widget? status;
  final VoidCallback onTap;
  final bool wide;
  const PluginTile({
    super.key,
    required this.icon,
    required this.name,
    required this.description,
    required this.onTap,
    required this.wide,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final text = Theme.of(context).textTheme;
    return Material(
      color: wide ? tone.sidebar : Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(wide ? 16 : 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 32, height: 32, child: Center(child: icon)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Symbols.chevron_right, size: 18, color: tone.ink3),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontSize: 13, height: 1.5),
                ),
              ],
              if (status != null) ...[const SizedBox(height: 12), status!],
            ],
          ),
        ),
      ),
    );
  }
}
