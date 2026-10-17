/// Languages the backend can translate and summarize a document into.
enum DocumentLanguage {
  bangla('bn', 'বাংলা'),
  english('en', 'English'),
  chinese('zh', '中文');

  final String code;
  final String label;
  const DocumentLanguage(this.code, this.label);

  static DocumentLanguage fromCode(Object? code) => DocumentLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => DocumentLanguage.bangla,
      );
}

enum RiskLevel {
  high,
  medium,
  low,
  unknown;

  static RiskLevel fromString(Object? value) => RiskLevel.values.firstWhere(
        (r) => r.name == value,
        orElse: () => RiskLevel.unknown,
      );
}

enum SigningVerdict {
  safeToSign('SAFE_TO_SIGN'),
  proceedWithCaution('PROCEED_WITH_CAUTION'),
  doNotSign('DO_NOT_SIGN');

  final String apiValue;
  const SigningVerdict(this.apiValue);

  /// Unknown values, including the older "SIGN_WITH_CAUTION" in saved rows, mean caution.
  static SigningVerdict fromString(Object? value) => SigningVerdict.values.firstWhere(
        (v) => v.apiValue == value,
        orElse: () => SigningVerdict.proceedWithCaution,
      );

  static const _labels = {
    SigningVerdict.safeToSign: {
      DocumentLanguage.bangla: 'সই করা নিরাপদ',
      DocumentLanguage.english: 'Safe to sign',
      DocumentLanguage.chinese: '可以签署',
    },
    SigningVerdict.proceedWithCaution: {
      DocumentLanguage.bangla: 'সই করার আগে যাচাই করুন',
      DocumentLanguage.english: 'Check before signing',
      DocumentLanguage.chinese: '签署前请核实',
    },
    SigningVerdict.doNotSign: {
      DocumentLanguage.bangla: 'সই করবেন না',
      DocumentLanguage.english: 'Do not sign',
      DocumentLanguage.chinese: '请勿签署',
    },
  };

  String label(DocumentLanguage language) => _labels[this]![language]!;
}

/// `source_engine` of a passport read on the phone from its MRZ (otherwise "Gemini").
const onDeviceMrzEngine = 'On-device MRZ';

/// What kind of paper was scanned: passports are read on the phone, the rest by Gemini.
enum DocumentCategory {
  passport('PASSPORT'),
  visa('VISA'),
  contract('CONTRACT');

  final String apiValue;
  const DocumentCategory(this.apiValue);

  static DocumentCategory fromString(Object? value) => DocumentCategory.values.firstWhere(
        (c) => c.apiValue == value,
        orElse: () => DocumentCategory.contract,
      );

  bool get isIdentityDocument => this != DocumentCategory.contract;
}

double? _toDouble(Object? value) => value is num ? value.toDouble() : null;
String _toStr(Object? value) => value is String ? value : '';
String? _toNullableStr(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
bool? _toBool(Object? value) => value is bool ? value : null;
Map<String, dynamic> _toMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

/// Holder details read from a passport, BMET smart card or visa.
class IdentityInfo {
  final String documentKind;
  final String? fullName;
  final String? documentNumber;
  final String? nationality;
  final String? dateOfBirth;
  final String? dateOfExpiry;
  final String? sex;
  final String? issuingCountry;
  final String? visaType;
  final String? sponsor;
  final String? occupation;

  const IdentityInfo({
    required this.documentKind,
    this.fullName,
    this.documentNumber,
    this.nationality,
    this.dateOfBirth,
    this.dateOfExpiry,
    this.sex,
    this.issuingCountry,
    this.visaType,
    this.sponsor,
    this.occupation,
  });

  factory IdentityInfo.fromMap(Map<String, dynamic> map) => IdentityInfo(
        documentKind: _toStr(map['document_kind']),
        fullName: _toNullableStr(map['full_name']),
        documentNumber: _toNullableStr(map['document_number']),
        nationality: _toNullableStr(map['nationality']),
        dateOfBirth: _toNullableStr(map['date_of_birth']),
        dateOfExpiry: _toNullableStr(map['date_of_expiry']),
        sex: _toNullableStr(map['sex']),
        issuingCountry: _toNullableStr(map['issuing_country']),
        visaType: _toNullableStr(map['visa_type']),
        sponsor: _toNullableStr(map['sponsor']),
        occupation: _toNullableStr(map['occupation']),
      );

  /// Label/value pairs for the fields that were found, in display order.
  List<(String, String)> get presentFields => [
        if (fullName != null) ('Name', fullName!),
        if (documentNumber != null) ('Document no.', documentNumber!),
        if (nationality != null) ('Nationality', nationality!),
        if (dateOfBirth != null) ('Date of birth', dateOfBirth!),
        if (sex != null) ('Sex', sex!),
        if (issuingCountry != null) ('Issued by', issuingCountry!),
        if (dateOfExpiry != null) ('Expires', dateOfExpiry!),
        if (visaType != null) ('Visa type', visaType!),
        if (sponsor != null) ('Sponsor / employer', sponsor!),
        if (occupation != null) ('Occupation', occupation!),
      ];
}

/// What is visible on the paper; the backend never claims a document is genuine.
class AuthenticityInfo {
  final bool? signaturePresent;
  final bool? stampPresent;

  /// government_seal, consular_stamp, notary_stamp, company_stamp, none or unclear.
  final String stampKind;

  /// Text read from the seal, in its original language.
  final String stampText;
  final String notes;

  const AuthenticityInfo({
    this.signaturePresent,
    this.stampPresent,
    this.stampKind = 'unclear',
    this.stampText = '',
    this.notes = '',
  });

  factory AuthenticityInfo.fromMap(Map<String, dynamic> map) => AuthenticityInfo(
        signaturePresent: _toBool(map['signature_present']),
        stampPresent: _toBool(map['stamp_present']),
        stampKind: _toNullableStr(map['stamp_kind']) ?? 'unclear',
        stampText: _toStr(map['stamp_text']),
        notes: _toStr(map['notes']),
      );

  static const _stampKindLabels = {
    'government_seal': 'Government seal',
    'consular_stamp': 'Embassy / consulate stamp',
    'notary_stamp': 'Notary stamp',
    'company_stamp': 'Company stamp',
  };

  String? get stampKindLabel => _stampKindLabels[stampKind];
}

/// Passport fields read on the phone from the machine-readable zone (MRZ)
/// by `passport_scanner`, after its check digits validated.
class PassportMrz {
  final String documentNumber;
  final String givenNames;
  final String surnames;
  final String nationalityCountryCode;
  final String issuingCountryCode;
  final DateTime expiryDate;

  const PassportMrz({
    required this.documentNumber,
    required this.givenNames,
    required this.surnames,
    required this.nationalityCountryCode,
    required this.issuingCountryCode,
    required this.expiryDate,
  });

  Map<String, dynamic> toJson() {
    String two(int n) => n.toString().padLeft(2, '0');
    return {
      'document_number': documentNumber,
      'given_names': givenNames,
      'surnames': surnames,
      'nationality_country_code': nationalityCountryCode,
      'issuing_country_code': issuingCountryCode,
      'expiry_date': '${expiryDate.year}-${two(expiryDate.month)}-${two(expiryDate.day)}',
    };
  }
}

class SalaryInfo {
  final double? amount;
  final String? currency;
  final String period;
  final double? monthlySarEquivalent;
  final RiskLevel risk;
  final String explanation;

  const SalaryInfo({
    required this.amount,
    required this.currency,
    required this.period,
    required this.monthlySarEquivalent,
    required this.risk,
    required this.explanation,
  });

  factory SalaryInfo.fromMap(Map<String, dynamic> map) => SalaryInfo(
        amount: _toDouble(map['amount']),
        currency: map['currency'] as String?,
        period: _toStr(map['period']),
        monthlySarEquivalent: _toDouble(map['monthly_sar_equivalent']),
        risk: RiskLevel.fromString(map['risk']),
        explanation: _toStr(map['explanation']),
      );
}

class FeeItem {
  final String description;
  final double? amount;
  final String? currency;
  final String paidBy;

  const FeeItem({
    required this.description,
    required this.amount,
    required this.currency,
    required this.paidBy,
  });

  factory FeeItem.fromMap(Map<String, dynamic> map) => FeeItem(
        description: _toStr(map['description']),
        amount: _toDouble(map['amount']),
        currency: map['currency'] as String?,
        paidBy: _toStr(map['paid_by']),
      );
}

class TipShoiFinding {
  final String type;
  final String location;
  final String explanation;

  const TipShoiFinding({
    required this.type,
    required this.location,
    required this.explanation,
  });

  factory TipShoiFinding.fromMap(Map<String, dynamic> map) => TipShoiFinding(
        type: _toStr(map['type']),
        location: _toStr(map['location']),
        explanation: _toStr(map['explanation']),
      );
}

/// One paragraph/clause of the document next to its translation.
class TranslationSegment {
  /// Marker the backend uses for blank lines and empty fields in the original.
  static const blankMarker = '[BLANK]';

  final String original;
  final String translated;

  const TranslationSegment({required this.original, required this.translated});

  bool get isBlank => original.trim() == blankMarker;

  factory TranslationSegment.fromMap(Map<String, dynamic> map) => TranslationSegment(
        original: _toStr(map['original']),
        translated: _toStr(map['translated']),
      );
}

/// The audit returned by `POST /api/documents/analyze`. Also parses rows of
/// `public.saved_documents`, whose columns use the same names.
class DocumentAnalysis {
  final DocumentCategory category;

  /// Human-readable title in the chosen language, e.g. "চাকরির চুক্তিপত্র".
  final String? documentType;

  /// The engine that read the document: Mindee, Base64.ai, Google Cloud Vision or Gemini.
  final String? sourceEngine;
  final IdentityInfo identity;
  final AuthenticityInfo authenticity;
  final bool isLegible;
  final SalaryInfo salary;
  final List<FeeItem> fees;
  final RiskLevel feesRisk;
  final String feesExplanation;
  final String durationText;
  final String cancellationText;
  final RiskLevel cancellationRisk;
  final String cancellationExplanation;
  final bool tipShoiDetected;
  final List<TipShoiFinding> tipShoiFindings;
  final SigningVerdict verdict;
  final List<String> summary3Lines;
  final List<TranslationSegment> translationSegments;
  final String fullTranslation;

  const DocumentAnalysis({
    this.category = DocumentCategory.contract,
    required this.documentType,
    this.sourceEngine,
    this.identity = const IdentityInfo(documentKind: 'other'),
    this.authenticity = const AuthenticityInfo(),
    required this.isLegible,
    required this.salary,
    required this.fees,
    required this.feesRisk,
    required this.feesExplanation,
    required this.durationText,
    required this.cancellationText,
    required this.cancellationRisk,
    required this.cancellationExplanation,
    required this.tipShoiDetected,
    required this.tipShoiFindings,
    required this.verdict,
    required this.summary3Lines,
    required this.translationSegments,
    required this.fullTranslation,
  });

  factory DocumentAnalysis.fromMap(Map<String, dynamic> map) {
    final fees = _toMap(map['fees']);
    final duration = _toMap(map['duration']);
    final cancellation = _toMap(map['cancellation']);
    return DocumentAnalysis(
      category: DocumentCategory.fromString(map['document_category']),
      documentType: map['document_type'] as String?,
      sourceEngine: _toNullableStr(map['source_engine']),
      identity: IdentityInfo.fromMap(_toMap(map['identity'])),
      authenticity: AuthenticityInfo.fromMap(_toMap(map['authenticity'])),
      isLegible: map['is_legible'] != false,
      salary: SalaryInfo.fromMap(_toMap(map['salary'])),
      fees: (fees['items'] as List<dynamic>? ?? [])
          .map((i) => FeeItem.fromMap(_toMap(i)))
          .toList(),
      feesRisk: RiskLevel.fromString(fees['risk']),
      feesExplanation: _toStr(fees['explanation']),
      durationText: _toStr(duration['text']),
      cancellationText: _toStr(cancellation['text']),
      cancellationRisk: RiskLevel.fromString(cancellation['risk']),
      cancellationExplanation: _toStr(cancellation['explanation']),
      tipShoiDetected: map['tip_shoi_detected'] == true,
      tipShoiFindings: (map['tip_shoi_findings'] as List<dynamic>? ?? [])
          .map((f) => TipShoiFinding.fromMap(_toMap(f)))
          .toList(),
      verdict: SigningVerdict.fromString(map['verdict']),
      summary3Lines: (map['summary_3_lines'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      translationSegments: (map['translation_segments'] as List<dynamic>? ?? [])
          .map((s) => TranslationSegment.fromMap(_toMap(s)))
          .toList(),
      fullTranslation: _toStr(map['full_translation']),
    );
  }
}

/// Response of `POST /api/documents/analyze`.
class DocumentAnalysisResult {
  final DocumentAnalysis analysis;
  final String? documentId;
  final bool saved;

  const DocumentAnalysisResult({
    required this.analysis,
    required this.documentId,
    required this.saved,
  });

  factory DocumentAnalysisResult.fromMap(Map<String, dynamic> map) => DocumentAnalysisResult(
        analysis: DocumentAnalysis.fromMap(_toMap(map['analysis'])),
        documentId: map['document_id'] as String?,
        saved: map['saved'] == true,
      );
}

/// A row of `public.saved_documents`, as shown in the vault.
class SavedDocument {
  final String id;
  final DateTime createdAt;
  final DocumentLanguage language;
  final DocumentAnalysis analysis;

  const SavedDocument({
    required this.id,
    required this.createdAt,
    required this.language,
    required this.analysis,
  });

  factory SavedDocument.fromRow(Map<String, dynamic> row) => SavedDocument(
        id: _toStr(row['id']),
        createdAt: DateTime.tryParse(_toStr(row['created_at']))?.toLocal() ?? DateTime.now(),
        language: DocumentLanguage.fromCode(row['language']),
        analysis: DocumentAnalysis.fromMap(row),
      );
}
