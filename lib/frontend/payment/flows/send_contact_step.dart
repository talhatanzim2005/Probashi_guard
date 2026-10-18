import 'package:flutter/material.dart';
import '../../../l10n/app_strings.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';
import '../models/country_model.dart';
import '../utils/phone_search_helper.dart';

class SendContactStep extends StatefulWidget {
  final List<BeneficiaryModel> beneficiaries;
  final ValueChanged<BeneficiaryModel> onSelectRecipient;

  const SendContactStep({
    super.key,
    required this.beneficiaries,
    required this.onSelectRecipient,
  });

  @override
  State<SendContactStep> createState() => _SendContactStepState();
}

class _SendContactStepState extends State<SendContactStep> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  String _searchQuery = '';
  CountryModel _selectedCountry = CountryModel.defaultCountry;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesFilter(BeneficiaryModel b) {
    if (_selectedFilter == 'All') return true;
    if (_selectedFilter == '🇧🇩 Bangladesh') return b.countryCode == 'BD';
    if (_selectedFilter == '🇸🇦 Saudi') return b.countryCode == 'SA';
    if (_selectedFilter == '🇦🇪 UAE') return b.countryCode == 'AE';
    if (_selectedFilter == 'Global') return !['BD', 'SA', 'AE'].contains(b.countryCode);
    if (_selectedFilter == 'bKash') return b.providerType.toLowerCase() == 'bkash';
    if (_selectedFilter == 'Nagad') return b.providerType.toLowerCase() == 'nagad';
    if (_selectedFilter == 'Bank') return b.providerType.toLowerCase().contains('bank');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // Intelligent search using PhoneSearchHelper
    final filtered = widget.beneficiaries.where((b) {
      final matchesQuery = PhoneSearchHelper.matches(b, _searchQuery);
      final matchesFilter = _matchesFilter(b);
      return matchesQuery && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.selectRecipient,
          style: const TextStyle(
            color: AppColors.royalBlue,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          s.selectRecipientSubtitle,
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),

        // Search Bar with Country Selector and Search Icon
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.royalBlue.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.royalBlue.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Country Dial Code Selector for new numbers
              InkWell(
                onTap: _showCountryPickerSheet,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.royalBlue.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                    border: Border(
                      right: BorderSide(
                        color: AppColors.royalBlue.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedCountry.flag,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedCountry.dialCode,
                        style: const TextStyle(
                          color: AppColors.royalBlue,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: AppColors.royalBlue,
                      ),
                    ],
                  ),
                ),
              ),

              // Search Text Field
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: s.searchContactHint,
                    hintStyle: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.royalBlue,
                      size: 19,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <({String key, String label})>[
              (key: 'All', label: s.filterAll),
              (key: '🇧🇩 Bangladesh', label: '🇧🇩 Bangladesh'),
              (key: '🇸🇦 Saudi', label: '🇸🇦 Saudi'),
              (key: '🇦🇪 UAE', label: '🇦🇪 UAE'),
              (key: 'Global', label: s.filterGlobal),
              (key: 'bKash', label: 'bKash'),
              (key: 'Nagad', label: 'Nagad'),
              (key: 'Bank', label: s.filterBank),
            ].map((filter) {
              final isSelected = _selectedFilter == filter.key;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ChoiceChip(
                  label: Text(filter.label),
                  selected: isSelected,
                  selectedColor: AppColors.royalBlue,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: isSelected ? AppColors.cloudDancer : AppColors.royalBlue,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: AppColors.royalBlue.withValues(alpha: isSelected ? 0 : 0.16),
                    ),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedFilter = filter.key);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Custom Instant Send banner if user is typing a new number
        if (_searchQuery.isNotEmpty)
          _buildQuickSendNewNumberBanner(),

        // Beneficiaries List
        Expanded(
          child: filtered.isEmpty && _searchQuery.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_search_rounded,
                        size: 48,
                        color: AppColors.royalBlue.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.noMatchingContact(_searchQuery),
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.sendDirectlyHint,
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => Divider(
                    color: AppColors.royalBlue.withValues(alpha: 0.08),
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildBeneficiaryTile(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQuickSendNewNumberBanner() {
    // If the input doesn't already contain dial code, format with selected country
    final rawNumber = _searchQuery.trim();
    final fullNumber = rawNumber.startsWith('+')
        ? rawNumber
        : '${_selectedCountry.dialCode} $rawNumber';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.royalBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.royalBlue.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.royalBlue,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.send_rounded, color: AppColors.cloudDancer, size: 18),
          ),
        ),
        title: Row(
          children: [
            Text(
              _selectedCountry.flag,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                AppStrings.of(context).sendDirectlyTo(fullNumber),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Remit to ${_selectedCountry.name} (${_selectedCountry.currencyCode})',
          style: TextStyle(
            color: AppColors.royalBlue.withValues(alpha: 0.65),
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppColors.royalBlue,
        ),
        onTap: () {
          final newRecipient = BeneficiaryModel(
            id: 'recipient_${DateTime.now().millisecondsSinceEpoch}',
            name: rawNumber,
            phoneOrAccount: fullNumber,
            providerType: _selectedCountry.providers.first,
            avatarUrl: '',
            initials: rawNumber.isNotEmpty ? rawNumber[0].toUpperCase() : 'U',
            countryCode: _selectedCountry.code,
            countryFlag: _selectedCountry.flag,
            countryName: _selectedCountry.name,
            countryDialCode: _selectedCountry.dialCode,
            currency: _selectedCountry.currencyCode,
            currencySymbol: _selectedCountry.currencySymbol,
          );
          widget.onSelectRecipient(newRecipient);
        },
      ),
    );
  }

  Widget _buildBeneficiaryTile(BeneficiaryModel item) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.royalBlue.withValues(alpha: 0.1),
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                item.initials,
                style: const TextStyle(
                  color: AppColors.royalBlue,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
          ),
          // Nationality Flag Symbol Badge
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.royalBlue.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              child: Text(
                item.countryFlag,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          Text(
            item.name,
            style: const TextStyle(
              color: AppColors.royalBlue,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${item.countryName})',
            style: TextStyle(
              color: AppColors.royalBlue.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppColors.royalBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.providerType,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            item.phoneOrAccount,
            style: TextStyle(
              color: AppColors.royalBlue.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: AppColors.royalBlue,
      ),
      onTap: () => widget.onSelectRecipient(item),
    );
  }

  void _showCountryPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: AppColors.cloudDancer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.royalBlue.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              AppStrings.of(context).selectDestinationCountry,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.separated(
                itemCount: CountryModel.supportedCountries.length,
                separatorBuilder: (context, index) => Divider(
                  color: AppColors.royalBlue.withValues(alpha: 0.08),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final c = CountryModel.supportedCountries[index];
                  final isSelected = c.code == _selectedCountry.code;

                  return ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        color: AppColors.royalBlue,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Currency: ${c.currencyCode} (${c.currencySymbol})',
                      style: TextStyle(
                        color: AppColors.royalBlue.withValues(alpha: 0.55),
                        fontSize: 11.5,
                      ),
                    ),
                    trailing: Text(
                      c.dialCode,
                      style: const TextStyle(
                        color: AppColors.royalBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () {
                      setState(() => _selectedCountry = c);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
