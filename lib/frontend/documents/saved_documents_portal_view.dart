import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../theme/app_colors.dart';
import 'document_detail_view.dart';
import 'models/document_analysis.dart';
import 'repository/document_analysis_repository.dart';

/// Vault of every document this user has scanned, read from Supabase
/// `saved_documents` (row-level security limits it to the current user).
class SavedDocumentsPortalView extends StatefulWidget {
  final DocumentAnalysisRepository? repository;

  const SavedDocumentsPortalView({super.key, this.repository});

  @override
  State<SavedDocumentsPortalView> createState() => _SavedDocumentsPortalViewState();
}

class _SavedDocumentsPortalViewState extends State<SavedDocumentsPortalView> {
  late final DocumentAnalysisRepository _repository =
      widget.repository ?? DocumentAnalysisRepository();
  late Future<List<SavedDocument>> _documents = _repository.fetchSavedDocuments();

  Future<void> _refresh() async {
    final next = _repository.fetchSavedDocuments();
    setState(() => _documents = next);
    await next.catchError((_) => <SavedDocument>[]);
  }

  void _open(SavedDocument doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentDetailView(
          analysis: doc.analysis,
          language: doc.language,
          scannedAt: doc.createdAt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cloudDancer,
      appBar: AppBar(
        backgroundColor: AppColors.cloudDancer,
        foregroundColor: AppColors.royalBlue,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(AppStrings.of(context).savedDocuments,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        color: AppColors.royalBlue,
        onRefresh: _refresh,
        child: FutureBuilder<List<SavedDocument>>(
          future: _documents,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.royalBlue));
            }
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_rounded,
                message: snapshot.error.toString(),
                actionLabel: AppStrings.of(context).tryAgain,
                onAction: _refresh,
              );
            }
            final docs = snapshot.data ?? const [];
            if (docs.isEmpty) {
              return const _MessageState(
                icon: Icons.folder_open_rounded,
                message: 'No saved documents yet.\nScan a contract to check it before you sign.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _DocumentCard(document: docs[i], onTap: () => _open(docs[i])),
            );
          },
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final SavedDocument document;
  final VoidCallback onTap;

  const _DocumentCard({required this.document, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = document.analysis;
    final (color, icon) = verdictStyle(a.verdict);
    return Material(
      color: AppColors.cloudDancer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: a.tipShoiDetected ? AppColors.crimsonRed : AppColors.royalBlue.withValues(alpha: 0.16),
              width: a.tipShoiDetected ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.documentType ??
                          AppStrings.of(context).documentFallbackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${a.verdict.label(document.language)} · ${_formatDate(document.createdAt)}',
                      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (a.tipShoiDetected)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'টিপ সই warning',
                          style: TextStyle(color: AppColors.crimsonRed, fontSize: 12.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.royalBlueMuted),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({required this.icon, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    // A ListView so pull-to-refresh still works on the empty and error states.
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
      children: [
        Icon(icon, size: 56, color: AppColors.royalBlueMuted),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 15, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.royalBlue),
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
