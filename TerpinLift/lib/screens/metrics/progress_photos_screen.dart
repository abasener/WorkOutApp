import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:share_plus/share_plus.dart';

import '../../data/models/progress_photo.dart';
import '../../services/app_services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/date_picker_field.dart';

/// Opens the take-photo/backdate flow — a small bottom sheet with a date
/// field (defaults to today, backdatable in case a photo's from an earlier
/// day) and Camera/Library buttons. Shared by the Metrics card's camera icon
/// and this screen's own add button, so both entry points behave identically.
Future<void> showAddProgressPhotoSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddProgressPhotoSheet(),
  );
  AppServices.signalReload();
}

class _AddProgressPhotoSheet extends StatefulWidget {
  const _AddProgressPhotoSheet();

  @override
  State<_AddProgressPhotoSheet> createState() => _AddProgressPhotoSheetState();
}

class _AddProgressPhotoSheetState extends State<_AddProgressPhotoSheet> {
  DateTime _date = DateTime.now();
  bool _saving = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _saving = true);
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final storedPath = await AppServices.progressPhotos.storePickedFile(picked.path);
    await AppServices.progressPhotos.insert(ProgressPhoto(
      date: _date.toIso8601String().substring(0, 10),
      filePath: storedPath,
      takenAt: DateTime.now().toIso8601String(),
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.edge,
          AppSpacing.standard,
          AppSpacing.edge,
          AppSpacing.standard + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Progress Photo', style: AppText.subHeader),
            const SizedBox(height: AppSpacing.standard),
            DatePickerField(date: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: AppSpacing.large),
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.large),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              )
            else ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button)),
                  ),
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take Photo'),
                ),
              ),
              const SizedBox(height: AppSpacing.standard),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textPrimary,
                  ),
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from Library'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The default "quick view" reached from the Metrics card — one stack per
/// day that has photos, laid out as an overlapping pile (each image pinned
/// to the same bottom-left corner, rotated a bit more per photo) so a
/// multi-photo day reads as a pile of prints at a glance, not just a single
/// flat thumbnail. Tapping a stack swipes through just that day
/// (`PhotoSwipeScreen`); the AppBar's carousel icon jumps straight to
/// swiping every photo ever logged, newest first — the original all-in-one
/// view this screen used to be on its own.
class ProgressPhotoAlbumScreen extends StatefulWidget {
  const ProgressPhotoAlbumScreen({super.key});

  @override
  State<ProgressPhotoAlbumScreen> createState() => _ProgressPhotoAlbumScreenState();
}

class _ProgressPhotoAlbumScreenState extends State<ProgressPhotoAlbumScreen> {
  bool _loading = true;
  List<ProgressPhoto> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await AppServices.progressPhotos.getAll();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  Future<void> _add() async {
    await showAddProgressPhotoSheet(context);
    await _load();
  }

  /// Newest first, in both cases — sorted explicitly here rather than
  /// trusting the order [_all]/[dayPhotos] already happen to be in, so
  /// swiping always reads chronologically regardless of how the data got
  /// assembled upstream.
  List<ProgressPhoto> _newestFirst(List<ProgressPhoto> photos) => [...photos]
    ..sort((a, b) => b.date == a.date ? b.takenAt.compareTo(a.takenAt) : b.date.compareTo(a.date));

  Future<void> _openAllSwipe() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PhotoSwipeScreen(title: 'All Photos', photos: _newestFirst(_all)),
      ),
    );
    await _load();
  }

  Future<void> _openDay(List<ProgressPhoto> dayPhotos) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoSwipeScreen(
          title: DateFormat('MMM d, yyyy').format(DateTime.parse(dayPhotos.first.date)),
          photos: _newestFirst(dayPhotos),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final byDate = <String, List<ProgressPhoto>>{};
    for (final p in _all) {
      byDate.putIfAbsent(p.date, () => []).add(p);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a)); // newest first

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Progress Photos'),
        actions: [
          if (_all.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.view_carousel_outlined),
              tooltip: 'Swipe through all photos',
              onPressed: _openAllSwipe,
            ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Add photo',
            onPressed: _add,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : dates.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.edge),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No photos logged yet.', style: AppText.bodyText),
                        const SizedBox(height: AppSpacing.large),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _add,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Add your first photo'),
                        ),
                      ],
                    ),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.edge),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.standard,
                    crossAxisSpacing: AppSpacing.standard,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: dates.length,
                  itemBuilder: (context, i) {
                    final dayPhotos = byDate[dates[i]]!;
                    return _PhotoPileTile(
                      dayPhotos: dayPhotos,
                      onTap: () => _openDay(dayPhotos),
                    );
                  },
                ),
    );
  }
}

/// A day's photos drawn as an overlapping pile — every image anchored at the
/// same bottom-left corner (`Transform.rotate` pivoting on that corner) and
/// rotated a little more per photo, so it reads as "a handful of prints
/// tossed down," not a flat grid. A single-photo day just shows flat
/// (nothing to pile).
class _PhotoPileTile extends StatelessWidget {
  final List<ProgressPhoto> dayPhotos;
  final VoidCallback onTap;

  const _PhotoPileTile({required this.dayPhotos, required this.onTap});

  static const _maxPiled = 3; // more than this just clutters the tile
  static const _rotationStep = 0.09; // radians (~5°) per additional photo

  @override
  Widget build(BuildContext context) {
    // Oldest-to-newest, so if there are more than `_maxPiled` the preview
    // keeps the *most recent* ones (not whichever happened to be first) —
    // and painting last-in-list on top means the newest photo ends up on
    // top of the pile, which is what you'd expect flipping through prints.
    final chronological = [...dayPhotos]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final shown = chronological.length <= _maxPiled
        ? chronological
        : chronological.sublist(chronological.length - _maxPiled);
    final date = DateTime.parse(dayPhotos.first.date);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Leave headroom so a rotated top corner never clips out of
                // the tile — the pile is inset from the full box, not filling it.
                final side = min(constraints.maxWidth, constraints.maxHeight) * 0.78;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < shown.length; i++)
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Transform.rotate(
                          angle: (i - (shown.length - 1) / 2) * _rotationStep,
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            width: side,
                            height: side,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.surfaceRaised, width: 3),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(1, 2)),
                              ],
                            ),
                            child: Image.file(File(shown[i].filePath), fit: BoxFit.cover),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.micro),
          Text(DateFormat('MMM d, yyyy').format(date), style: AppText.smallText),
          if (dayPhotos.length > 1)
            Text('${dayPhotos.length} photos', style: AppText.smallText),
        ],
      ),
    );
  }
}

/// Flip through a fixed list of photos (either one day's worth, or every
/// photo logged) — delete and a download/share action per photo, and a
/// running "i of N" count. "Download" opens the OS share sheet
/// (`share_plus`, already a dependency) rather than writing straight to the
/// device's photo gallery — saving directly to the gallery needs a separate
/// plugin/permission this app doesn't have yet, and the share sheet's own
/// "Save to Photos"/"Save to device" targets cover the same end result on
/// both platforms without adding either.
class PhotoSwipeScreen extends StatefulWidget {
  final String title;
  final List<ProgressPhoto> photos;
  const PhotoSwipeScreen({super.key, required this.title, required this.photos});

  @override
  State<PhotoSwipeScreen> createState() => _PhotoSwipeScreenState();
}

class _PhotoSwipeScreenState extends State<PhotoSwipeScreen> {
  late final List<ProgressPhoto> _photos = [...widget.photos];
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _delete(ProgressPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: Text('Delete this photo?', style: AppText.subHeader),
        content: Text('This cannot be undone.', style: AppText.bodyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.bodyText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppServices.progressPhotos.delete(photo);
    AppServices.signalReload();
    setState(() => _photos.remove(photo));
    if (_photos.isEmpty && mounted) Navigator.pop(context);
  }

  Future<void> _download(ProgressPhoto photo) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(photo.filePath)], subject: 'Progress photo'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: Text(widget.title)),
        body: const SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _photos.length,
        itemBuilder: (context, i) {
          final photo = _photos[i];
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.edge),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMM d, yyyy').format(DateTime.parse(photo.date)),
                      style: AppText.subHeader,
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.download_outlined,
                              color: AppColors.textSecondary),
                          tooltip: 'Save / share',
                          onPressed: () => _download(photo),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.accent),
                          onPressed: () => _delete(photo),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.standard),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: Image.file(File(photo.filePath), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: AppSpacing.standard),
                Text('${i + 1} of ${_photos.length}', style: AppText.smallText),
              ],
            ),
          );
        },
      ),
    );
  }
}
