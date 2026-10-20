import 'package:flutter/widgets.dart';

import 'language_controller.dart';

/// Every piece of text the app shows, in English and Bangla.
///
/// The Bangla follows how people actually speak (চলিত ভাষা), not literary or
/// Sanskritised Bengali, and keeps the words migrant workers already know from
/// their own papers in recognisable form — ভিসা, পাসপোর্ট, আকামা, রেমিট্যান্স,
/// স্মার্ট কার্ড, ফি, মেয়াদ, MRZ. Instructions stay to one or two short lines
/// because they sit next to a large icon.
///
/// English is the fallback by construction: [_p] returns the English string
/// whenever the Bangla one is missing or left empty, so a half-finished
/// translation can never show a blank label.
class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  bool get isBangla => languageCode == LanguageController.banglaCode;

  /// Picks the Bangla string, falling back to English when it is absent.
  String _p(String en, String bn) => isBangla && bn.isNotEmpty ? bn : en;

  /// The active strings for [context]. Falls back to English when no
  /// [AppStringsScope] is above it (e.g. a widget tested in isolation).
  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStringsScope>();
    return scope?.strings ?? const AppStrings(LanguageController.englishCode);
  }

  // ---------------------------------------------------------------------------
  // Common actions
  // ---------------------------------------------------------------------------
  String get cancel => _p('Cancel', 'বাতিল');
  String get close => _p('Close', 'বন্ধ করুন');
  String get done => _p('Done', 'হয়ে গেছে');
  String get retry => _p('Retry', 'আবার চেষ্টা করুন');
  String get tryAgain => _p('Try again', 'আবার চেষ্টা করুন');
  String get save => _p('Save', 'সেভ করুন');
  String get add => _p('Add', 'যোগ করুন');
  String get confirm => _p('Confirm', 'নিশ্চিত করুন');
  String get amount => _p('Amount', 'টাকার পরিমাণ');
  String get language => _p('Language', 'ভাষা');
  String get chooseLanguage => _p('Choose language', 'ভাষা বেছে নিন');

  // ---------------------------------------------------------------------------
  // Navigation & menu
  // ---------------------------------------------------------------------------
  String get navHome => _p('Home', 'হোম');
  String get navPayment => _p('Payment', 'পেমেন্ট');
  String get navScan => _p('Scan', 'স্ক্যান');
  String get navNotice => _p('Notice', 'নোটিশ');

  String get menu => _p('Menu', 'মেনু');
  String get openMenu => _p('Open menu', 'মেনু খুলুন');
  String get menuHome => _p('Home', 'হোম');
  String get menuPayments => _p('Payments', 'পেমেন্ট');
  String get menuFraudChecker => _p('Fraud Checker', 'জালিয়াতি যাচাই');
  String get menuNotices => _p('Notices', 'নোটিশ');
  String get menuComplaint => _p('File a Complaint', 'অভিযোগ করুন');
  String get menuDocumentScanner =>
      _p('Document Scanner', 'ডকুমেন্ট স্ক্যানার');
  String get menuSavedDocuments => _p('Saved Documents', 'সংরক্ষিত ডকুমেন্ট');
  String get menuEmbassy => _p('Embassy & Helplines', 'দূতাবাস ও হেল্পলাইন');
  String get menuHelpSupport => _p('Help & Support', 'সহায়তা ও সাপোর্ট');
  String get menuAbout => _p('About the App', 'অ্যাপ সম্পর্কে');
  String get menuShareApp => _p('Share App', 'অ্যাপ শেয়ার করুন');
  String get menuProfile => _p('Profile', 'প্রোফাইল');

  // ---------------------------------------------------------------------------
  // Prohori, the AI assistant
  // ---------------------------------------------------------------------------
  String get prohori => _p('Prohori', 'প্রহরী');
  String get prohoriSubtitle => _p('AI Assistant', 'এআই সহকারী');

  /// The big greeting over an empty chat; [firstName] is the person's first name.
  String prohoriHi(String firstName) {
    final name = firstName.trim();
    if (name.isEmpty) return _p('HI THERE !', 'হ্যালো !');
    return _p('HI ${name.toUpperCase()} !', 'হ্যালো $name !');
  }

  String get prohoriPrompt => _p(
    'What do you want to chat about today?',
    'আজ আপনি কী নিয়ে কথা বলতে চান?',
  );

  // The most asked questions, offered as one-tap cards on an empty chat. The
  // question is what gets sent, so each is worded the way a worker would ask it.
  String get prohoriRemitTitle => _p('Remittance & Fees', 'রেমিট্যান্স ও ফি');
  String get prohoriRemitAsk => _p(
    'How can I send money without hidden fees?',
    'লুকানো ফি ছাড়া কীভাবে টাকা পাঠাতে পারি?',
  );
  String get prohoriLegalTitle => _p('Legal & Contracts', 'আইন ও চুক্তি');
  String get prohoriLegalAsk => _p(
    'My employer wants a fingerprint on a blank paper.',
    'আমার মালিক সাদা কাগজে আঙুলের ছাপ চাইছে।',
  );
  String get prohoriRightsTitle => _p('Worker Rights', 'শ্রমিকের অধিকার');
  String get prohoriRightsAsk =>
      _p('What is the legal minimum wage?', 'আইনি ন্যূনতম মজুরি কত?');
  String get prohoriInputHint =>
      _p('Ask Prohori a question', 'প্রহরীকে প্রশ্ন করুন');
  String get prohoriSend => _p('Send', 'পাঠান');
  String get prohoriThinking => _p('Prohori is typing', 'প্রহরী লিখছে');
  String get prohoriDisclaimer => _p(
    'General guidance only, not legal advice.',
    'এটি সাধারণ পরামর্শ, আইনি পরামর্শ নয়।',
  );
  String get prohoriUnavailable => _p(
    'Prohori is not available yet. Please try again later.',
    'প্রহরী এখনো চালু হয়নি। কিছুক্ষণ পরে আবার চেষ্টা করুন।',
  );
  String get prohoriUnreachable => _p(
    'Cannot reach Prohori. Check your internet connection and try again.',
    'প্রহরীর সাথে যোগাযোগ করা যাচ্ছে না। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
  );
  String get prohoriTimeout => _p(
    'Prohori is taking too long to answer. Please try again.',
    'প্রহরী উত্তর দিতে দেরি করছে। আবার চেষ্টা করুন।',
  );
  String get prohoriBusy => _p(
    'Prohori is busy right now. Please try again in a minute.',
    'প্রহরী এখন ব্যস্ত আছে। এক মিনিট পরে আবার চেষ্টা করুন।',
  );
  String get prohoriSignIn => _p(
    'Please log in again to talk to Prohori.',
    'প্রহরীর সাথে কথা বলতে আবার লগ ইন করুন।',
  );
  String get prohoriFailed => _p(
    'Prohori could not answer that. Please try again.',
    'প্রহরী এর উত্তর দিতে পারেনি। আবার চেষ্টা করুন।',
  );
  String get badgeNew => _p('New', 'নতুন!');
  String version(String v) => _p('Version: $v', 'ভার্সন: $v');

  String get logOut => _p('Log Out', 'লগ আউট');
  String get logOutQuestion => _p('Log out?', 'লগ আউট করবেন?');
  String get logOutBody => _p(
    'You will need to sign in again to use the app.',
    'অ্যাপ ব্যবহার করতে আপনাকে আবার লগইন করতে হবে।',
  );

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------
  String get searchHint => 'Search services, features... / সেবা খুঁজুন...';
  String get recentSearches => _p('Recent Searches', 'সাম্প্রতিক অনুসন্ধান');
  String get exploreServices => _p('Explore Services', 'সেবা সমূহ');
  String get noServicesFound =>
      _p('No services found', 'কোনো সেবা পাওয়া যায়নি');
  String get clearAll => _p('Clear All', 'সব মুছুন');
  String get tapToSeeBalance =>
      _p('Tap to see balance', 'ব্যালেন্স দেখতে চাপুন');
  String get hideBalance => _p('Hide balance', 'ব্যালেন্স লুকান');
  String get showBalance => _p('Show balance', 'ব্যালেন্স দেখান');
  String balanceShownA11y(String balance) => _p(
    'Balance $balance. Double tap to hide.',
    'ব্যালেন্স $balance। লুকাতে দুইবার চাপুন।',
  );
  String get balanceHiddenA11y => _p(
    'Balance hidden. Double tap to show.',
    'ব্যালেন্স লুকানো আছে। দেখতে দুইবার চাপুন।',
  );

  // ---------------------------------------------------------------------------
  // Home / dashboard
  // ---------------------------------------------------------------------------
  String get welcome => _p('Welcome', 'স্বাগতম');
  String greeting(String name) => _p('Hi, $name', 'হ্যালো, $name');
  String get dashboardSubtitle => _p(
    'Your Overseas Protection Dashboard',
    'বিদেশে আপনার সুরক্ষার ড্যাশবোর্ড',
  );
  String get checklistTitle => _p(
    'Pre-Departure Company & Travel Checklist',
    'যাওয়ার আগে কোম্পানি ও সফরের চেকলিস্ট',
  );
  String get checklistSubtitle => _p(
    'Check your company and documents before you fly',
    'ফ্লাইটের আগে কোম্পানি ও কাগজপত্র যাচাই করে নিন',
  );
  String checklistDone(int done, int total) =>
      _p('$done/$total Done', '$done/$total শেষ');
  String get viewDetails => _p('View Details', 'বিস্তারিত দেখুন');
  String get departureReadiness =>
      _p('Departure Readiness', 'যাওয়ার প্রস্তুতি');
  String get showFewerItems => _p('Show Fewer Items', 'কম দেখান');
  String showAllItems(int total) =>
      _p('Show All $total Checklist Items', 'সব $total টি দেখান');
  String get nextStep => _p('NEXT STEP', 'পরের ধাপ');
  String get markAsDoneHint =>
      _p('Double tap to mark as done', 'শেষ করতে দুইবার চাপুন');
  String get fullyProtected => _p('Fully Protected', 'পুরোপুরি সুরক্ষিত');
  String get partiallyProtected => _p('Partially Protected', 'কিছুটা সুরক্ষিত');
  String get actionNeeded => _p('Action Needed', 'কাজ বাকি আছে');
  String get quickFeatures => _p('Quick Features', 'দরকারি সেবা');
  String get noticeBoard => _p('Notice Board', 'নোটিশ বোর্ড');
  String get allNotices => _p('All Notices', 'সব নোটিশ');
  String get pauseAutoSlide => _p('Pause auto-slide', 'স্লাইড থামান');
  String get resumeAutoSlide => _p('Resume auto-slide', 'স্লাইড চালু করুন');
  String get previousNotice => _p('Previous notice', 'আগের নোটিশ');
  String get nextNotice => _p('Next notice', 'পরের নোটিশ');

  /// The pre-departure checklist, in display order. The widget keeps only the
  /// tick state, so the wording lives here and switches with the language.
  List<ChecklistText> get checklist => [
    ChecklistText(
      _p(
        'Verify Company Commercial Registration (CR/Trade License) is active',
        'কোম্পানির ট্রেড লাইসেন্স / CR চালু আছে কিনা দেখুন',
      ),
      _p(
        'Official host country establishment database status',
        'যে দেশে যাবেন সেখানকার সরকারি তালিকায় যাচাই',
      ),
    ),
    ChecklistText(
      _p(
        'Confirm work visa is authentic on the host country immigration portal',
        'ভিসা আসল কিনা ইমিগ্রেশন পোর্টালে যাচাই করুন',
      ),
      _p(
        'Cross-check visa number directly with ministry records',
        'ভিসা নম্বর মন্ত্রণালয়ের তথ্যের সাথে মিলিয়ে নিন',
      ),
    ),
    ChecklistText(
      _p(
        "Ensure visa type is 'Work/Employment' (NOT Visit or Tourist)",
        'ভিসা অবশ্যই কাজের (Work) হতে হবে — ভিজিট বা টুরিস্ট নয়',
      ),
      _p(
        'Avoid illegal travel on visitor visas without legal protections',
        'ভিজিট ভিসায় গেলে কোনো আইনি সুরক্ষা থাকে না',
      ),
    ),
    ChecklistText(
      _p(
        'Verify BMET Smart Clearance Card via QR code scan',
        'BMET স্মার্ট কার্ড QR কোড স্ক্যান করে যাচাই করুন',
      ),
      _p(
        'Government authorized emigrant clearance registration',
        'সরকার অনুমোদিত ছাড়পত্রের নিবন্ধন',
      ),
    ),
    ChecklistText(
      _p(
        'Cross-check that company name on contract matches the visa',
        'চুক্তির কোম্পানির নাম ভিসার সাথে মিলছে কিনা দেখুন',
      ),
      _p(
        'Guarantees the sponsor matches the real workplace',
        'যাতে কফিল আর আসল কাজের জায়গা একই হয়',
      ),
    ),
    ChecklistText(
      _p(
        'Confirm salary, food allowance, and accommodation terms in writing',
        'বেতন, খাওয়া ও থাকার শর্ত লিখিতভাবে নিশ্চিত করুন',
      ),
      _p(
        'Legally attested employment agreement terms',
        'সত্যায়িত চাকরির চুক্তির শর্ত',
      ),
    ),
    ChecklistText(
      _p(
        'Obtain company representative contact and airport pickup details',
        'কোম্পানির লোকের নম্বর ও বিমানবন্দরে কে নিতে আসবে জেনে নিন',
      ),
      _p(
        'Authorized reception contact point at arrival airport',
        'পৌঁছানোর বিমানবন্দরে অনুমোদিত লোকের তথ্য',
      ),
    ),
    ChecklistText(
      _p(
        'Save embassy helpline and labor dispute contact numbers',
        'দূতাবাসের হেল্পলাইন ও শ্রম সমস্যার নম্বর সেভ রাখুন',
      ),
      _p(
        'Direct hotlines for legal and labor grievance support',
        'আইনি ও শ্রম অভিযোগের সরাসরি নম্বর',
      ),
    ),
  ];

  /// The home notice slider, in display order.
  List<NoticeText> get noticeSlides => [
    NoticeText(fraudAlert, noticeFraudBody),
    NoticeText(embassyAdvisory, noticeEmbassyBody),
    NoticeText(laborWingNotice, noticeLaborBody),
  ];

  // ---------------------------------------------------------------------------
  // Notices
  // ---------------------------------------------------------------------------
  String get officialNotices => _p('Official Notices', 'সরকারি নোটিশ');
  String get latestNews => _p('Latest News', 'সর্বশেষ খবর');
  String get viewCompact => _p('Compact', 'সংক্ষিপ্ত');
  String get viewExpanded => _p('Expanded', 'বিস্তারিত');
  String get noNoticesYet => _p(
    'No notices yet.\nCheck back soon for migration news.',
    'এখনো কোনো নোটিশ নেই।\nপ্রবাস সংক্রান্ত খবরের জন্য পরে দেখুন।',
  );
  String get noticesUnavailable =>
      _p('Could not load notices right now.', 'এখন নোটিশ আনা যাচ্ছে না।');
  String get readFullStory => _p('Read full story', 'পুরো খবর পড়ুন');
  String get couldNotOpenLink => _p(
    'Could not open that link in a browser.',
    'ব্রাউজারে লিংকটি খোলা যায়নি।',
  );
  String get fraudAlert => _p('FRAUD ALERT', 'জালিয়াতির সতর্কতা');
  String get embassyAdvisory => _p('EMBASSY ADVISORY', 'দূতাবাসের নির্দেশনা');
  String get laborWingNotice => _p('LABOR WING NOTICE', 'লেবার উইং নোটিশ');
  String get noticeFraudBody => _p(
    'Fraud Alert: Verify all work permits on the official embassy portal before booking flights.',
    'সতর্কতা: ফ্লাইট বুকিংয়ের আগে দূতাবাসের অফিশিয়াল পোর্টালে ওয়ার্ক পারমিট যাচাই করুন।',
  );
  String get noticeEmbassyBody => _p(
    'Embassy Advisory: Mandatory BMET Smart Card scanning at airport immigration.',
    'দূতাবাসের নির্দেশনা: বিমানবন্দরে ইমিগ্রেশনে BMET স্মার্ট কার্ড স্ক্যান করা বাধ্যতামূলক।',
  );
  String get noticeLaborBody => _p(
    'Labor Wing Notice: Updated minimum wage standards for destination countries.',
    'লেবার উইং নোটিশ: যে দেশে যাবেন সেখানকার সর্বনিম্ন বেতনের নতুন নিয়ম।',
  );
  String get urgentAirportAdvisory => _p(
    'Urgent Airport Clearance Advisory',
    'বিমানবন্দর ছাড়পত্র নিয়ে জরুরি নির্দেশনা',
  );
  String get importantAdvisoryBody => _p(
    'Important Advisory: Verify all job offers and CR numbers before airport departure.',
    'জরুরি নির্দেশনা: বিমানবন্দরে যাওয়ার আগে চাকরির অফার ও CR নম্বর যাচাই করুন।',
  );

  // ---------------------------------------------------------------------------
  // Document scanner
  // ---------------------------------------------------------------------------
  String get documentScanner => _p('Document Scanner', 'ডকুমেন্ট স্ক্যানার');
  String get scannerSubtitle => _p(
    'Check any contract or paper before you sign or give a thumbprint.',
    'সই বা টিপসই দেওয়ার আগে যেকোনো কাগজ যাচাই করে নিন।',
  );
  String get scanContractVisa => _p('Contract / Visa', 'চুক্তি / ভিসা');
  String get scanPassport => _p('Passport', 'পাসপোর্ট');
  String get takePhoto => _p('Photos', 'ছবি');
  String get gallery => _p('Gallery', 'গ্যালারি');
  String get vault => _p('Vault', 'ভল্ট');
  String get checkDocument => _p('Check document', 'ডকুমেন্ট যাচাই করুন');
  String get captureDocument => _p('Capture document', 'কাগজের ছবি তুলুন');
  String get removeThePhoto => _p('Remove the photo', 'ছবিটি সরান');

  String get stageTakingPhoto => _p('Taking photo...', 'ছবি তোলা হচ্ছে…');
  String get stageAnalyzing =>
      _p('Analyzing document...', 'কাগজ বিশ্লেষণ করা হচ্ছে…');
  String get stageCheckingPassport =>
      _p('Checking passport details...', 'পাসপোর্টের তথ্য যাচাই করা হচ্ছে…');
  String get waitHint =>
      _p('This can take up to 2 minutes', 'এতে ২ মিনিট পর্যন্ত লাগতে পারে');
  String get passportHint => _p(
    'Hold the passport photo page flat with the two code lines at the bottom inside the frame. It scans automatically.',
    'পাসপোর্টের ছবির পাতা সমান করে ধরুন, নিচের কোডের দুই লাইন ফ্রেমের ভেতরে রাখুন। নিজে থেকেই স্ক্যান হবে।',
  );
  String get mrzUnclearHint => _p(
    'Hold still: the code lines are not clear yet.',
    'স্থির রাখুন: কোডের লাইনগুলো এখনো পরিষ্কার পড়া যাচ্ছে না।',
  );
  String get pageHint => _p(
    'Photograph the document or pick a photo, then tap Check.',
    'কাগজের ছবি তুলুন বা একটি ছবি বেছে নিন, তারপর “যাচাই করুন” চাপুন।',
  );

  // Scanner problems — short, plain, and always say what to do next.
  String get noCameraFound => _p(
    'No camera found. Choose a photo from the gallery instead.',
    'ক্যামেরা পাওয়া যায়নি। গ্যালারি থেকে ছবি বেছে নিন।',
  );
  String get cameraPermissionOff => _p(
    'Camera permission is off. Allow camera access in Settings, or choose a photo from the gallery.',
    'ক্যামেরার অনুমতি বন্ধ আছে। সেটিংসে অনুমতি দিন, বা গ্যালারি থেকে ছবি বেছে নিন।',
  );
  String get cameraCouldNotStart => _p(
    'Could not start the camera. Choose a photo from the gallery instead.',
    'ক্যামেরা চালু করা যায়নি। গ্যালারি থেকে ছবি বেছে নিন।',
  );
  String get cameraUnavailable => _p(
    'The camera is not available on this device. Choose a photo from the gallery instead.',
    'এই ফোনে ক্যামেরা কাজ করছে না। গ্যালারি থেকে ছবি বেছে নিন।',
  );
  String get captureFailed => _p(
    'Could not take the photo. Please try again.',
    'ছবি তোলা যায়নি। আবার চেষ্টা করুন।',
  );
  String get galleryOpenFailed =>
      _p('Could not open the gallery.', 'গ্যালারি খোলা যায়নি।');
  String get photoOpenFailed =>
      _p('Could not open that photo.', 'ছবিটি খোলা যায়নি।');
  String get noPassportCode => _p(
    'No passport code found. Choose a clear photo of the passport photo page.',
    'পাসপোর্টের কোড (MRZ) পাওয়া যায়নি। ছবির পাতার পরিষ্কার ছবি দিন।',
  );
  String get passportCodeUnclear => _p(
    'The passport code could not be read clearly. Try a sharper photo.',
    'পাসপোর্টের কোড পরিষ্কার পড়া যায়নি। আরও পরিষ্কার ছবি দিন।',
  );
  String get vaultRejectedScan => _p(
    'The document vault did not accept this scan. Please try again.',
    'ভল্টে এই স্ক্যান নেওয়া হয়নি। আবার চেষ্টা করুন।',
  );
  String get couldNotSaveDocument => _p(
    'Could not save this document. Please try again.',
    'কাগজটি সেভ করা যায়নি। আবার চেষ্টা করুন।',
  );
  String get scanWentWrong => _p(
    'Something went wrong while checking the document. Please try again.',
    'কাগজ যাচাই করার সময় সমস্যা হয়েছে। আবার চেষ্টা করুন।',
  );

  // ---------------------------------------------------------------------------
  // Saved documents
  // ---------------------------------------------------------------------------
  String get savedDocuments => _p('Saved Documents', 'সংরক্ষিত ডকুমেন্ট');
  String get noSavedDocuments => _p(
    'No saved documents yet.\nScan a contract to check it before you sign.',
    'এখনো কোনো কাগজ সেভ করা হয়নি।\nসই করার আগে চুক্তি স্ক্যান করে যাচাই করুন।',
  );
  String get documentFallbackName => _p('Document', 'কাগজ');

  // ---------------------------------------------------------------------------
  // Verdicts & fraud warnings
  // ---------------------------------------------------------------------------
  String get verdictSafe => _p('SAFE', 'নিরাপদ');
  String get verdictCaution => _p('CAUTION', 'সতর্ক থাকুন');
  String get verdictDoNotSign => _p('DO NOT SIGN', 'স্বাক্ষর করবেন না');
  String get tipShoiWarning => _p(
    'Warning: Never give your thumbprint or signature on a blank paper or on a document that demands money!',
    'সতর্কতা: খালি কাগজে বা টাকা দাবি করা কোনো কাগজে কখনোই টিপসই বা সই দেবেন না!',
  );
  String get riskNoStamp => _p('No Stamp Found', 'কোনো সিল পাওয়া যায়নি');
  String get riskBlankSignatureLine =>
      _p('Blank Signature Line Detected', 'টিপসই ঝুঁকি: খালি সইয়ের ঘর');
  String get riskFakeAgency => _p('Fake Agency', 'ভুয়া এজেন্সি');

  // ---------------------------------------------------------------------------
  // Remittance — wallet home
  // ---------------------------------------------------------------------------
  String get currency => _p('Currency', 'মুদ্রা');
  String get availableBalance =>
      _p('Available Balance', 'ব্যবহারযোগ্য ব্যালেন্স');
  String get tapCardToSwitch => _p('Tap card to switch', 'কার্ড বদলাতে চাপুন');
  String get send => _p('Send', 'পাঠান');
  String get receive => _p('Receive', 'গ্রহণ করুন');
  String get quickSend => _p('Quick send', 'দ্রুত পাঠান');
  String get transactionHistory => _p('Transaction History', 'লেনদেনের হিসাব');
  String get seeAll => _p('See all', 'সব দেখুন');
  String get noTransactionsYet =>
      _p('No transactions recorded yet', 'এখনো কোনো লেনদেন নেই');
  String get completeLedger =>
      _p('Complete Transaction Ledger', 'সব লেনদেনের হিসাব');
  String get statusPending => _p('Pending', 'অপেক্ষায়');
  String get statusFailed => _p('Failed', 'হয়নি');
  String awaitingPaymentVia(String provider) =>
      _p('Awaiting payment • $provider', 'পেমেন্টের অপেক্ষায় • $provider');
  String remittanceTo(String account) =>
      _p('Remittance to $account', '$account এ রেমিট্যান্স');
  String minutesAgo(int m) => _p('${m}m ago', '$m মিনিট আগে');
  String todayAt(String time) => _p('$time - Today', '$time - আজ');

  // Beneficiaries
  String get addBeneficiary =>
      _p('Add Remittance Beneficiary', 'টাকা পাঠানোর লোক যোগ করুন');
  String get addBeneficiarySubtitle => _p(
    'Save family or merchant details for quick 1-tap transfer',
    'পরিবার বা দোকানের তথ্য সেভ রাখলে এক চাপে টাকা পাঠাতে পারবেন',
  );
  String get recipientFullName =>
      _p('Recipient Full Name', 'যাকে পাঠাবেন তার পুরো নাম');
  String mobileNumberHint(String dialCode) =>
      _p('Mobile Number ($dialCode...)', 'মোবাইল নম্বর ($dialCode...)');
  String get saveBeneficiary => _p('Save Beneficiary', 'সেভ করুন');

  // ---------------------------------------------------------------------------
  // Remittance — send flow
  // ---------------------------------------------------------------------------
  String get stepRecipient => _p('Recipient', 'যাকে পাঠাবেন');
  String get stepAmount => _p('Amount', 'পরিমাণ');
  String get stepConfirm => _p('Confirm', 'নিশ্চিত');

  String get selectRecipient => _p('Select Recipient', 'যাকে পাঠাবেন বেছে নিন');
  String get selectRecipientSubtitle => _p(
    'Search by name, country, or phone number across all countries',
    'নাম, দেশ বা মোবাইল নম্বর দিয়ে খুঁজুন',
  );
  String get searchContactHint =>
      _p('Search contact or enter phone...', 'নাম খুঁজুন বা নম্বর লিখুন...');
  String noMatchingContact(String query) => _p(
    'No matching contact found for "$query"',
    '"$query" নামে কিছু পাওয়া যায়নি',
  );
  String get sendDirectlyHint => _p(
    'You can still send directly using the banner above',
    'উপরের অংশ থেকে সরাসরি পাঠাতে পারেন',
  );
  String sendDirectlyTo(String number) =>
      _p('Send directly to $number', 'সরাসরি $number এ পাঠান');
  String get selectDestinationCountry =>
      _p('Select Destination Country & Dial Code', 'দেশ ও কোড বেছে নিন');
  String get filterAll => _p('All', 'সব');
  String get filterGlobal => _p('Global', 'অন্য দেশ');
  String get active => _p('Active', 'চালু');

  String get payFrom => _p('PAY FROM', 'যে কার্ড থেকে');
  String get sendAmount => _p('SEND AMOUNT', 'যত টাকা পাঠাবেন');
  String recipientGetsIn(String country) =>
      _p('Recipient Gets in $country:', '$country-এ যত পাবেন:');
  String availableShort(String amount) => _p('Avail: $amount', 'আছে: $amount');
  String get reviewTransferDetails =>
      _p('Review Transfer Details', 'তথ্য দেখে নিন');
  String get enterAmountGreaterThanZero =>
      _p('Please enter an amount greater than 0', '০ এর বেশি টাকা লিখুন');
  String get amountExceedsBalance => _p(
    'Entered amount exceeds your available card balance',
    'কার্ডে এত টাকা নেই',
  );
  String get exchangeRate => _p('Exchange Rate', 'রেট');
  String get govtIncentive => _p('Govt Incentive', 'সরকারি প্রণোদনা');
  String get vatOnCommission => _p('Vat on Commission', 'কমিশনের উপর ভ্যাট');
  String get chargedInUsd => _p('Charged in USD', 'ডলারে কাটা হবে');
  String get totalDebited => _p('Total Debited', 'মোট কাটা হবে');
  String get usdSettlementNote => _p(
    'Every transfer is settled in US Dollars, then paid out in the '
        "recipient's local currency.",
    'প্রতিটি লেনদেন ডলারে হয়, তারপর প্রাপকের দেশের মুদ্রায় দেওয়া হয়।',
  );

  String get reviewAndConfirm => _p('Review & Confirm', 'দেখে নিশ্চিত করুন');
  String get reviewSubtitle => _p(
    'Please verify recipient and remittance amount carefully',
    'যাকে পাঠাচ্ছেন ও টাকার পরিমাণ ভালো করে দেখে নিন',
  );
  String get recipientReceives => _p('RECIPIENT RECEIVES', 'তিনি পাবেন');
  String get govtBonusIncluded =>
      _p('Govt 2.5% Cash Bonus included', 'সরকারি ২.৫% প্রণোদনা সহ');
  String guaranteedSettlement(String country) => _p(
    'Guaranteed Cross-Border Settlement to $country',
    '$country-এ পৌঁছানোর নিশ্চয়তা',
  );
  String get destinationCountry => _p('Destination Country', 'যে দেশে যাবে');
  String get accountOrPhone => _p('Account / Phone', 'একাউন্ট / মোবাইল');
  String get channelProvider => _p('Channel / Provider', 'যে মাধ্যমে');
  String get sourceDeduction => _p('Source Deduction', 'আপনার কাছ থেকে কাটবে');
  String get debitedFrom => _p('Debited From', 'যে কার্ড থেকে');
  String get transferFee => _p('Transfer Fee', 'ফি');
  String get feeFree => _p('FREE (0.00)', 'ফ্রি (০.০০)');
  String get settlementSpeed => _p('Settlement Speed', 'কত সময় লাগবে');
  String get instantVerified => _p('Instant Verified', 'সাথে সাথে');
  String get remittanceProtectionNote => _p(
    'Protected by Bangladesh Bank Expatriate Remittance Guidelines & Host WPS Guarantee.',
    'বাংলাদেশ ব্যাংকের প্রবাসী রেমিট্যান্স নিয়ম ও WPS সুরক্ষার আওতায়।',
  );
  String get holdToConfirm => _p('Hold to Confirm', 'চেপে ধরে নিশ্চিত করুন');
  String get transferConfirmed =>
      _p('Transfer Confirmed', 'পাঠানো নিশ্চিত হয়েছে');

  // Stripe hand-off
  String get completePaymentOnStripe =>
      _p('Complete payment on Stripe', 'Stripe-এ পেমেন্ট শেষ করুন');
  String stripeHandoffBody(String name) => _p(
    'Finish the card payment in the browser to send this remittance to $name. This screen updates on its own as soon as Stripe confirms it.',
    '$name-কে টাকা পাঠাতে ব্রাউজারে কার্ড পেমেন্ট শেষ করুন। Stripe নিশ্চিত করলেই এই পাতা নিজে থেকে বদলে যাবে।',
  );
  String get reopenStripePage =>
      _p('Reopen Stripe page', 'Stripe পাতা আবার খুলুন');
  String get checkingWithStripe =>
      _p('Checking with Stripe…', 'Stripe-এ দেখা হচ্ছে…');
  String get ivePaidCheckNow =>
      _p("I've paid — check now", 'টাকা দিয়েছি — এখন দেখুন');
  String get cancelTransfer => _p('Cancel transfer', 'পাঠানো বাতিল করুন');
  String get remittanceSuccessful =>
      _p('Remittance Successful!', 'টাকা পাঠানো হয়েছে!');
  String creditedTo(String amount, String name, String provider) => _p(
    '$amount has been credited to $name ($provider).',
    '$amount $name ($provider) এর কাছে পৌঁছে গেছে।',
  );
  String get appearsInHistory => _p(
    'It now appears in your Transaction History.',
    'এটি এখন আপনার লেনদেনের হিসাবে আছে।',
  );
  String get gatewayNoCheckoutPage => _p(
    'The gateway did not return a Stripe Checkout page.',
    'Stripe-এর পেমেন্ট পাতা পাওয়া যায়নি।',
  );
  String get couldNotOpenCheckout => _p(
    'Could not open the Stripe Checkout page on this device. Please make sure a browser is installed.',
    'এই ফোনে Stripe-এর পেমেন্ট পাতা খোলা যায়নি। ব্রাউজার আছে কিনা দেখুন।',
  );
  String get paymentNotCompleted => _p(
    'Payment was not completed, so nothing was sent.',
    'পেমেন্ট শেষ হয়নি, তাই কোনো টাকা যায়নি।',
  );

  // ---------------------------------------------------------------------------
  // Receive & inter-card transfer
  // ---------------------------------------------------------------------------
  String get receiveTitle =>
      _p('Receive Remittance & Funds', 'টাকা গ্রহণ করুন');
  String get receiveSubtitle => _p(
    'Scan QR code or use account IBAN for direct transfer',
    'QR কোড স্ক্যান করুন বা IBAN দিয়ে সরাসরি টাকা নিন',
  );
  String get verifiedMerchantId =>
      _p('Probashi Verified Merchant & Personal ID', 'প্রবাসী যাচাই করা আইডি');
  String get accountId => _p('Account ID', 'একাউন্ট আইডি');
  String get remittanceIban => _p('REMITTANCE IBAN', 'রেমিট্যান্স IBAN');
  String get shareInfo => _p('Share Info', 'তথ্য শেয়ার করুন');
  String get paymentInfo => _p('Payment info', 'পেমেন্টের তথ্য');
  String copiedToClipboard(String label) =>
      _p('$label copied to clipboard!', '$label কপি হয়েছে!');

  String get interCardTransfer =>
      _p('Inter-Card Transfer', 'কার্ড থেকে কার্ডে');
  String get interCardSubtitle => _p(
    'Instant zero-fee transfer between your linked accounts',
    'আপনার নিজের একাউন্টগুলোর মধ্যে ফ্রি ও সাথে সাথে টাকা সরান',
  );
  String get fromAccount => _p('From Account', 'যে একাউন্ট থেকে');
  String get toAccount => _p('To Account', 'যে একাউন্টে');
  String get confirmTransfer => _p('Confirm Transfer', 'নিশ্চিত করুন');
  String get sameCardTransfer => _p(
    'Choose two different cards to transfer between',
    'আলাদা দুটি কার্ড বেছে নিন',
  );
  String get enterValidTransferAmount =>
      _p('Please enter a valid transfer amount', 'সঠিক পরিমাণ লিখুন');
  String get insufficientSourceBalance => _p(
    'Insufficient balance on selected source card',
    'এই কার্ডে পর্যাপ্ত টাকা নেই',
  );

  // ---------------------------------------------------------------------------
  // Log in, register and email verification
  // ---------------------------------------------------------------------------
  String get authWelcomeBack => _p('Welcome back', 'আবার স্বাগতম');
  String get authLoginSubtitle =>
      _p('Log in to continue', 'চালিয়ে যেতে লগ ইন করুন');
  String get authCreateAccount => _p('Create account', 'অ্যাকাউন্ট খুলুন');
  String get authRegisterSubtitle =>
      _p('Sign up to continue', 'চালিয়ে যেতে সাইন আপ করুন');

  String get authFullName => _p('Full name', 'পুরো নাম');
  String get authFullNameHint => _p('Your full name', 'আপনার পুরো নাম');
  String get authEmail => _p('Email', 'ইমেইল');
  String get authEmailHint => _p('Your email', 'আপনার ইমেইল');
  String get authPassword => _p('Password', 'পাসওয়ার্ড');
  String get authPasswordHint => _p('Your password', 'আপনার পাসওয়ার্ড');
  String get authConfirmPassword =>
      _p('Confirm password', 'পাসওয়ার্ড আবার লিখুন');
  String get authConfirmPasswordHint =>
      _p('Confirm your password', 'পাসওয়ার্ডটি আবার লিখুন');
  String get authShowPassword => _p('Show password', 'পাসওয়ার্ড দেখান');
  String get authHidePassword => _p('Hide password', 'পাসওয়ার্ড লুকান');

  String get authForgotPassword =>
      _p('Forgot password?', 'পাসওয়ার্ড ভুলে গেছেন?');
  String get authResetTitle => _p('Reset password', 'পাসওয়ার্ড রিসেট করুন');
  String get authResetSubtitle => _p(
    "Enter your account's email and we will send you a 6-digit code",
    'অ্যাকাউন্টের ইমেইল লিখুন, আমরা একটি ৬-সংখ্যার কোড পাঠাব',
  );
  String get authSendCode => _p('Send code', 'কোড পাঠান');
  String get authNewPassword => _p('New password', 'নতুন পাসওয়ার্ড');
  String get authNewPasswordHint =>
      _p('Choose a new password', 'নতুন পাসওয়ার্ড দিন');
  String get authSavePassword =>
      _p('Save new password', 'নতুন পাসওয়ার্ড সেভ করুন');
  String get authPasswordChanged => _p(
    'Password changed. You are logged in.',
    'পাসওয়ার্ড বদলানো হয়েছে। আপনি লগ ইন করেছেন।',
  );
  String get authSamePassword => _p(
    'Choose a password different from your old one',
    'পুরনো পাসওয়ার্ড থেকে আলাদা পাসওয়ার্ড দিন',
  );

  String get authLogIn => _p('Log in', 'লগ ইন');
  String get authRegister => _p('Register', 'রেজিস্টার করুন');
  String get authOr => _p('Or', 'অথবা');
  String get authWithGoogle =>
      _p('Log in with Google', 'Google দিয়ে লগ ইন করুন');
  String get authWithGithub =>
      _p('Log in with GitHub', 'GitHub দিয়ে লগ ইন করুন');
  String get authNoAccount => _p("Don't have an account? ", 'অ্যাকাউন্ট নেই? ');
  String get authHaveAccount =>
      _p('Already have an account? ', 'আগেই অ্যাকাউন্ট আছে? ');

  // Bangla puts the verb after the link, so the sentence comes in three parts.
  String get authAgreePrefix => _p('I agree to the ', 'আমি ');
  String get authTermsLink =>
      _p('Terms and Privacy Policy', 'শর্তাবলি ও গোপনীয়তা নীতিতে');
  String get authAgreeSuffix => _p('', ' সম্মত');

  String get authVerifyTitle =>
      _p('Verify your email', 'আপনার ইমেইল যাচাই করুন');
  String authCodeSentTo(String email) => _p(
    'We sent a 6-digit code to $email',
    'আমরা $email-এ একটি ৬-সংখ্যার কোড পাঠিয়েছি',
  );
  String get authVerify => _p('Verify', 'যাচাই করুন');
  String get authResendCode => _p('Resend code', 'আবার কোড পাঠান');
  String authResendIn(int seconds) => _p(
    'Resend code in ${seconds}s',
    '$seconds সেকেন্ড পরে আবার পাঠাতে পারবেন',
  );
  String get authCodeResent =>
      _p('A new code is on its way', 'নতুন কোড পাঠানো হয়েছে');
  String get authCodeLabel => _p('6-digit code', '৬-সংখ্যার কোড');

  String get authEnterName =>
      _p('Enter your full name', 'আপনার পুরো নাম লিখুন');
  String get authInvalidEmail =>
      _p('Enter a valid email address', 'সঠিক ইমেইল ঠিকানা লিখুন');
  String get authEnterPassword => _p('Enter your password', 'পাসওয়ার্ড লিখুন');
  String get authPasswordTooShort => _p(
    'Password must be at least 6 characters',
    'পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে',
  );
  String get authPasswordsMismatch =>
      _p('Passwords do not match', 'দুটি পাসওয়ার্ড মিলছে না');
  String get authAcceptTerms => _p(
    'Please agree to the Terms and Privacy Policy',
    'শর্তাবলি ও গোপনীয়তা নীতিতে সম্মতি দিন',
  );
  String get authCodeIncomplete =>
      _p('Enter all 6 digits of the code', 'কোডের ৬টি সংখ্যাই লিখুন');
  String get authCodeInvalid => _p(
    'That code is wrong or has expired',
    'কোডটি ভুল অথবা মেয়াদ শেষ হয়ে গেছে',
  );
  String get authInvalidCredentials =>
      _p('Wrong email or password', 'ইমেইল বা পাসওয়ার্ড ভুল');
  String get authEmailNotConfirmed => _p(
    'Verify your email first. We sent you a new code.',
    'আগে ইমেইল যাচাই করুন। আমরা নতুন কোড পাঠিয়েছি।',
  );
  String get authAccountExists => _p(
    'An account with this email already exists. Please log in.',
    'এই ইমেইলে আগেই অ্যাকাউন্ট আছে। লগ ইন করুন।',
  );
  String get authWeakPassword =>
      _p('Choose a stronger password', 'আরও শক্ত পাসওয়ার্ড দিন');
  String get authTooManyAttempts => _p(
    'Too many attempts. Wait a minute and try again.',
    'অনেকবার চেষ্টা হয়েছে। এক মিনিট পরে আবার চেষ্টা করুন।',
  );
  String get authNetworkError => _p(
    'Could not reach the server. Check your internet.',
    'সার্ভারে পৌঁছানো যায়নি। ইন্টারনেট সংযোগ দেখুন।',
  );
  String authOAuthFailed(String provider) =>
      _p('Could not open $provider sign-in', '$provider লগ ইন খোলা যায়নি');
  String get authGenericError => _p(
    'Something went wrong. Please try again.',
    'কোনো সমস্যা হয়েছে। আবার চেষ্টা করুন।',
  );

  // ---------------------------------------------------------------------------
  // Claiming a phone number (the address money is sent to)
  // ---------------------------------------------------------------------------
  String get authPhoneTitle =>
      _p('Add your phone number', 'আপনার মোবাইল নম্বর দিন');
  String get authPhoneSubtitle => _p(
    'People send you money using this number, so it has to be yours alone.',
    'এই নম্বরে আপনাকে টাকা পাঠানো হবে, তাই এটি শুধু আপনার হতে হবে।',
  );
  String get authPhoneLabel => _p('Mobile number', 'মোবাইল নম্বর');
  String get authPhoneHint => _p('01712345678', '০১৭১২৩৪৫৬৭৮');
  String get authPhoneSave => _p('Save number', 'নম্বর সেভ করুন');
  String get authPhoneSaved => _p('Number saved', 'নম্বর সেভ হয়েছে');
  String get authPhoneInvalid =>
      _p('Enter a valid mobile number', 'সঠিক মোবাইল নম্বর লিখুন');
  String get authPhoneTaken => _p(
    'Another account already uses that number',
    'এই নম্বরটি অন্য একটি অ্যাকাউন্টে ব্যবহার হচ্ছে',
  );
  String get authPhoneSendCode => _p('Send code', 'কোড পাঠান');
  String authPhoneCodeSentTo(String phone) => _p(
    'We sent a 6-digit code to $phone',
    'আমরা $phone নম্বরে একটি ৬-সংখ্যার কোড পাঠিয়েছি',
  );
  String get authPhoneChangeNumber => _p('Change number', 'নম্বর বদলান');
  String get authPhoneVerify => _p('Verify number', 'নম্বর যাচাই করুন');
  String get authPhoneVerified => _p('Number verified', 'নম্বর যাচাই হয়েছে');
  String get authPhoneSkip => _p('Skip for now', 'এখন থাক');
  String get authPhoneSkipNote => _p(
    'You can look around without a verified number, but sending and '
        'receiving money stays locked until you verify one.',
    'নম্বর যাচাই ছাড়াও অ্যাপ দেখতে পারবেন, তবে টাকা পাঠানো ও গ্রহণ করা '
        'বন্ধ থাকবে।',
  );
  String get authPhoneNotConfigured => _p(
    'Phone verification is not set up yet. You can continue without it '
        'for now.',
    'ফোন যাচাই এখনো চালু হয়নি। আপাতত এটি ছাড়াই চালিয়ে যেতে পারেন।',
  );
  String get authPhoneCodeWrong => _p(
    'That code is wrong or has expired',
    'কোডটি ভুল অথবা মেয়াদ শেষ হয়ে গেছে',
  );
  String get authPhoneTooManyRequests => _p(
    'Too many attempts from this device. Try again later.',
    'এই ডিভাইস থেকে অনেকবার চেষ্টা হয়েছে। পরে আবার চেষ্টা করুন।',
  );
  String get authPhoneSmsUnavailable => _p(
    'We cannot send an SMS to this number yet. Try again later, or skip '
        'for now.',
    'এই নম্বরে এখনো SMS পাঠানো যাচ্ছে না। পরে আবার চেষ্টা করুন, অথবা আপাতত '
        'এড়িয়ে যান।',
  );
  String get authPhoneCountryLabel => _p('Country', 'দেশ');
  String authPhoneInvalidLength(String digits, String example) => _p(
    'Enter a number with $digits digits, like $example',
    '$digits সংখ্যার নম্বর লিখুন, যেমন $example',
  );
  String authPhoneDigitCount(int typed, String digits) =>
      _p('$typed / $digits digits', '$typed / $digits সংখ্যা');
  String get authPhoneCodeLabel => _p('Verification code', 'যাচাই কোড');
  String get authPhoneCodeHint => _p('6-digit code', '৬ সংখ্যার কোড');
  String get authPhoneCodeSent => _p('Code sent', 'কোড পাঠানো হয়েছে');
  String get authPhoneClearLabel => _p('Clear', 'মুছুন');
  String get authPhoneTestModeNote => _p(
    'Testing build: use a test number from the Firebase console with its '
        'code. No SMS is sent.',
    'টেস্টিং বিল্ড: Firebase কনসোলের টেস্ট নম্বর ও তার কোড দিন। কোনো SMS '
        'পাঠানো হয় না।',
  );
  String phoneCountryName(String iso) {
    switch (iso) {
      case 'BD':
        return _p('Bangladesh', 'বাংলাদেশ');
      case 'SA':
        return _p('Saudi Arabia', 'সৌদি আরব');
      case 'AE':
        return _p('United Arab Emirates', 'সংযুক্ত আরব আমিরাত');
      case 'QA':
        return _p('Qatar', 'কাতার');
      case 'KW':
        return _p('Kuwait', 'কুয়েত');
      case 'OM':
        return _p('Oman', 'ওমান');
      case 'MY':
        return _p('Malaysia', 'মালয়েশিয়া');
      case 'SG':
        return _p('Singapore', 'সিঙ্গাপুর');
      default:
        return iso;
    }
  }

  // ---------------------------------------------------------------------------
  // Generic feedback
  // ---------------------------------------------------------------------------
  String comingSoon(String feature) =>
      _p('$feature is coming soon', '$feature শীঘ্রই আসছে');

  // Names of the features that only say "coming soon" for now. They match the
  // labels on the tiles that open them.
  String get featureTransactionDetails =>
      _p('Transaction Details', 'লেনদেনের বিবরণ');
  String get featureTermsPrivacy =>
      _p('Terms and Privacy Policy', 'শর্তাবলি ও গোপনীয়তা নীতি');
  String get featurePassportVisa => _p('Passport & Visa', 'পাসপোর্ট ও ভিসা');
  String get featureBmetCard => _p('BMET Smart Card', 'বিএমইটি স্মার্ট কার্ড');
  String get featureBiometric => _p('Touch / Face ID', 'টাচ/ফেস আইডি');
  String get featureChangePin => _p('Change PIN', 'পিন পরিবর্তন');
  String get featureLinkedDevices => _p('Linked Devices', 'লিংকড ডিভাইস');
  String get featureNotificationManagement =>
      _p('Notification Management', 'নোটিফিকেশন ম্যানেজমেন্ট');
  String get remittanceFailed => _p(
    'Failed to complete remittance. Please try again.',
    'টাকা পাঠানো যায়নি। আবার চেষ্টা করুন।',
  );
}

/// Publishes the active [AppStrings] to the whole widget tree.
///
/// It sits above `MaterialApp`, so routes, dialogs and bottom sheets — which
/// build under the app's Navigator — all resolve the same strings, and a
/// language change repaints them together.
class AppStringsScope extends InheritedWidget {
  final AppStrings strings;

  const AppStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.strings.languageCode != strings.languageCode;
}

/// One pre-departure checklist row's wording.
class ChecklistText {
  final String title;
  final String subtitle;

  const ChecklistText(this.title, this.subtitle);
}

/// One notice slide's wording; its icon and colours stay in the widget.
class NoticeText {
  final String tag;
  final String message;

  const NoticeText(this.tag, this.message);
}
