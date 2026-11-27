import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/gol_engine.dart';
import '../engine/gol_share_link.dart';
import '../engine/rle_codec.dart';
import 'app_toast.dart';

String _trOr(GolEngine engine, String key, String fallback) {
  final String value = engine.tr(key);
  if (value.isEmpty || value == key || value.startsWith('!')) {
    return fallback;
  }
  return value;
}

/// Shows a Material 3 modal bottom sheet for sharing the current board or a
/// specific set of [cellsOverride] as a QR code, `gol.puzzak.page` link,
/// custom pattern, or RLE snippet.
Future<void> showShareGolSheet(
  BuildContext context,
  GolEngine engine, {
  List<(int, int)>? cellsOverride,
  String? initialName,
  VoidCallback? onStartCrop,
}) async {
  final List<(int, int)> cells;
  if (cellsOverride != null) {
    cells = cellsOverride;
  } else {
    final ({int minX, int minY, int maxX, int maxY})? box =
        engine.grid.boundingBox();
    if (box == null) {
      showAppToast(
        context,
        _trOr(
          engine,
          'empty_board_share',
          'Board is empty — draw something to share',
        ),
      );
      return;
    }
    final List<(int, int)> extracted = engine.grid.extractRegion(
      box.minX,
      box.minY,
      box.maxX,
      box.maxY,
      maxCells: GolShareLink.maxShareCells + 1,
    );
    cells = extracted.length > GolShareLink.maxShareCells
        ? extracted.sublist(0, GolShareLink.maxShareCells)
        : extracted;
  }

  if (cells.isEmpty) {
    showAppToast(
      context,
      _trOr(
        engine,
        'empty_board_share',
        'Board is empty — draw something to share',
      ),
    );
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return _ShareGolSheetContent(
        engine: engine,
        cells: cells,
        initialName: initialName,
        onStartCrop: onStartCrop,
      );
    },
  );
}

class _ShareGolSheetContent extends StatefulWidget {
  final GolEngine engine;
  final List<(int, int)> cells;
  final String? initialName;
  final VoidCallback? onStartCrop;

  const _ShareGolSheetContent({
    required this.engine,
    required this.cells,
    this.initialName,
    this.onStartCrop,
  });

  @override
  State<_ShareGolSheetContent> createState() => _ShareGolSheetContentState();
}

class _ShareGolSheetContentState extends State<_ShareGolSheetContent> {
  late final TextEditingController _nameController;
  bool _patternSaved = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GolEngine engine = widget.engine;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final String currentName = _nameController.text.trim();
    final GolShareEncodeResult result = GolShareLink.encodeCells(
      widget.cells,
      rule: engine.rule,
      topology: engine.topology,
      palette: engine.palette,
      name: currentName.isNotEmpty ? currentName : null,
    );
    final String shareUrl = result.uri.toString();

    final String title = _trOr(engine, 'share_title', 'Share Pattern');
    final String nameFieldLabel =
        _trOr(engine, 'share_name_label', 'Pattern name (optional)');
    final String copyLinkLabel = _trOr(engine, 'copy_link', 'Copy Link');
    final String shareLinkLabel = _trOr(engine, 'share_link', 'Share Link');
    final String addPatternsLabel =
        _trOr(engine, 'add_to_patterns', 'Add to Patterns');
    final String patternAddedLabel =
        _trOr(engine, 'pattern_added', 'Added to custom patterns');
    final String copyRleLabel = _trOr(engine, 'copy_rle', 'Copy RLE');
    final String cellsLabel =
        _trOr(engine, 'cells_label', 'cells').toLowerCase();
    final String badgeText =
        '${result.width}×${result.height} · ${result.cellCount} $cellsLabel · ${result.payloadBytes}B ${result.encodingMode}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: nameFieldLabel,
                    prefixIcon: const Icon(Icons.edit_rounded, size: 18),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  onChanged: (_) => setState(() {
                    _patternSaved = false;
                  }),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: result.qrReadable
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            QrImageView(
                              data: shareUrl,
                              version: QrVersions.auto,
                              errorCorrectionLevel: QrErrorCorrectLevel.L,
                              size: 196,
                              backgroundColor: Colors.white,
                            ),
                            if (currentName.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 8),
                              Text(
                                currentName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleSmall?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.qr_code_2_rounded,
                                size: 48,
                                color: Colors.black54,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _trOr(
                                  engine,
                                  'qr_too_large_title',
                                  'Pattern too large for QR',
                                ),
                                textAlign: TextAlign.center,
                                style: textTheme.titleSmall?.copyWith(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _trOr(
                                  engine,
                                  'qr_too_large_hint',
                                  'This pattern exceeds the QR code limit. You can still share the link, or crop a smaller area.',
                                ),
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                ),
                              ),
                              if (widget.onStartCrop != null) ...<Widget>[
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 48),
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    widget.onStartCrop!();
                                  },
                                  icon: const Icon(Icons.crop_rounded),
                                  label: Text(
                                    _trOr(
                                      engine,
                                      'crop_smaller',
                                      'Crop Smaller',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  badgeText,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Material(
                  color: scheme.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        IconButton(
                          tooltip: copyLinkLabel,
                          iconSize: 26,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: shareUrl),
                            );
                            if (!context.mounted) return;
                            showAppToast(
                              context,
                              _trOr(
                                engine,
                                'copied_link',
                                'Link copied to clipboard',
                              ),
                            );
                          },
                          icon: const Icon(Icons.link_rounded),
                        ),
                        IconButton(
                          tooltip: shareLinkLabel,
                          iconSize: 26,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            final RenderBox? box =
                                context.findRenderObject() as RenderBox?;
                            final Rect? origin = (box != null && box.hasSize)
                                ? box.localToGlobal(Offset.zero) & box.size
                                : null;
                            final String shareText = currentName.isNotEmpty
                                ? '$currentName · $shareUrl'
                                : shareUrl;
                            try {
                              await Share.share(
                                shareText,
                                sharePositionOrigin: origin,
                              );
                            } catch (_) {
                              await Clipboard.setData(
                                ClipboardData(text: shareUrl),
                              );
                              if (!context.mounted) return;
                              showAppToast(
                                context,
                                _trOr(
                                  engine,
                                  'copied_link',
                                  'Link copied to clipboard',
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.share_rounded),
                        ),
                        IconButton(
                          tooltip: _patternSaved
                              ? patternAddedLabel
                              : addPatternsLabel,
                          iconSize: 26,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () {
                            if (_patternSaved) {
                              showAppToast(context, patternAddedLabel);
                              return;
                            }
                            final String fallbackName =
                                '${result.width}×${result.height} Pattern';
                            engine.saveCustomPattern(
                              name: currentName.isNotEmpty
                                  ? currentName
                                  : fallbackName,
                              cells: widget.cells,
                            );
                            setState(() {
                              _patternSaved = true;
                            });
                            showAppToast(context, patternAddedLabel);
                          },
                          icon: Icon(
                            _patternSaved
                                ? Icons.bookmark_added_rounded
                                : Icons.bookmark_add_outlined,
                            color: _patternSaved ? scheme.primary : null,
                          ),
                        ),
                        IconButton(
                          tooltip: copyRleLabel,
                          iconSize: 26,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () async {
                            final RleEncodeResult encoded = RleCodec.encode(
                              widget.cells,
                              name: currentName.isNotEmpty ? currentName : null,
                              rule: engine.rule.notation,
                            );
                            await Clipboard.setData(
                              ClipboardData(text: encoded.rle),
                            );
                            if (!context.mounted) return;
                            showAppToast(
                              context,
                              _trOr(
                                engine,
                                'copied_rle',
                                'RLE copied to clipboard',
                              ),
                            );
                          },
                          icon: const Icon(Icons.code_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
