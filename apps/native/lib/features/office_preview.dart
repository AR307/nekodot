import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quds_office_editor/quds_office_editor.dart' as office;

import '../ui/design.dart';

enum OfficeFormat { word, sheet, slides }

// A preview must preserve Excel's saved results, including functions that the
// embedded engine cannot calculate. Parsing remains off the UI isolate.
office.SmlWorkbook _openWorkbook(Uint8List bytes) =>
    office.SheetDeserializer().read(office.OfficeRepair.open(bytes));

OfficeFormat? officeFormat(String name, String mime) {
  final extension = name.split('.').last.toLowerCase();
  return switch (extension) {
    'docx' => OfficeFormat.word,
    'xlsx' => OfficeFormat.sheet,
    'pptx' => OfficeFormat.slides,
    _ => switch (mime.split(';').first.trim().toLowerCase()) {
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        OfficeFormat.word,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        OfficeFormat.sheet,
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        OfficeFormat.slides,
      _ => null,
    },
  };
}

/// Local, read-only Office surfaces. Original bytes remain the download/share
/// source; previewing never saves an altered document or calls a cloud service.
class OfficePreview extends StatefulWidget {
  final Uint8List bytes;
  final OfficeFormat format;
  final String zoomInLabel, zoomOutLabel;
  const OfficePreview({
    super.key,
    required this.bytes,
    required this.format,
    required this.zoomInLabel,
    required this.zoomOutLabel,
  });

  @override
  State<OfficePreview> createState() => _OfficePreviewState();
}

class _OfficePreviewState extends State<OfficePreview> {
  office.OfficeController? controller;
  late final ready = load();
  bool fit = true;

  Future<void> load() async {
    await office.OfficeHostFonts.ensureRegistered();
    const config = office.OfficeSurfaceConfig(
      mode: office.OfficeInteractionMode.viewing,
      showRulers: false,
      showFormulaBar: false,
      showSlideHandles: false,
      enableUndo: false,
      interactiveRulers: false,
    );
    final opened = switch (widget.format) {
      OfficeFormat.word => office.WordEditorController(config: config),
      OfficeFormat.sheet => office.SheetEditorController(config: config),
      OfficeFormat.slides => office.SlideEditorController(config: config),
    };
    try {
      switch (opened) {
        case office.WordEditorController c:
          await c.loadBytesAsync(widget.bytes);
        case office.SheetEditorController c:
          c.workbook = await compute(_openWorkbook, widget.bytes);
        case office.SlideEditorController c:
          await c.loadBytesAsync(widget.bytes);
      }
    } catch (_) {
      opened.dispose();
      rethrow;
    }
    if (mounted) {
      controller = opened;
    } else {
      opened.dispose();
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void zoom(double factor) {
    final c = controller!;
    fit = false;
    c.viewport.setScale(c.viewport.scale * factor);
    c.refresh();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: ErrorNotice('${snapshot.error}'));
      }
      final c = controller;
      if (c == null) return const Center(child: ShiningText());
      return ListenableBuilder(
        listenable: c,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            if (fit && c is office.WordEditorController) {
              final pages = c.documentLaidOut.pages;
              if (pages.isNotEmpty) {
                // The read-only Word canvas uses 16px gutters, a 14px scrollbar
                // and a 96/72 point-to-pixel conversion.
                c.viewport.setScale(
                  (constraints.maxWidth - 46) / (pages.first.width * 96 / 72),
                );
              }
            }
            final config = c.config.copyWith(
              theme: office.OfficeTheme.light.copyWith(
                canvasBackground: context.tone.bubble,
                chromeFill: context.tone.surface,
                chromeText: context.tone.ink2,
              ),
            );
            return Column(
              children: [
                Material(
                  color: context.tone.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        if (c is office.SlideEditorController) ...[
                          IconButton(
                            key: const ValueKey('office-previous-slide'),
                            tooltip: MaterialLocalizations.of(context)
                                .previousPageTooltip,
                            onPressed: c.activeSlideIndex > 0
                                ? () => c.setActiveSlide(c.activeSlideIndex - 1)
                                : null,
                            icon: const Icon(Icons.chevron_left, size: 18),
                          ),
                          Text(
                            '${c.activeSlideIndex + 1} / ${c.presentation.slides.length}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: context.tone.ink2,
                                ),
                          ),
                          IconButton(
                            key: const ValueKey('office-next-slide'),
                            tooltip: MaterialLocalizations.of(context)
                                .nextPageTooltip,
                            onPressed:
                                c.activeSlideIndex + 1 <
                                    c.presentation.slides.length
                                ? () => c.setActiveSlide(c.activeSlideIndex + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right, size: 18),
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('office-zoom-out'),
                          tooltip: widget.zoomOutLabel,
                          onPressed: () => zoom(1 / 1.2),
                          icon: const Icon(Icons.remove, size: 18),
                        ),
                        Text(
                          '${(c.viewport.scale * 100).round()}%',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: context.tone.ink2,
                              ),
                        ),
                        IconButton(
                          key: const ValueKey('office-zoom-in'),
                          tooltip: widget.zoomInLabel,
                          onPressed: () => zoom(1.2),
                          icon: const Icon(Icons.add, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: switch (c) {
                    office.WordEditorController() => office.QudsWordEditor(
                      key: const ValueKey('office-word'),
                      controller: c,
                      config: config,
                    ),
                    office.SheetEditorController() => office.QudsSheetEditor(
                      key: const ValueKey('office-sheet'),
                      controller: c,
                      config: config,
                    ),
                    office.SlideEditorController() => office.QudsSlideEditor(
                      key: const ValueKey('office-slides'),
                      controller: c,
                      config: config,
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
                if (c is office.SheetEditorController)
                  Material(
                    color: context.tone.surface,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Segment<int>(
                        value: c.activeSheetIndex,
                        options: {
                          for (var i = 0; i < c.workbook.sheets.length; i++)
                            i: Text(
                              c.workbook.sheets[i].name,
                              key: ValueKey('office-sheet-$i'),
                            ),
                        },
                        onChanged: c.setActiveSheet,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}
