import 'dart:io' show File, Platform;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:passport_scanner/passport_scanner.dart';
import '../../theme/app_colors.dart';
import 'document_detail_view.dart';
import 'models/document_analysis.dart';
import 'repository/document_analysis_repository.dart';
import 'saved_documents_portal_view.dart';

enum _ScanStage { idle, capturing, analyzing, saving }

/// Contracts and visas are photographed and audited by Gemini on the backend;
/// passports are read on the phone from their MRZ and only the fields are sent.
enum _ScanMode { document, passport }

PassportMrz _passportMrzFrom(MRZResult result) => PassportMrz(
      documentNumber: result.documentNumber,
      givenNames: result.givenNames,
      surnames: result.surnames,
      nationalityCountryCode: result.nationalityCountryCode,
      issuingCountryCode: result.countryCode,
      expiryDate: result.expiryDate,
    );

/// The scanner keeps a JPEG of the passport page in the temp folder; it is never
/// uploaded, so don't leave it lying around.
void _deletePassportImage(String? path) {
  if (path == null) return;
  File(path).delete().catchError((Object _) => File(path));
}

/// Live camera scanner: frame a labor document, pick the output language,
/// and capture it for an AI audit by backend_service.
class DocumentScanView extends StatefulWidget {
  final DocumentAnalysisRepository? repository;

  const DocumentScanView({super.key, this.repository});

  @override
  State<DocumentScanView> createState() => _DocumentScanViewState();
}

class _DocumentScanViewState extends State<DocumentScanView>
    with WidgetsBindingObserver {
  late final DocumentAnalysisRepository _repository =
      widget.repository ?? DocumentAnalysisRepository();
  final ImagePicker _picker = ImagePicker();

  CameraController? _controller;
  String? _cameraError;
  DocumentLanguage _language = DocumentLanguage.bangla;
  _ScanStage _stage = _ScanStage.idle;
  _ScanMode _mode = _ScanMode.document;

  /// Bumped on every scan and on cancel, so a cancelled request's late result is dropped.
  int _scanId = 0;

  /// PassportScannerWidget reports one passport per instance; a new key starts a fresh scan.
  int _passportScannerKey = 0;

  /// The scanner sees MRZ-like lines that don't validate yet (blur, glare, tilt).
  bool _mrzUnclear = false;

  /// ML Kit, which reads the MRZ, only runs on Android and iOS.
  static final bool _mrzSupported = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isBusy => _stage != _ScanStage.idle;

  static const _stageLabels = {
    _ScanStage.capturing: {
      DocumentLanguage.bangla: 'ছবি তোলা হচ্ছে…',
      DocumentLanguage.english: 'Taking photo...',
      DocumentLanguage.chinese: '正在拍照…',
    },
    _ScanStage.analyzing: {
      DocumentLanguage.bangla: 'কাগজ বিশ্লেষণ করা হচ্ছে…',
      DocumentLanguage.english: 'Analyzing document...',
      DocumentLanguage.chinese: '正在分析文件…',
    },
    _ScanStage.saving: {
      DocumentLanguage.bangla: 'পাসপোর্টের তথ্য যাচাই করা হচ্ছে…',
      DocumentLanguage.english: 'Checking passport details...',
      DocumentLanguage.chinese: '正在核对护照信息…',
    },
  };

  static const _passportHints = {
    DocumentLanguage.bangla: 'পাসপোর্টের ছবির পাতা সমান করে ধরুন, নিচের কোডের দুই লাইন ফ্রেমের ভেতরে রাখুন। নিজে থেকেই স্ক্যান হবে।',
    DocumentLanguage.english:
        'Hold the passport photo page flat with the two code lines at the bottom inside the frame. It scans automatically.',
    DocumentLanguage.chinese: '将护照照片页放平，使底部两行代码位于框内。会自动扫描。',
  };

  static const _mrzUnclearHints = {
    DocumentLanguage.bangla: 'স্থির রাখুন: কোডের লাইনগুলো এখনো পরিষ্কার পড়া যাচ্ছে না।',
    DocumentLanguage.english: 'Hold still: the code lines are not clear yet.',
    DocumentLanguage.chinese: '请保持稳定：代码行还不够清晰。',
  };

  static const _waitHints = {
    DocumentLanguage.bangla: 'এতে ৩০ সেকেন্ড পর্যন্ত লাগতে পারে',
    DocumentLanguage.english: 'This can take up to 30 seconds',
    DocumentLanguage.chinese: '最多可能需要 30 秒',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // Release the camera while the app is in the background so other apps
  // (and the gallery picker) can use it. In passport mode the scanner manages its own.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive && controller != null) {
      _controller = null;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _mode == _ScanMode.document) {
      _initCamera();
    }
  }

  /// Only one plugin can hold the camera: release ours before the passport
  /// scanner opens its own, and take it back afterwards.
  Future<void> _setMode(_ScanMode mode) async {
    if (mode == _mode) return;
    if (mode == _ScanMode.passport) {
      final controller = _controller;
      setState(() => _controller = null);
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _mode = _ScanMode.passport;
        _mrzUnclear = false;
        _passportScannerKey++;
      });
    } else {
      setState(() => _mode = _ScanMode.document);
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(
            () => _cameraError =
                'No camera found. Choose a photo from the gallery instead.',
          );
        }
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // veryHigh (1080p) keeps small contract text readable.
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // Switched to passport mode (or left the screen) while starting up.
      if (!mounted || _mode != _ScanMode.document) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
      });
    } on CameraException catch (e) {
      debugPrint('[DocumentScanView] Camera error: ${e.code} ${e.description}');
      if (!mounted) return;
      setState(() {
        _cameraError = e.code.startsWith('CameraAccess')
            ? 'Camera permission is off. Allow camera access in Settings, or choose a photo from the gallery.'
            : 'Could not start the camera. Choose a photo from the gallery instead.';
      });
    } catch (e) {
      // The plugin can fail in other ways (no camera support on this platform,
      // a missing plugin registration). Without this the placeholder would
      // spin forever instead of telling the user what to do.
      debugPrint('[DocumentScanView] Camera unavailable: $e');
      if (!mounted) return;
      setState(() {
        _cameraError =
            'The camera is not available on this device. Choose a photo from the gallery instead.';
      });
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_isBusy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    // Show feedback before takePicture: it can take a second or two on Android.
    setState(() => _stage = _ScanStage.capturing);
    Uint8List bytes;
    try {
      final file = await controller.takePicture();
      bytes = await file.readAsBytes();
    } on CameraException catch (e) {
      debugPrint(
        '[DocumentScanView] Capture failed: ${e.code} ${e.description}',
      );
      if (mounted) setState(() => _stage = _ScanStage.idle);
      _showError('Could not take the photo. Please try again.');
      return;
    }
    await _analyze(bytes);
  }

  Future<void> _pickFromGallery() async {
    Uint8List bytes;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('[DocumentScanView] Gallery pick failed: $e');
      _showError('Could not open the gallery.');
      return;
    }
    await _analyze(bytes);
  }

  Future<void> _pickPassportFromGallery() async {
    final scan = await scanPassportFromGallery();
    if (scan.isSuccess) {
      _deletePassportImage(scan.imagePath);
      await _savePassport(_passportMrzFrom(scan.result!));
      return;
    }
    final message = switch (scan.failure) {
      PassportScanFailure.noMrzFound =>
        'No passport code found. Choose a clear photo of the passport photo page.',
      PassportScanFailure.invalidMrz =>
        'The passport code could not be read clearly. Try a sharper photo.',
      PassportScanFailure.unreadableImage => 'Could not open that photo.',
      _ => null, // cancelled
    };
    if (message != null) _showError(message);
  }

  /// Contracts and visas: the photo goes to Gemini on the backend.
  Future<void> _analyze(Uint8List bytes) => _runScan(
        _ScanStage.analyzing,
        (language) => _repository.analyze(imageBytes: bytes, language: language),
      );

  /// Passports: only the fields read on the phone go to the backend.
  Future<void> _savePassport(PassportMrz mrz) async {
    await _runScan(
      _ScanStage.saving,
      (language) => _repository.saveMrzScan(mrz: mrz, language: language),
    );
    if (mounted) setState(() => _passportScannerKey++);
  }

  Future<void> _runScan(
    _ScanStage stage,
    Future<DocumentAnalysisResult> Function(DocumentLanguage language) request,
  ) async {
    if (_stage == _ScanStage.analyzing || _stage == _ScanStage.saving) return;
    final language = _language;
    final scanId = ++_scanId;
    setState(() => _stage = stage);
    try {
      final result = await request(language);
      if (!mounted || scanId != _scanId) return;
      setState(() => _stage = _ScanStage.idle);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentDetailView(
            analysis: result.analysis,
            language: language,
            saved: result.saved,
            scannedAt: DateTime.now(),
          ),
        ),
      );
    } on DocumentAnalysisException catch (e) {
      if (scanId != _scanId) return;
      _showError(e.message, onRetry: e.retryable ? () => _runScan(stage, request) : null);
    } catch (e) {
      debugPrint('[DocumentScanView] Unexpected scan error: $e');
      if (scanId != _scanId) return;
      _showError('Something went wrong while checking the document. Please try again.');
    } finally {
      if (mounted && scanId == _scanId && _stage == stage) {
        setState(() => _stage = _ScanStage.idle);
      }
    }
  }

  void _cancelScan() {
    setState(() {
      _scanId++;
      _stage = _ScanStage.idle;
    });
  }

  void _openVault() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedDocumentsPortalView(repository: _repository),
      ),
    );
  }

  void _showError(String message, {VoidCallback? onRetry}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.crimsonRed,
        duration: Duration(seconds: onRetry != null ? 8 : 5),
        action: onRetry == null
            ? null
            : SnackBarAction(
                label: 'Retry',
                textColor: AppColors.cloudDancer,
                onPressed: onRetry,
              ),
      ),
    );
  }

  Widget _buildPreview(CameraController? controller) {
    if (_mode == _ScanMode.passport) {
      return PassportScannerWidget(
        key: ValueKey(_passportScannerKey),
        // Two identical, check-digit-validated reads before accepting.
        precision: 2,
        showFlashButton: true,
        onScanned: (result, imagePath) {
          _deletePassportImage(imagePath);
          _savePassport(_passportMrzFrom(result));
        },
        onNoMrzFound: () {
          if (mounted) setState(() => _mrzUnclear = false);
        },
        onParsingFailed: (_) {
          if (mounted) setState(() => _mrzUnclear = true);
        },
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: AppColors.royalBlue,
          child: controller != null && controller.value.isInitialized
              ? Center(child: CameraPreview(controller))
              : _CameraPlaceholder(error: _cameraError),
        ),
        // Page-framing guide.
        IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.cloudDancer.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isPassport = _mode == _ScanMode.passport;
    final canCapture = !isPassport &&
        controller != null &&
        controller.value.isInitialized &&
        !_isBusy;
    final segmentStyle = SegmentedButton.styleFrom(
      foregroundColor: AppColors.royalBlue,
      selectedForegroundColor: AppColors.cloudDancer,
      selectedBackgroundColor: AppColors.royalBlue,
      side: BorderSide(color: AppColors.royalBlue.withValues(alpha: 0.3)),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Document Scanner',
            style: TextStyle(
              color: AppColors.royalBlue,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Check any contract or paper before you sign or give a thumbprint.',
            style: TextStyle(color: AppColors.royalBlueMuted, fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          if (_mrzSupported) ...[
            SegmentedButton<_ScanMode>(
              segments: const [
                ButtonSegment(
                  value: _ScanMode.document,
                  icon: Icon(Icons.description_rounded),
                  label: Text('Contract / Visa'),
                ),
                ButtonSegment(
                  value: _ScanMode.passport,
                  icon: Icon(Icons.badge_rounded),
                  label: Text('Passport'),
                ),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: _isBusy ? null : (s) => _setMode(s.first),
              style: segmentStyle,
            ),
            const SizedBox(height: 8),
          ],
          SegmentedButton<DocumentLanguage>(
            segments: [
              for (final lang in DocumentLanguage.values)
                ButtonSegment(value: lang, label: Text(lang.label)),
            ],
            selected: {_language},
            showSelectedIcon: false,
            onSelectionChanged: _isBusy
                ? null
                : (s) => setState(() => _language = s.first),
            style: segmentStyle,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreview(controller),
                  if (_isBusy)
                    _ProgressOverlay(
                      label: _stageLabels[_stage]![_language]!,
                      hint: _stage == _ScanStage.analyzing
                          ? _waitHints[_language]!
                          : null,
                      onCancel: _stage == _ScanStage.capturing
                          ? null
                          : _cancelScan,
                    ),
                ],
              ),
            ),
          ),
          if (isPassport) ...[
            const SizedBox(height: 8),
            Text(
              (_mrzUnclear ? _mrzUnclearHints : _passportHints)[_language]!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.royalBlueMuted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundAction(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onPressed: _isBusy
                    ? null
                    : isPassport
                        ? _pickPassportFromGallery
                        : _pickFromGallery,
              ),
              _ShutterButton(onPressed: canCapture ? _capture : null),
              _RoundAction(
                icon: Icons.folder_shared_rounded,
                label: 'Vault',
                onPressed: _isBusy ? null : _openVault,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressOverlay extends StatelessWidget {
  final String label;
  final String? hint;
  final VoidCallback? onCancel;

  const _ProgressOverlay({required this.label, this.hint, this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: ColoredBox(
        color: AppColors.royalBlue.withValues(alpha: 0.78),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.cloudDancer),
            const SizedBox(height: 14),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.cloudDancer,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.cloudDancer.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.cloudDancer,
                  side: BorderSide(
                    color: AppColors.cloudDancer.withValues(alpha: 0.6),
                  ),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  final String? error;

  const _CameraPlaceholder({required this.error});

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cloudDancer),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              color: AppColors.cloudDancer,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.cloudDancer,
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _ShutterButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: 'Capture document',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled
                  ? AppColors.royalBlue
                  : AppColors.royalBlue.withValues(alpha: 0.3),
              width: 3,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? AppColors.royalBlue
                  : AppColors.royalBlue.withValues(alpha: 0.3),
            ),
            child: const Icon(
              Icons.document_scanner_rounded,
              color: AppColors.cloudDancer,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          onPressed: onPressed,
          icon: Icon(icon),
          color: AppColors.royalBlue,
          style: IconButton.styleFrom(
            side: BorderSide(
              color: AppColors.royalBlue.withValues(alpha: 0.3),
              width: 1.2,
            ),
            fixedSize: const Size(52, 52),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.royalBlue,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
