import 'dart:io' show File, Platform;
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
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

/// One page waiting to be checked: a photo, or a PDF holding a whole document.
class _ScanFile {
  final Uint8List bytes;
  final bool isPdf;

  /// Shown instead of a thumbnail for a PDF, which cannot be previewed here.
  final String? name;

  const _ScanFile(this.bytes, {this.isPdf = false, this.name});
}

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
  final bool initialPassportMode;

  const DocumentScanView({
    super.key,
    this.repository,
    this.initialPassportMode = false,
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
  DocumentLanguage _language = DocumentLanguage.bangla;
  _ScanStage _stage = _ScanStage.idle;
  late _ScanMode _mode =
      (widget.initialPassportMode && _mrzSupported) ? _ScanMode.passport : _ScanMode.document;

  /// Pages gathered for the next check: a multi-page contract is one scan, so
  /// they are held here until the worker taps Check.
  final List<_ScanFile> _files = [];

  /// Why the last save to the vault failed, read by the detail screen.
  String? _saveError;

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

  static const _pageHints = {
    DocumentLanguage.bangla: 'প্রতিটি পাতার ছবি তুলুন বা গ্যালারি/পিডিএফ থেকে বেছে নিন, তারপর “যাচাই করুন” চাপুন।',
    DocumentLanguage.english: 'Photograph each page, or pick photos or a PDF, then tap Check.',
    DocumentLanguage.chinese: '逐页拍照，或从相册/PDF 中选择，然后点击“检查”。',
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
        // A passport is read live from its MRZ, so gathered pages don't apply.
        _files.clear();
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

  /// A photo of one page. It joins the tray rather than being checked straight
  /// away, so a contract that runs over several pages is audited as one document.
  Future<void> _capture() async {
    final controller = _controller;
    if (_isBusy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    if (!_canAddPhotos()) return;
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
          debugPrint('[DocumentScanView] Failed to delete temp capture file: $delErr');
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _stage = _ScanStage.idle;
      _files.add(_ScanFile(bytes));
    });
  }

  Future<void> _pickFromGallery() async {
    if (!_canAddPhotos()) return;
    final room = DocumentAnalysisRepository.maxPages - _files.length;
    List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage(
        limit: room > 1 ? room : null,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('[DocumentScanView] Gallery pick failed: $e');
      _showError('Could not open the gallery.');
      return;
    }
    if (picked.isEmpty) return;

    // pickMultiImage's limit is advisory on some platforms, so trim here too.
    final tooMany = picked.length > room;
    final added = <_ScanFile>[];
    for (final file in picked.take(room)) {
      try {
        added.add(_ScanFile(await file.readAsBytes()));
      } catch (e) {
        debugPrint('[DocumentScanView] Could not read ${file.name}: $e');
      }
    }
    if (!mounted) return;
    if (added.isEmpty) {
      _showError('Could not open those photos.');
      return;
    }
    setState(() => _files.addAll(added));
    if (tooMany) {
      _showError(
        'Only ${DocumentAnalysisRepository.maxPages} pages can be checked at once. '
        'Check these first, then scan the rest.',
      );
    }
  }

  /// A PDF is a whole document, so it is checked on its own.
  Future<void> _pickPdf() async {
    if (_files.isNotEmpty) {
      _showError(
        _files.first.isPdf
            ? 'A PDF is already attached. Remove it to choose another.'
            : 'A PDF is checked on its own. Remove the photos first, or check them.',
      );
      return;
    }
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Choose a PDF document',
      );
    } catch (e) {
      debugPrint('[DocumentScanView] PDF pick failed: $e');
      _showError('Could not open your files.');
      return;
    }
    if (file == null) return;

    // When the picker already knows the size, say so before reading 8 MB+ in.
    final knownLength = file.lengthSync();
    if (knownLength != null && knownLength > DocumentAnalysisRepository.maxImageBytes) {
      _showError('That PDF is too large (over 8 MB). Please choose a smaller file.');
      return;
    }
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      debugPrint('[DocumentScanView] Could not read the PDF: $e');
      _showError('Could not read that PDF.');
      return;
    }
    if (bytes.isEmpty) {
      _showError('That PDF is empty. Please choose another file.');
      return;
    }
    if (bytes.length > DocumentAnalysisRepository.maxImageBytes) {
      _showError('That PDF is too large (over 8 MB). Please choose a smaller file.');
      return;
    }
    if (!mounted) return;
    setState(() => _files.add(_ScanFile(bytes, isPdf: true, name: file!.name)));
  }

  /// Photos and a PDF cannot be mixed in one check.
  bool _canAddPhotos() {
    if (_files.isNotEmpty && _files.first.isPdf) {
      _showError('A PDF is attached. Remove it to photograph pages instead.');
      return false;
    }
    if (_files.length >= DocumentAnalysisRepository.maxPages) {
      _showError(
        'Up to ${DocumentAnalysisRepository.maxPages} pages can be checked at once. '
        'Check these first, then scan the rest.',
      );
      return false;
    }
    return true;
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
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

  /// Contracts and visas: the pages gathered in the tray go to Gemini on the
  /// backend as one document. Nothing is stored yet; the worker decides after
  /// reading the audit.
  Future<void> _checkFiles() async {
    if (_files.isEmpty) return;
    final pages = [for (final file in _files) file.bytes];
    final checked = await _runScan(
      _ScanStage.analyzing,
      (language) => _repository.analyze(files: pages, language: language),
    );
    // Keep the pages when the check failed, so Retry can send them again.
    if (checked && mounted) setState(() => _files.clear());
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
      final saved = await _repository.saveAnalysis(result: result, language: language);
      if (saved.saved) return true;
      _saveError = 'The document vault did not accept this scan. Please try again.';
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
    if (_stage == _ScanStage.analyzing || _stage == _ScanStage.saving) return false;
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
      _showError(e.message, onRetry: e.retryable ? () => _runScan(stage, request) : null);
    } catch (e) {
      debugPrint('[DocumentScanView] Unexpected scan error: $e');
      if (scanId != _scanId) return false;
      _showError('Something went wrong while checking the document. Please try again.');
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
    final hasFiles = !isPassport && _files.isNotEmpty;
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
            style: TextStyle(
              color: AppColors.inkMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
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
          // Once pages are queued the tray and its button speak for themselves,
          // and dropping the hint keeps the preview tall on short screens.
          if (!hasFiles) ...[
            const SizedBox(height: 8),
            Text(
              isPassport
                  ? (_mrzUnclear ? _mrzUnclearHints : _passportHints)[_language]!
                  : _pageHints[_language]!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ],
          if (hasFiles) ...[
            const SizedBox(height: 10),
            _PageTray(
              files: _files,
              onRemove: _isBusy ? null : _removeFile,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _isBusy ? null : _checkFiles,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.royalBlue,
                foregroundColor: AppColors.cloudDancer,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.fact_check_rounded, size: 20),
              label: Text(
                _files.first.isPdf
                    ? 'Check this PDF'
                    : 'Check ${_files.length} page${_files.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _RoundAction(
                icon: Icons.photo_library_rounded,
                label: isPassport ? 'Gallery' : 'Photos',
                onPressed: _isBusy
                    ? null
                    : isPassport
                        ? _pickPassportFromGallery
                        : _pickFromGallery,
              ),
              if (!isPassport)
                _RoundAction(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'PDF',
                  onPressed: _isBusy ? null : _pickPdf,
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

/// The pages queued for the next check, each removable: a blurred page can be
/// dropped and retaken before the document is sent.
class _PageTray extends StatelessWidget {
  final List<_ScanFile> files;
  final void Function(int index)? onRemove;

  const _PageTray({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final file = files[i];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.royalBlue.withValues(alpha: 0.3), width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: file.isPdf
                    ? const Center(
                        child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.royalBlue, size: 28),
                      )
                    // cacheWidth keeps ten full-resolution pages from being
                    // decoded at full size just to show thumbnails.
                    : Image.memory(file.bytes, fit: BoxFit.cover, cacheWidth: 160),
              ),
              Positioned(
                left: 2,
                bottom: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.royalBlue.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    child: Text(
                      file.isPdf ? 'PDF' : '${i + 1}',
                      style: const TextStyle(
                        color: AppColors.cloudDancer,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Semantics(
                  button: true,
                  label: file.isPdf ? 'Remove the PDF' : 'Remove page ${i + 1}',
                  child: GestureDetector(
                    onTap: onRemove == null ? null : () => onRemove!(i),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.crimsonRed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: AppColors.cloudDancer),
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
