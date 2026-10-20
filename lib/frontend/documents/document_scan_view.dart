import 'dart:io' show File, Platform;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mrz_parser/mrz_parser.dart';
import 'package:passport_scanner/passport_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/language_controller.dart';
import '../../theme/app_colors.dart';
import 'document_detail_view.dart';
import 'models/document_analysis.dart';
import 'repository/document_analysis_repository.dart';

enum _ScanStage { idle, capturing, analyzing, saving }

/// What the camera placeholder offers when the camera is not running.
enum _CameraFix {
  /// Ask for camera access again (it was refused, but can still be granted).
  retry,

  /// Access is blocked for good; only the system settings can turn it back on.
  openSettings,
}

/// Contracts and visas are photographed and audited by a vision model on the backend;
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

/// Live camera scanner: frame a labor document, read in the app language,
/// and capture it for an AI audit by backend_service.
///
/// Full-bleed: the camera fills the screen and every control floats over it,
/// the way mobile wallet scanners look. Passports are still detected on their
/// own from the MRZ; contracts and visas are captured with the shutter, since
/// the audit needs a sharp full-resolution page rather than a video frame.
class DocumentScanView extends StatefulWidget {
  final DocumentAnalysisRepository? repository;
  final bool initialPassportMode;

  /// What the back arrow (and Android's back gesture) does. The shell passes
  /// "go to the Home tab", because the scanner is a tab there, not a route.
  /// Left null, the scanner pops its own route.
  final VoidCallback? onBack;

  const DocumentScanView({
    super.key,
    this.repository,
    this.initialPassportMode = false,
    this.onBack,
  });

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

  /// The button the camera placeholder shows with [_cameraError], if any.
  _CameraFix? _cameraFix;

  /// The "camera is blocked" sheet is shown once per visit, not on every
  /// retry, and not again when the person comes back from Settings.
  bool _settingsSheetShown = false;

  bool _torchOn = false;

  /// Follows the app-wide language (set in Menu or Profile). The scanner has no
  /// language picker of its own. Chinese is no longer offered, so results come
  /// back in Bangla or English only.
  DocumentLanguage get _language => LanguageController.instance.isBangla
      ? DocumentLanguage.bangla
      : DocumentLanguage.english;
  _ScanStage _stage = _ScanStage.idle;
  late _ScanMode _mode = (widget.initialPassportMode && _mrzSupported)
      ? _ScanMode.passport
      : _ScanMode.document;

  /// The one photo waiting for the next check. Taking or picking another
  /// replaces it; the worker taps Check when it looks right.
  Uint8List? _photo;

  /// Why the last save to the vault failed, read by the detail screen.
  String? _saveError;

  /// Bumped on every scan and on cancel, so a cancelled request's late result is dropped.
  int _scanId = 0;

  /// PassportScannerWidget reports one passport per instance; a new key starts a fresh scan.
  int _passportScannerKey = 0;

  /// The scanner sees MRZ-like lines that don't validate yet (blur, glare, tilt).
  bool _mrzUnclear = false;

  static final bool _isAndroid = !kIsWeb && Platform.isAndroid;
  static final bool _isIOS = !kIsWeb && Platform.isIOS;

  /// ML Kit, which reads the MRZ, only runs on Android and iOS.
  static final bool _mrzSupported = _isAndroid || _isIOS;

  /// A torch is a phone thing: browsers and desktops have no flash to drive.
  static final bool _torchSupported = _isAndroid || _isIOS;

  bool get _isBusy => _stage != _ScanStage.idle;

  bool get _bangla => _language == DocumentLanguage.bangla;
  String _t(String en, String bn) => _bangla ? bn : en;

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
    DocumentLanguage.bangla:
        'পাসপোর্টের ছবির পাতা সমান করে ধরুন, নিচের কোডের দুই লাইন ফ্রেমের ভেতরে রাখুন। নিজে থেকেই স্ক্যান হবে।',
    DocumentLanguage.english:
        'Hold the passport photo page flat with the two code lines at the bottom inside the frame. It scans automatically.',
    DocumentLanguage.chinese: '将护照照片页放平，使底部两行代码位于框内。会自动扫描。',
  };

  static const _mrzUnclearHints = {
    DocumentLanguage.bangla:
        'স্থির রাখুন: কোডের লাইনগুলো এখনো পরিষ্কার পড়া যাচ্ছে না।',
    DocumentLanguage.english: 'Hold still: the code lines are not clear yet.',
    DocumentLanguage.chinese: '请保持稳定：代码行还不够清晰。',
  };

  static const _pageHints = {
    DocumentLanguage.bangla:
        'কাগজের ছবি তুলুন বা একটি ছবি বেছে নিন, তারপর “যাচাই করুন” চাপুন।',
    DocumentLanguage.english:
        'Photograph the document or pick a photo, then tap Check.',
    DocumentLanguage.chinese: '拍摄文件或选择一张照片，然后点击“检查”。',
  };

  // Matches DocumentAnalysisRepository.analyzeTimeout.
  static const _waitHints = {
    DocumentLanguage.bangla: 'এতে ২ মিনিট পর্যন্ত লাগতে পারে',
    DocumentLanguage.english: 'This can take up to 2 minutes',
    DocumentLanguage.chinese: '最多可能需要 2 分钟',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LanguageController.instance.addListener(_onAppLanguageChanged);
    _initCamera();
  }

  // Repaint the hints and progress labels when the app language changes.
  void _onAppLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LanguageController.instance.removeListener(_onAppLanguageChanged);
    _controller?.dispose();
    super.dispose();
  }

  /// Set when the app really went to the background, so coming back is the only
  /// time the camera is restarted automatically.
  bool _wentToBackground = false;

  /// Stops two camera starts from running at once.
  bool _initializing = false;

  // Release the camera while the app is in the background so other apps
  // (and the gallery picker) can use it. In passport mode the scanner manages its own.
  //
  // Only `paused` counts as background. `inactive` also fires for the status
  // bar, the notification shade and permission dialogs, and the camera start
  // itself can trigger it. Releasing and restarting the camera on `inactive`
  // made it loop forever: flickering status bar, leaked camera sessions, and
  // eventually a crash.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wentToBackground = true;
      final controller = _controller;
      if (controller != null) {
        _controller = null;
        _torchOn = false;
        controller.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed && _wentToBackground) {
      _wentToBackground = false;
      if (_controller == null && _mode == _ScanMode.document) {
        _initCamera();
      }
    }
  }

  /// Only one plugin can hold the camera: release ours before the passport
  /// scanner opens its own, and take it back afterwards.
  Future<void> _setMode(_ScanMode mode) async {
    if (mode == _mode) return;
    if (mode == _ScanMode.passport) {
      final controller = _controller;
      setState(() {
        _controller = null;
        _torchOn = false;
      });
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _mode = _ScanMode.passport;
        _mrzUnclear = false;
        _passportScannerKey++;
        // A passport is read live from its MRZ, so a waiting photo doesn't apply.
        _photo = null;
      });
    } else {
      setState(() => _mode = _ScanMode.document);
      await _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      await _startCamera();
    } finally {
      _initializing = false;
    }
  }

  /// Asks for the camera before starting it. True when the camera may start.
  ///
  /// Android only. On iOS, permission_handler can only ask once its Podfile
  /// enables PERMISSION_CAMERA, and this project has no Podfile until it is
  /// first built on a Mac; asking without it would report "denied" forever.
  /// The camera plugin raises its own system prompt there, and the browser
  /// raises its own on web, so both still ask. Their refusals are handled in
  /// [_startCamera]'s CameraException branch.
  Future<bool> _ensureCameraPermission() async {
    if (!_isAndroid) return true;
    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (e) {
      // Let the camera plugin try anyway; it reports a refusal itself.
      debugPrint('[DocumentScanView] Could not ask for the camera: $e');
      return true;
    }
    if (status.isGranted || status.isLimited) return true;
    if (!mounted) return false;
    _setCameraBlocked(
      permanently: status.isPermanentlyDenied || status.isRestricted,
    );
    return false;
  }

  /// Records a refused camera and, the first time it is refused for good,
  /// explains how to turn it back on.
  void _setCameraBlocked({required bool permanently}) {
    setState(() {
      _cameraError = permanently
          ? _t(
              'Camera access is turned off for Probashi Guard. Turn it on in Settings, or choose a photo below.',
              'Probashi Guard-এর জন্য ক্যামেরা বন্ধ করা আছে। সেটিংস থেকে চালু করুন, অথবা নিচ থেকে ছবি বেছে নিন।',
            )
          : kIsWeb
          ? _t(
              'Allow the camera in your browser (the camera icon in the address bar), then tap Try again.',
              'ব্রাউজারে ক্যামেরা চালু করুন (ঠিকানা বারের ক্যামেরা আইকন), তারপর আবার চেষ্টা করুন চাপুন।',
            )
          : _t(
              'The scanner needs the camera to photograph your document.',
              'কাগজের ছবি তুলতে স্ক্যানারের ক্যামেরা লাগবে।',
            );
      _cameraFix = permanently ? _CameraFix.openSettings : _CameraFix.retry;
    });
    if (permanently) _showCameraSettingsSheet();
  }

  Future<void> _showCameraSettingsSheet() async {
    if (_settingsSheetShown || !mounted) return;
    _settingsSheetShown = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cloudDancer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        // A sheet is capped at about half the screen, which a landscape phone
        // or large system text outgrows, so it scrolls rather than overflow.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.royalBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.no_photography_rounded,
                  color: AppColors.royalBlue,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _t('Camera access is off', 'ক্যামেরা বন্ধ আছে'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'To scan a document, allow Camera for Probashi Guard in Settings. You can still choose a photo without it.',
                  'কাগজ স্ক্যান করতে সেটিংসে Probashi Guard-এর জন্য ক্যামেরা চালু করুন। ক্যামেরা ছাড়াও একটি ছবি বেছে নিতে পারবেন।',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _openSettings();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.royalBlue,
                    foregroundColor: AppColors.cloudDancer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.settings_rounded, size: 20),
                  label: Text(
                    _t('Open Settings', 'সেটিংস খুলুন'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.inkMuted,
                ),
                child: Text(_t('Not now', 'এখন না')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Settings opens outside the app, which pauses it; coming back resumes it,
  /// and [didChangeAppLifecycleState] restarts the camera if access is now on.
  Future<void> _openSettings() async {
    try {
      final opened = await openAppSettings();
      if (!opened) {
        _showError(
          _t(
            'Could not open Settings. Turn on the camera for Probashi Guard there yourself.',
            'সেটিংস খোলা যায়নি। নিজে সেখানে গিয়ে Probashi Guard-এর ক্যামেরা চালু করুন।',
          ),
        );
      }
    } catch (e) {
      debugPrint('[DocumentScanView] Could not open settings: $e');
    }
  }

  Future<void> _retryCamera() async {
    setState(() {
      _cameraError = null;
      _cameraFix = null;
    });
    await _initCamera();
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isBusy) {
      return;
    }
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (e) {
      debugPrint('[DocumentScanView] Torch failed: $e');
      _showError(
        _t('This camera has no flashlight.', 'এই ক্যামেরায় ফ্ল্যাশলাইট নেই।'),
      );
    }
  }

  void _goBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _startCamera() async {
    try {
      if (!await _ensureCameraPermission()) return;
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError =
                'No camera found. Choose a photo from the gallery instead.';
            _cameraFix = null;
          });
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
        _cameraFix = null;
        _torchOn = false;
      });
    } on CameraException catch (e) {
      debugPrint('[DocumentScanView] Camera error: ${e.code} ${e.description}');
      if (!mounted) return;
      if (e.code.startsWith('CameraAccess')) {
        // iOS never shows its prompt twice, so any refusal there is for good
        // and only Settings can undo it. A browser can be asked again.
        _setCameraBlocked(permanently: _isIOS || e.code.contains('Restricted'));
        return;
      }
      setState(() {
        _cameraError =
            'Could not start the camera. Choose a photo from the gallery instead.';
        _cameraFix = _CameraFix.retry;
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
        _cameraFix = null;
      });
    }
  }

  /// The shutter. With the camera running it takes the photo; without it, the
  /// tap asks for the camera again (or opens Settings when only Settings can
  /// grant it), so the person never has to hunt for a separate retry button.
  void _onShutterTap() {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      _capture();
    } else if (_initializing) {
      return;
    } else if (_cameraFix == _CameraFix.openSettings) {
      _openSettings();
    } else {
      _retryCamera();
    }
  }

  /// A photo of the document. It waits to be checked rather than being sent
  /// straight away, so a blurred shot can be dropped and retaken first.
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
    String? tempPath;
    try {
      final file = await controller.takePicture();
      tempPath = file.path;
      bytes = await file.readAsBytes();
    } catch (e) {
      // Anything here (a CameraException, or a temp file that cannot be read)
      // has to clear the stage: the capturing overlay has no cancel button.
      debugPrint('[DocumentScanView] Capture failed: $e');
      if (mounted) setState(() => _stage = _ScanStage.idle);
      _showError('Could not take the photo. Please try again.');
      return;
    } finally {
      if (tempPath != null) {
        try {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (delErr) {
          debugPrint(
            '[DocumentScanView] Failed to delete temp capture file: $delErr',
          );
        }
      }
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _stage = _ScanStage.idle;
      _photo = bytes;
    });
  }

  /// Exactly one photo: pickImage offers a single choice, so there is nothing
  /// to trim. The system picker (the Photo Picker on Android, the file chooser
  /// in a browser) needs no storage permission, so there is none to ask for.
  Future<void> _pickFromGallery() async {
    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('[DocumentScanView] Gallery pick failed: $e');
      _showError('Could not open the gallery.');
      return;
    }
    if (picked == null) return;

    Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (e) {
      debugPrint('[DocumentScanView] Could not read ${picked.name}: $e');
      _showError('Could not open that photo.');
      return;
    }
    if (!mounted) return;
    if (bytes.isEmpty) {
      _showError('Could not open that photo.');
      return;
    }
    setState(() => _photo = bytes);
  }

  void _removePhoto() {
    setState(() => _photo = null);
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

  /// Contracts and visas: the photo goes to a vision model on the backend. Nothing is
  /// stored yet; the worker decides after reading the audit.
  Future<void> _checkPhoto() async {
    final photo = _photo;
    if (photo == null) return;
    final checked = await _runScan(
      _ScanStage.analyzing,
      (language) => _repository.analyze(files: [photo], language: language),
    );
    // Keep the photo when the check failed, so Retry can send it again.
    if (checked && mounted) setState(() => _photo = null);
  }

  /// Passports: only the fields read on the phone go to the backend.
  Future<void> _savePassport(PassportMrz mrz) async {
    await _runScan(
      _ScanStage.saving,
      (language) => _repository.saveMrzScan(mrz: mrz, language: language),
    );
    if (mounted) setState(() => _passportScannerKey++);
  }

  /// Keeps a result the worker chose to save. Its reason for failing is left in
  /// [_saveError] for the detail screen to show.
  Future<bool> _saveToVault(
    DocumentAnalysisResult result,
    DocumentLanguage language,
  ) async {
    _saveError = null;
    try {
      final saved = await _repository.saveAnalysis(
        result: result,
        language: language,
      );
      if (saved.saved) return true;
      _saveError =
          'The document vault did not accept this scan. Please try again.';
    } on DocumentAnalysisException catch (e) {
      _saveError = e.message;
    } catch (e) {
      debugPrint('[DocumentScanView] Unexpected save error: $e');
      _saveError = 'Could not save this document. Please try again.';
    }
    return false;
  }

  /// Runs one check and opens its result. True when the document was audited
  /// (whatever the worker then chose to do with it).
  Future<bool> _runScan(
    _ScanStage stage,
    Future<DocumentAnalysisResult> Function(DocumentLanguage language) request,
  ) async {
    if (_stage == _ScanStage.analyzing || _stage == _ScanStage.saving) {
      return false;
    }
    final language = _language;
    final scanId = ++_scanId;
    setState(() => _stage = stage);
    try {
      final result = await request(language);
      if (!mounted || scanId != _scanId) return false;
      setState(() => _stage = _ScanStage.idle);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentDetailView(
            analysis: result.analysis,
            language: language,
            saved: result.saved,
            pages: result.pages,
            scannedAt: DateTime.now(),
            onSave: () => _saveToVault(result, language),
            saveError: () => _saveError,
          ),
        ),
      );
      return true;
    } on DocumentAnalysisException catch (e) {
      if (scanId != _scanId) return false;
      _showError(
        e.message,
        onRetry: e.retryable ? () => _runScan(stage, request) : null,
      );
    } catch (e) {
      debugPrint('[DocumentScanView] Unexpected scan error: $e');
      if (scanId != _scanId) return false;
      _showError(
        'Something went wrong while checking the document. Please try again.',
      );
    } finally {
      if (mounted && scanId == _scanId && _stage == stage) {
        setState(() => _stage = _ScanStage.idle);
      }
    }
    return false;
  }

  void _cancelScan() {
    setState(() {
      _scanId++;
      _stage = _ScanStage.idle;
    });
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

  /// How far down the floating top bar reaches, title and mode toggle included.
  double _topBarExtent(EdgeInsets insets) =>
      insets.top + (_mrzSupported ? 128 : 84);

  Widget _buildPreview(CameraController? controller, EdgeInsets insets) {
    if (_mode == _ScanMode.passport) {
      return PassportScannerWidget(
        key: ValueKey(_passportScannerKey),
        // Two identical, check-digit-validated reads before accepting.
        precision: 2,
        // Its flash button sits top-left, under the floating back arrow, and
        // its camera is private to the package, so the torch is not offered
        // here. The MRZ is read on the photo page, which is rarely too dark.
        showFlashButton: false,
        onScanned: (result, imagePath) {
          // The automatic read: a tap of feedback, then straight on to the
          // check. This instance reports once; a new key starts a fresh read.
          HapticFeedback.lightImpact();
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
    if (controller != null && controller.value.isInitialized) {
      return _CoverPreview(controller: controller);
    }
    return _CameraPlaceholder(
      // Keeps the message clear of the floating bars that sit over it.
      padding: EdgeInsets.only(
        top: _topBarExtent(insets),
        bottom: insets.bottom + 196,
      ),
      error: _cameraError,
      fixLabel: switch (_cameraFix) {
        _CameraFix.retry => _t('Try again', 'আবার চেষ্টা করুন'),
        _CameraFix.openSettings => _t('Open Settings', 'সেটিংস খুলুন'),
        null => null,
      },
      onFix: switch (_cameraFix) {
        _CameraFix.retry => _retryCamera,
        _CameraFix.openSettings => _openSettings,
        null => null,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isPassport = _mode == _ScanMode.passport;
    final cameraLive = controller != null && controller.value.isInitialized;
    final hasPhoto = !isPassport && _photo != null;
    final insets = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over the camera.
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        // Android's back gesture does what the arrow does, so it returns to
        // Home instead of closing the app from the Scan tab.
        canPop: widget.onBack == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: ColoredBox(
          color: AppColors.ink,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final window = _viewfinderWindow(
                constraints.biggest,
                insets,
                hasPhoto: hasPhoto,
              );
              // The dock never climbs over the top bar: on a short screen
              // (a phone held sideways) it scrolls, the buttons staying put.
              final dockMaxHeight =
                  constraints.maxHeight - _topBarExtent(insets);
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildPreview(controller, insets),
                  // The passport scanner draws its own scan area.
                  if (!isPassport && cameraLive)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _ViewfinderPainter(window: window),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildTopBar(
                      isPassport: isPassport,
                      cameraLive: cameraLive,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: dockMaxHeight > 0 ? dockMaxHeight : 0,
                      ),
                      child: _buildDock(
                        isPassport: isPassport,
                        hasPhoto: hasPhoto,
                      ),
                    ),
                  ),
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
              );
            },
          ),
        ),
      ),
    );
  }

  /// Where the page should sit: the upper-middle of the screen, between the
  /// floating top bar and the dock, shaped like an A4 page where it fits.
  Rect _viewfinderWindow(
    Size size,
    EdgeInsets insets, {
    required bool hasPhoto,
  }) {
    final top = _topBarExtent(insets);
    // The dock grows by the photo preview and its Check button once one exists.
    final bottomReserve = insets.bottom + (hasPhoto ? 300 : 196);
    final available = size.height - top - bottomReserve;
    var width = size.width * 0.84;
    if (width > 440) width = 440;
    var height = width * 1.32;
    if (height > available) {
      height = available < 140 ? 140 : available;
      width = height / 1.32;
    }
    final left = (size.width - width) / 2;
    final slack = available - height;
    // Hold slightly above centre, where a hand naturally frames a page.
    final y = top + (slack > 0 ? slack * 0.4 : 0);
    return Rect.fromLTWH(left, y, width, height);
  }

  Widget _buildTopBar({required bool isPassport, required bool cameraLive}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.ink.withValues(alpha: 0.6),
            AppColors.ink.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _GlassIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    semanticLabel: _t('Back', 'ফিরে যান'),
                    onPressed: _goBack,
                  ),
                  Expanded(
                    child: Text(
                      isPassport
                          ? _t('Scan Passport', 'পাসপোর্ট স্ক্যান')
                          : _t('Scan Document', 'ডকুমেন্ট স্ক্যান'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.cloudDancer,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        shadows: _textShadow,
                      ),
                    ),
                  ),
                  if (_torchSupported && !isPassport && cameraLive)
                    _GlassIconButton(
                      icon: _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      semanticLabel: _torchOn
                          ? _t(
                              'Turn the flashlight off',
                              'ফ্ল্যাশলাইট বন্ধ করুন',
                            )
                          : _t(
                              'Turn the flashlight on',
                              'ফ্ল্যাশলাইট চালু করুন',
                            ),
                      active: _torchOn,
                      onPressed: _isBusy ? null : _toggleTorch,
                    )
                  else
                    // Keeps the title centred when there is no torch.
                    const SizedBox(width: _GlassIconButton.size),
                ],
              ),
              if (_mrzSupported) ...[
                const SizedBox(height: 12),
                // Shrinks as a whole on a narrow phone or with large system
                // text, so both choices stay whole and side by side.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _ModeToggle(
                    mode: _mode,
                    documentLabel: _t('Contract / Visa', 'চুক্তি / ভিসা'),
                    passportLabel: _t('Passport', 'পাসপোর্ট'),
                    onChanged: _isBusy ? null : _setMode,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDock({required bool isPassport, required bool hasPhoto}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.ink.withValues(alpha: 0.0),
            AppColors.ink.withValues(alpha: 0.78),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        // Scrolls only when the screen is too short for it, anchored at the
        // bottom so the capture row is what stays on screen.
        child: SingleChildScrollView(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Once a photo is waiting, its preview and the Check button speak
              // for themselves, so the hint gives way to them.
              if (!hasPhoto)
                Text(
                  isPassport
                      ? (_mrzUnclear
                            ? _mrzUnclearHints
                            : _passportHints)[_language]!
                      : _pageHints[_language]!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.cloudDancer.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    shadows: _textShadow,
                  ),
                ),
              if (hasPhoto) ...[
                _PhotoPreview(
                  photo: _photo!,
                  onRemove: _isBusy ? null : _removePhoto,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isBusy ? null : _checkPhoto,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.royalBlue,
                      foregroundColor: AppColors.cloudDancer,
                      disabledBackgroundColor: AppColors.royalBlue.withValues(
                        alpha: 0.45,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.fact_check_rounded, size: 20),
                    label: Text(
                      _t('Check document', 'ডকুমেন্ট যাচাই করুন'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              // The buttons are spread evenly across the full width: the same
              // gap before, between and after them. The photo button is
              // Flexible, so a narrow phone or large system text squeezes its
              // label (which shrinks to fit) rather than the row overflowing.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: _DockButton(
                      icon: Icons.photo_library_outlined,
                      label: isPassport ? 'Gallery' : 'Photos',
                      onPressed: _isBusy
                          ? null
                          : isPassport
                          ? _pickPassportFromGallery
                          : _pickFromGallery,
                    ),
                  ),
                  // A passport is read on its own, so it gets no shutter.
                  if (!isPassport)
                    _ShutterButton(
                      label: _t('Scan', 'স্ক্যান'),
                      onPressed: _isBusy ? null : _onShutterTap,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The photo waiting for the next check, removable: a blurred shot can be
/// dropped and retaken before the document is sent.
class _PhotoPreview extends StatelessWidget {
  final Uint8List photo;
  final VoidCallback? onRemove;

  const _PhotoPreview({required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Room above the thumbnail for the remove badge, which overhangs it.
      height: 84,
      child: Align(
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 58,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.cloudDancer.withValues(alpha: 0.75),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              // cacheWidth keeps a full-resolution photo from being decoded
              // at full size just to show a thumbnail.
              child: Image.memory(photo, fit: BoxFit.cover, cacheWidth: 160),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Semantics(
                button: true,
                label: 'Remove the photo',
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.crimsonRed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: AppColors.cloudDancer,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
        // Centred when it fits; scrolls on a phone held sideways with large
        // system text, instead of overflowing.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }
}

/// Keeps white text readable over a bright patch of camera feed.
const List<Shadow> _textShadow = [
  Shadow(color: Color(0x99040303), blurRadius: 8, offset: Offset(0, 1)),
];

/// The camera feed scaled to cover the whole screen without being stretched.
///
/// The preview is laid out at the size [CameraPreview] itself would choose
/// for the current orientation, then a [FittedBox] scales it up until it
/// covers, cropping the overflow rather than squashing the image. The
/// orientation rule mirrors CameraPreview's own, so the box always matches
/// the aspect ratio CameraPreview draws at, on Android, iOS and the web.
class _CoverPreview extends StatelessWidget {
  final CameraController controller;

  const _CoverPreview({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final previewSize = value.previewSize;
        if (previewSize == null) {
          return Center(child: CameraPreview(controller));
        }
        final orientation =
            value.previewPauseOrientation ??
            value.lockedCaptureOrientation ??
            value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        return FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: landscape ? previewSize.width : previewSize.height,
            height: landscape ? previewSize.height : previewSize.width,
            child: CameraPreview(controller),
          ),
        );
      },
    );
  }
}

/// Dims everything except the page window and marks its corners.
class _ViewfinderPainter extends CustomPainter {
  final Rect window;

  const _ViewfinderPainter({required this.window});

  static const double _radius = 22;
  static const double _bracket = 46;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      window,
      const Radius.circular(_radius),
    );

    // The scrim, with the window cut out of it.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      Paint()..color = AppColors.ink.withValues(alpha: 0.46),
    );

    // A hairline round the window, so its edge reads on a dark page too.
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.cloudDancer.withValues(alpha: 0.28),
    );

    // Rounded corner brackets.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.cloudDancer;
    final l = window.left, t = window.top, r = window.right, b = window.bottom;
    const c = _radius;
    const k = _bracket;
    final arc = Rect.fromLTWH(0, 0, c * 2, c * 2);
    canvas
      ..drawPath(
        Path()
          ..moveTo(l, t + k)
          ..lineTo(l, t + c)
          ..arcTo(arc.shift(Offset(l, t)), 3.14159, 1.5708, false)
          ..lineTo(l + k, t),
        bracket,
      )
      ..drawPath(
        Path()
          ..moveTo(r - k, t)
          ..lineTo(r - c, t)
          ..arcTo(arc.shift(Offset(r - c * 2, t)), -1.5708, 1.5708, false)
          ..lineTo(r, t + k),
        bracket,
      )
      ..drawPath(
        Path()
          ..moveTo(r, b - k)
          ..lineTo(r, b - c)
          ..arcTo(arc.shift(Offset(r - c * 2, b - c * 2)), 0, 1.5708, false)
          ..lineTo(r - k, b),
        bracket,
      )
      ..drawPath(
        Path()
          ..moveTo(l + k, b)
          ..lineTo(l + c, b)
          ..arcTo(arc.shift(Offset(l, b - c * 2)), 1.5708, 1.5708, false)
          ..lineTo(l, b - k),
        bracket,
      );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter oldDelegate) =>
      oldDelegate.window != window;
}

class _CameraPlaceholder extends StatelessWidget {
  final String? error;
  final String? fixLabel;
  final VoidCallback? onFix;

  /// Room above and below for the floating top bar and dock.
  final EdgeInsets padding;

  const _CameraPlaceholder({
    required this.error,
    this.fixLabel,
    this.onFix,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cloudDancer),
      );
    }
    // Centred between the bars when it fits; scrolls when a long message or
    // large system text outgrows a short screen.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(36, padding.top, 36, padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.cloudDancer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.no_photography_rounded,
                color: AppColors.cloudDancer,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.cloudDancer,
                fontSize: 14.5,
                height: 1.45,
              ),
            ),
            if (fixLabel != null && onFix != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onFix,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cloudDancer,
                  foregroundColor: AppColors.royalBlue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  fixLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A round, translucent button for the floating top bar.
class _GlassIconButton extends StatelessWidget {
  static const double size = 44;

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Lit, e.g. while the torch is on.
  final bool active;

  const _GlassIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: active
            ? AppColors.cloudDancer
            : AppColors.ink.withValues(alpha: 0.38),
        shape: CircleBorder(
          side: BorderSide(
            color: AppColors.cloudDancer.withValues(alpha: active ? 0 : 0.22),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: 20,
              color: active ? AppColors.royalBlue : AppColors.cloudDancer,
            ),
          ),
        ),
      ),
    );
  }
}

/// Contract / Visa versus Passport, as a translucent pill over the camera.
class _ModeToggle extends StatelessWidget {
  final _ScanMode mode;
  final String documentLabel;
  final String passportLabel;
  final ValueChanged<_ScanMode>? onChanged;

  const _ModeToggle({
    required this.mode,
    required this.documentLabel,
    required this.passportLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget segment(_ScanMode value, IconData icon, String label) {
      final selected = mode == value;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null || selected ? null : () => onChanged!(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.cloudDancer : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.royalBlue : AppColors.cloudDancer,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.royalBlue
                        : AppColors.cloudDancer,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: onChanged == null ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: AppColors.cloudDancer.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(
              _ScanMode.document,
              Icons.description_rounded,
              documentLabel,
            ),
            segment(_ScanMode.passport, Icons.badge_rounded, passportLabel),
          ],
        ),
      ),
    );
  }
}

/// The large round capture button in the middle of the dock.
class _ShutterButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _ShutterButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Capture document',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onPressed,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: enabled ? 1 : 0.45,
              child: Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.cloudDancer, width: 3.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.royalBlue,
                  ),
                  child: Icon(
                    Icons.document_scanner_rounded,
                    color: AppColors.cloudDancer,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // No wider than the shutter, so it cannot widen the dock row.
          SizedBox(width: 74, child: _DockLabel(label)),
        ],
      ),
    );
  }
}

/// A round, elevated dock action with its name underneath.
class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _DockButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      // Lines its circle up with the shutter's, which is taller.
      padding: const EdgeInsets.only(top: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            enabled: enabled,
            label: label,
            excludeSemantics: true,
            child: Material(
              color: AppColors.cloudDancer.withValues(
                alpha: enabled ? 0.96 : 0.5,
              ),
              shape: const CircleBorder(),
              elevation: enabled ? 4 : 0,
              shadowColor: AppColors.ink.withValues(alpha: 0.5),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(icon, color: AppColors.royalBlue, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _DockLabel(label),
        ],
      ),
    );
  }
}

class _DockLabel extends StatelessWidget {
  final String text;

  const _DockLabel(this.text);

  /// One line, shrunk to the width of its slot when it would not fit.
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      text,
      maxLines: 1,
      style: const TextStyle(
        color: AppColors.cloudDancer,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        shadows: _textShadow,
      ),
    ),
  );
}
