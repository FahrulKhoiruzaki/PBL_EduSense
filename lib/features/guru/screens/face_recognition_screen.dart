import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/camera.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme.dart';
import '../../../models/app_models.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/avatar.dart';
import '../../../widgets/common_widgets.dart';
import '../../../widgets/custom_button.dart';
import '../../../widgets/custom_card.dart';
import '../providers/face_scan_provider.dart';
import '../widgets/face_oval_overlay.dart';

enum _Phase { permission, starting, ready, scanning, done, fail, duplicate, other, error }

class FaceRecognitionScreen extends ConsumerStatefulWidget {
  const FaceRecognitionScreen({
    super.key,
    required this.startAtPermission,
    this.onManualInput,
  });

  final bool startAtPermission;
  final VoidCallback? onManualInput;

  @override
  ConsumerState<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends ConsumerState<FaceRecognitionScreen>
    with WidgetsBindingObserver {
  late _Phase _phase = widget.startAtPermission ? _Phase.permission : _Phase.starting;
  FaceCamera? _camera;
  var _releasedForPause = false;
  var _studentName = '';
  var _time = '';
  var _message = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.startAtPermission) _openCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _camera = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _camera != null) {
      _releasedForPause = true;
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _releasedForPause) {
      _releasedForPause = false;
      _openCamera(keepPhase: _phase != _Phase.ready && _phase != _Phase.scanning);
    }
  }

  Future<void> _openCamera({bool keepPhase = false}) async {
    if (!keepPhase && _phase != _Phase.starting) {
      setState(() => _phase = _Phase.starting);
    }
    final camera = ref.read(faceCameraFactoryProvider)();
    try {
      await camera.initialize();
    } on CameraUnavailable catch (e) {
      await camera.dispose();
      if (mounted) _fail(e.message);
      return;
    }
    if (!mounted) {
      await camera.dispose();
      return;
    }
    setState(() {
      _camera = camera;
      if (_phase == _Phase.starting) _phase = _Phase.ready;
    });
  }

  void _fail(String message) => setState(() {
        _message = message;
        _phase = _Phase.error;
      });

  Future<void> _scan() async {
    final camera = _camera;
    if (camera == null || _phase != _Phase.ready) return;
    setState(() => _phase = _Phase.scanning);

    final cls = ref.read(selectedClassProvider);
    try {
      final image = await camera.capture();
      final result = await ref.read(faceScannerProvider)(cls, image);
      if (!mounted) return;
      setState(() {
        switch (result) {
          case FaceMatched(:final studentName, :final time):
            _studentName = studentName;
            _time = time;
            _phase = _Phase.done;
          case FaceDuplicate(:final studentName, :final time):
            _studentName = studentName;
            _time = time;
            _phase = _Phase.duplicate;
          case FaceNotRecognized():
            _phase = _Phase.fail;
          case FaceOtherClass():
            _phase = _Phase.other;
        }
      });
    } on CameraUnavailable catch (e) {
      if (mounted) _fail(e.message);
    } on ApiException catch (e) {
      if (mounted) _fail(e.message);
    }
  }

  void _retry() {
    if (_camera == null) {
      _openCamera();
    } else {
      setState(() => _phase = _Phase.ready);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cls = ref.watch(selectedClassProvider);

    return switch (_phase) {
      _Phase.permission => ScreenScaffold(
          title: 'Kelas $cls',
          barIcon: Icons.close,
          barTooltip: 'Tutup',
          children: [_permissionCard(context)],
        ),
      _Phase.starting => const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      _Phase.ready || _Phase.scanning => _stage(context, cls),
      _ => ScreenScaffold(
          title: 'Kelas $cls',
          barIcon: Icons.close,
          barTooltip: 'Tutup',
          children: [_resultCard(context, cls)],
        ),
    };
  }

  Widget _stage(BuildContext context, String cls) {
    final scanning = _phase == _Phase.scanning;
    final camera = _camera;

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          final oval = faceOvalRect(box.biggest);
          const shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

          return Stack(
            fit: StackFit.expand,
            children: [
              if (camera != null) camera.buildPreview(context),
              FaceOvalOverlay(scanning: scanning),
              Positioned(
                top: oval.bottom + 20,
                left: 24,
                right: 24,
                child: Text(
                  scanning ? 'Memindai wajah…' : 'Posisikan wajah siswa di dalam area.',
                  textAlign: TextAlign.center,
                  style: context.styleBold.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    shadows: shadow,
                  ),
                ),
              ),
              if (scanning)
                Positioned.fromRect(
                  rect: oval,
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Tutup',
                          color: Colors.white,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Text(
                          'Kelas $cls',
                          style: context.styleBold.copyWith(color: Colors.white, shadows: shadow),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: CustomButton(
                      label: scanning ? 'Memindai…' : 'Mulai Scan',
                      expanded: true,
                      onDark: true,
                      onPressed: scanning ? null : _scan,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _permissionCard(BuildContext context) {
    return CustomCard(
      margin: const EdgeInsets.only(top: 24, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Izinkan akses kamera', style: context.styleH2),
          const SizedBox(height: 8),
          Text(
            'Wajah hanya dipakai untuk mengenali identitas dan mencatat kehadiran.',
            style: context.styleMuted,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomButton(
                  label: 'Nanti',
                  variant: ButtonVariant.outline,
                  expanded: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomButton(
                  label: 'Izinkan',
                  expanded: true,
                  onPressed: () {
                    ref.read(cameraPermissionProvider.notifier).grant();
                    _openCamera();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context, String cls) {
    if (_phase == _Phase.done) {
      return CustomCard(
        margin: const EdgeInsets.only(top: 16, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Avatar(name: _studentName, size: 72, fontSize: 22)),
            const SizedBox(height: 12),
            Text('Absensi Berhasil dicatat', style: context.styleH2),
            RowList(
              children: [
                for (final (label, value) in [
                  ('Siswa', _studentName),
                  ('Kelas', cls),
                  ('Status', 'Hadir'),
                  ('Waktu', _time),
                ])
                  DetailRow(label: label, value: value),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    label: 'Kembali ke Absensi',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomButton(
                    label: 'Scan Siswa Berikutnya',
                    expanded: true,
                    onPressed: _retry,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final (title, message, retryLabel) = switch (_phase) {
      _Phase.fail => (
          'Wajah Belum Terdaftar',
          'Minta wali kelas mendaftarkan wajah siswa ini, atau pastikan wajah terlihat jelas di dalam area kamera.',
          'Coba Lagi',
        ),
      _Phase.duplicate => (
          '$_studentName sudah tercatat hari ini pukul $_time.',
          'Tidak perlu scan ulang.',
          'Scan Ulang',
        ),
      _Phase.other => (
          'Siswa ini terdaftar di kelas lain.',
          'Pilih kelas yang sesuai atau gunakan input manual.',
          'Scan Ulang',
        ),
      _ => ('Scan tidak dapat diproses', _message, 'Coba Lagi'),
    };

    return CustomCard(
      margin: const EdgeInsets.only(top: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.styleH2),
          const SizedBox(height: 8),
          Text(message, style: context.styleMuted),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.onManualInput != null) ...[
                Expanded(
                  child: CustomButton(
                    label: 'Input Manual',
                    variant: ButtonVariant.outline,
                    expanded: true,
                    onPressed: widget.onManualInput,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: CustomButton(label: retryLabel, expanded: true, onPressed: _retry),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
