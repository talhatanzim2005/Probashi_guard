import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/language_controller.dart';
import '../../theme/app_colors.dart';
import '../profile/controllers/profile_controller.dart';
import 'prohori_repository.dart';

/// The dark, glowing look of this one screen. Every colour here is a colour of
/// [AppColors] or a tint of one (mixed toward [AppColors.ink] or
/// [AppColors.cloudDancer], or made translucent), and each surface is a
/// gradient between them.
abstract final class _Glow {
  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  /// [AppColors.emeraldGreen] lightened toward [AppColors.cloudDancer]. Icons,
  /// links and the cursor need more contrast on the dark ground than the pure
  /// green gives.
  static final Color accent = _mix(
    AppColors.emeraldGreen,
    AppColors.cloudDancer,
    0.4,
  );

  /// [AppColors.crimsonRed] lightened the same way, for text on a red tint.
  static final Color errorText = _mix(
    AppColors.crimsonRed,
    AppColors.cloudDancer,
    0.6,
  );

  static Color get edge => AppColors.cloudDancer.withValues(alpha: 0.14);

  /// The ground: royal blue sinking into ink.
  static final Gradient sky = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      _mix(AppColors.ink, AppColors.royalBlue, 0.45),
      _mix(AppColors.ink, AppColors.royalBlue, 0.12),
      AppColors.ink,
    ],
    stops: const [0, 0.55, 1],
  );

  /// A royal blue glow at the top right and an emerald one at the bottom right.
  static final Gradient glowTop = RadialGradient(
    center: const Alignment(1, -0.9),
    radius: 1.1,
    colors: [
      AppColors.royalBlue.withValues(alpha: 0.65),
      AppColors.royalBlue.withValues(alpha: 0),
    ],
  );
  static final Gradient glowBottom = RadialGradient(
    center: const Alignment(1.1, 0.95),
    radius: 0.85,
    colors: [
      AppColors.emeraldGreen.withValues(alpha: 0.55),
      AppColors.emeraldGreen.withValues(alpha: 0),
    ],
  );

  /// Send button: green into blue, with the light icon readable at both ends.
  static final Gradient send = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.emeraldGreen, AppColors.royalBlue],
  );

  /// The person's own bubbles: the send gradient, a little darker so 14px text
  /// keeps at least 4.5:1 contrast at both ends.
  static final Gradient ownBubble = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      _mix(AppColors.emeraldGreen, AppColors.ink, 0.2),
      _mix(AppColors.royalBlue, AppColors.ink, 0.1),
    ],
  );

  static final Gradient errorBubble = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.crimsonRed.withValues(alpha: 0.30),
      AppColors.crimsonRed.withValues(alpha: 0.12),
    ],
  );

  /// The input pill: dark blue on the left fading to dark green on the right.
  static final Gradient pill = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      _mix(AppColors.ink, AppColors.royalBlue, 0.3).withValues(alpha: 0.9),
      _mix(AppColors.ink, AppColors.emeraldGreen, 0.25).withValues(alpha: 0.9),
    ],
  );

  /// The circle behind a card's icon.
  static final Gradient badge = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.emeraldGreen.withValues(alpha: 0.55),
      AppColors.royalBlue.withValues(alpha: 0.55),
    ],
  );

  /// The big greeting: cloud white fading into the green accent.
  static final Gradient title = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.cloudDancer, accent],
  );

  /// A pane of dark glass: a faint sheen from the top left.
  static Gradient glass() => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.cloudDancer.withValues(alpha: 0.10),
      AppColors.cloudDancer.withValues(alpha: 0.04),
    ],
  );
}

/// Who said a line, and whether it is a failure the person can retry.
class _Line {
  final String text;
  final bool fromUser;
  final bool isError;

  const _Line(this.text, {required this.fromUser, this.isError = false});
}

/// Chat with Prohori, the AI assistant. Each question goes to backend_service
/// (/api/chat), which answers from the FAQ knowledge base.
class ProhoriChatView extends StatefulWidget {
  final ProhoriRepository? repository;

  const ProhoriChatView({super.key, this.repository});

  @override
  State<ProhoriChatView> createState() => _ProhoriChatViewState();
}

class _ProhoriChatViewState extends State<ProhoriChatView> {
  late final ProhoriRepository _repository =
      widget.repository ?? ProhoriRepository();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  /// What the person has said and Prohori has answered. The greeting and the
  /// suggestion cards are not stored here: they are drawn from the current
  /// language while this is empty, so they follow it.
  final List<_Line> _lines = [];

  bool _waiting = false;

  /// The last question, so a failed one can be sent again without retyping.
  String? _lastQuestion;

  bool get _canSend => !_waiting && _input.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    if (!_canSend) return;
    final question = _input.text.trim();
    _input.clear();
    await _submit(question);
  }

  /// A suggestion card was tapped: its question goes out as if it were typed.
  /// Whatever the person had already started typing is left alone.
  Future<void> _sendSuggestion(String question) async {
    if (_waiting) return;
    await _submit(question);
  }

  Future<void> _submit(String question) async {
    HapticFeedback.selectionClick();
    setState(() => _lines.add(_Line(question, fromUser: true)));
    await _ask(question);
  }

  Future<void> _retry() async {
    final question = _lastQuestion;
    if (question == null || _waiting) return;
    // The failed line goes; the question itself is already on screen.
    setState(() {
      if (_lines.isNotEmpty && _lines.last.isError) _lines.removeLast();
    });
    await _ask(question);
  }

  Future<void> _ask(String question) async {
    _lastQuestion = question;
    setState(() => _waiting = true);
    _scrollToEnd();

    final s = AppStrings.of(context);
    final language = LanguageController.instance.isBangla ? 'bn' : 'en';
    _Line answer;
    try {
      final reply = await _repository.ask(question, language: language);
      answer = _Line(reply, fromUser: false);
    } on ProhoriException catch (e) {
      answer = _Line(
        _problemText(s, e.problem),
        fromUser: false,
        isError: true,
      );
    } catch (_) {
      answer = _Line(s.prohoriFailed, fromUser: false, isError: true);
    }
    if (!mounted) return;
    setState(() {
      _lines.add(answer);
      _waiting = false;
    });
    _scrollToEnd();
  }

  String _problemText(AppStrings s, ProhoriProblem problem) =>
      switch (problem) {
        ProhoriProblem.unavailable => s.prohoriUnavailable,
        ProhoriProblem.unreachable => s.prohoriUnreachable,
        ProhoriProblem.timeout => s.prohoriTimeout,
        ProhoriProblem.busy => s.prohoriBusy,
        ProhoriProblem.signIn => s.prohoriSignIn,
        ProhoriProblem.failed => s.prohoriFailed,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    // The glow sits behind the Scaffold, not in its body, so it stays put when
    // the keyboard shrinks the body instead of sliding up with it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _GlowBackground(),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: Column(
              children: [
                _buildHeader(context, s),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    children: [
                      if (_lines.isEmpty) ..._buildEmptyState(s),
                      for (var i = 0; i < _lines.length; i++)
                        _Bubble(
                          text: _lines[i].text,
                          fromUser: _lines[i].fromUser,
                          isError: _lines[i].isError,
                          // Only the newest failure can be retried.
                          onRetry: _lines[i].isError && i == _lines.length - 1
                              ? _retry
                              : null,
                          retryLabel: s.tryAgain,
                        ),
                      if (_waiting) _Typing(label: s.prohoriThinking),
                    ],
                  ),
                ),
                _buildComposer(context, s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The greeting and the most asked questions, shown until the first message.
  List<Widget> _buildEmptyState(AppStrings s) {
    final cards = [
      (
        icon: Icons.account_balance_rounded,
        title: s.prohoriRemitTitle,
        question: s.prohoriRemitAsk,
      ),
      (
        icon: Icons.policy_rounded,
        title: s.prohoriLegalTitle,
        question: s.prohoriLegalAsk,
      ),
      (
        icon: Icons.work_rounded,
        title: s.prohoriRightsTitle,
        question: s.prohoriRightsAsk,
      ),
    ];

    return [
      const SizedBox(height: 12),
      _Rise(index: 0, child: _Greeting(strings: s)),
      const SizedBox(height: 28),
      for (var i = 0; i < cards.length; i++)
        _Rise(
          index: i + 1,
          child: _SuggestionCard(
            icon: cards[i].icon,
            title: cards[i].title,
            subtitle: cards[i].question,
            onTap: () => _sendSuggestion(cards[i].question),
          ),
        ),
    ];
  }

  Widget _buildHeader(BuildContext context, AppStrings s) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.cloudDancer,
              ),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cloudDancer.withValues(alpha: 0.10),
                side: BorderSide(color: _Glow.edge),
              ),
            ),
            const SizedBox(width: 12),
            ProhoriAvatar(
              radius: 20,
              backgroundColor: AppColors.cloudDancer.withValues(alpha: 0.12),
              iconColor: _Glow.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.prohori,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.cloudDancer,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    s.prohoriSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.cloudDancer.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A pill that floats above the bottom edge (and so above the keyboard, since
  /// the Scaffold lifts its body), with the send button inside its right end.
  Widget _buildComposer(BuildContext context, AppStrings s) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: _Glow.pill,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: _Glow.edge),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: ProhoriRepository.maxQuestionLength,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: _Glow.accent,
                        style: const TextStyle(
                          color: AppColors.cloudDancer,
                          fontSize: 15,
                        ),
                        decoration: InputDecoration(
                          hintText: s.prohoriInputHint,
                          hintStyle: TextStyle(
                            color: AppColors.cloudDancer.withValues(alpha: 0.6),
                          ),
                          counterText: '',
                          isDense: true,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(
                      label: s.prohoriSend,
                      enabled: _canSend,
                      onTap: _send,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.prohoriDisclaimer,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.cloudDancer.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prohori's round badge, shared by the chat header and its menu card.
class ProhoriAvatar extends StatelessWidget {
  final double radius;
  final Color backgroundColor;
  final Color iconColor;

  const ProhoriAvatar({
    super.key,
    required this.radius,
    this.backgroundColor = AppColors.cloudDancer,
    this.iconColor = AppColors.royalBlue,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: Icon(Icons.shield_rounded, color: iconColor, size: radius * 1.1),
    );
  }
}

/// Royal blue sinking into ink, with a blue glow in the top right and an
/// emerald one at the bottom right.
class _GlowBackground extends StatelessWidget {
  const _GlowBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: _Glow.sky)),
        DecoratedBox(decoration: BoxDecoration(gradient: _Glow.glowTop)),
        DecoratedBox(decoration: BoxDecoration(gradient: _Glow.glowBottom)),
      ],
    );
  }
}

/// "HI JOSH !" and the line under it. Listens to the profile so the name
/// appears as soon as sign-in has filled it in.
class _Greeting extends StatelessWidget {
  final AppStrings strings;
  const _Greeting({required this.strings});

  static String _firstName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ProfileController.instance,
      builder: (context, _) {
        // Without a real name the greeting stays "HI THERE !" instead of
        // calling the person "Guest".
        final profile = ProfileController.instance;
        final hi = strings.prohoriHi(
          profile.hasName ? _firstName(profile.userName) : '',
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              // The text colour only has to be opaque: the gradient replaces it.
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: _Glow.title.createShader,
                child: Text(
                  hi,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Big type is the point, but not at 2x system text.
                  textScaler: MediaQuery.textScalerOf(
                    context,
                  ).clamp(maxScaleFactor: 1.3),
                  style: const TextStyle(
                    color: AppColors.cloudDancer,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              strings.prohoriPrompt,
              style: TextStyle(
                color: AppColors.cloudDancer.withValues(alpha: 0.75),
                fontSize: 16,
                height: 1.35,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One suggested question: an icon, what it is about, and the question itself.
/// Tapping it sends the question.
class _SuggestionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SuggestionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(20));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            gradient: _Glow.glass(),
            borderRadius: radius,
            border: Border.all(color: _Glow.edge),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            splashColor: _Glow.accent.withValues(alpha: 0.12),
            highlightColor: AppColors.cloudDancer.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _Glow.badge,
                    ),
                    child: Icon(icon, color: _Glow.accent, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.cloudDancer,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppColors.cloudDancer.withValues(
                              alpha: 0.75,
                            ),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular send button with a green-to-blue fill. Dims when there is nothing
/// to send, but stays put so the pill does not change shape.
class _SendButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _SendButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 160),
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _Glow.send,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: const Icon(
                Icons.send_rounded,
                color: AppColors.cloudDancer,
                size: 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades its child in and lifts it a little, each one a beat after the last.
/// Plays once, and not at all when the device asks for less motion.
class _Rise extends StatelessWidget {
  final int index;
  final Widget child;

  const _Rise({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    const stepMs = 70;
    const travelMs = 380;
    final totalMs = travelMs + index * stepMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(index * stepMs / totalMs, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool fromUser;
  final bool isError;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const _Bubble({
    required this.text,
    required this.fromUser,
    this.isError = false,
    this.onRetry,
    this.retryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isError ? _Glow.errorText : AppColors.cloudDancer;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: fromUser
                ? _Glow.ownBubble
                : isError
                ? _Glow.errorBubble
                : _Glow.glass(),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(fromUser ? 18 : 4),
              bottomRight: Radius.circular(fromUser ? 4 : 18),
            ),
            border: fromUser
                ? null
                : Border.all(
                    color: isError
                        ? _Glow.errorText.withValues(alpha: 0.4)
                        : _Glow.edge,
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                text,
                style: TextStyle(color: textColor, fontSize: 14.5, height: 1.4),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: _Glow.accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            retryLabel ?? '',
                            style: TextStyle(
                              color: _Glow.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  final String label;
  const _Typing({required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: _Glow.glass(),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _Glow.edge),
          ),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: _Glow.accent,
            ),
          ),
        ),
      ),
    );
  }
}
