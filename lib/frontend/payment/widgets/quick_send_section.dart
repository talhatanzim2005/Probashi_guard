import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart';
import '../models/beneficiary_model.dart';

class QuickSendSection extends StatelessWidget {
  final List<BeneficiaryModel> beneficiaries;
  final ValueChanged<BeneficiaryModel> onBeneficiaryTap;
  final VoidCallback onAddTap;

  const QuickSendSection({
    super.key,
    required this.beneficiaries,
    required this.onBeneficiaryTap,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.0),
          child: Text(
            'Quick send',
            style: TextStyle(
              color: AppColors.royalBlue,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Horizontal Avatar List
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: beneficiaries.length + 1,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Add New Beneficiary Button
                return _AddContactItem(onTap: onAddTap);
              }

              final contact = beneficiaries[index - 1];
              return _ContactAvatarItem(
                contact: contact,
                index: index - 1,
                onTap: () => onBeneficiaryTap(contact),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContactAvatarItem extends StatelessWidget {
  final BeneficiaryModel contact;
  final int index;
  final VoidCallback onTap;

  const _ContactAvatarItem({
    required this.contact,
    required this.index,
    required this.onTap,
  });

  // Soft palette accents for avatar rings strictly complementary
  static const List<Color> _accentColors = [
    AppColors.royalBlue,
    AppColors.emeraldGreen,
    Color(0xFF8A56AC),
    Color(0xFFE07A5F),
    Color(0xFF2A9D8F),
    Color(0xFF3D5A80),
  ];

  @override
  Widget build(BuildContext context) {
    final ringColor = _accentColors[index % _accentColors.length];

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Circular Avatar Container with Nationality Flag Badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringColor.withValues(alpha: 0.12),
                  border: Border.all(
                    color: ringColor.withValues(alpha: 0.4),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ringColor.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    contact.initials,
                    style: TextStyle(
                      color: ringColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
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
                    contact.countryFlag,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Contact Name
          SizedBox(
            width: 58,
            child: Text(
              contact.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.royalBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddContactItem extends StatelessWidget {
  final VoidCallback onTap;

  const _AddContactItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cloudDancer,
              border: Border.all(
                color: AppColors.royalBlue.withValues(alpha: 0.3),
                style: BorderStyle.solid,
                width: 1.4,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.add,
                color: AppColors.royalBlue,
                size: 22,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const SizedBox(
            width: 54,
            child: Text(
              'Add',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.royalBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
