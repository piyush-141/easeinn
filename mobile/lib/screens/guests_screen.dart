import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/hotel_store.dart';
import '../models/guest.dart';
import '../theme/app_theme.dart';

class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key});

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  final _searchController = TextEditingController();
  String _filter = 'all'; // 'all', 'in_house', 'past'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showGuestProfile(BuildContext context, Guest guest) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.slateBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.brandPrimary,
                    child: Text(
                      guest.fullName.isNotEmpty ? guest.fullName.substring(0, 1) : 'G',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          guest.fullName,
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                        Text(
                          guest.phone,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.statusVacantBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded, color: AppTheme.statusVacant, size: 14),
                        SizedBox(width: 4),
                        Text('Verified', style: TextStyle(color: AppTheme.statusVacant, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Government ID Section
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.brandLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.brandPrimary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GOVERNMENT ID RECORD (${guest.idType.toUpperCase()})',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.brandPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      guest.idNumberMasked,
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.slateDark, letterSpacing: 1),
                    ),
                    if (guest.fatherName != null && guest.fatherName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Care of: ${guest.fatherName}', style: const TextStyle(fontSize: 11, color: AppTheme.slateMuted)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Details
              if (guest.address != null && guest.address!.isNotEmpty)
                _buildProfileDetailRow(Icons.home_outlined, 'Address', '${guest.address}${guest.pincode != null ? " - ${guest.pincode}" : ""}'),
              if (guest.dateOfBirth != null && guest.dateOfBirth!.isNotEmpty)
                _buildProfileDetailRow(Icons.calendar_today_outlined, 'DOB', guest.dateOfBirth!),
              if (guest.gender != null && guest.gender!.isNotEmpty)
                _buildProfileDetailRow(Icons.wc_outlined, 'Gender', guest.gender!),
              _buildProfileDetailRow(Icons.hotel_outlined, 'Total Stays', '${guest.staysCount} Stay(s) at EaseInn'),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.slateDark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close Profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.brandPrimary),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.slateDark)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HotelStore>();
    final activeGuestIds = store.activeStays.map((s) => s.guestId).toSet();

    final query = _searchController.text.trim().toLowerCase();
    final filtered = store.guests.where((g) {
      final matchesQuery = query.isEmpty ||
          g.fullName.toLowerCase().contains(query) ||
          g.phone.contains(query) ||
          g.idNumberMasked.toLowerCase().contains(query);

      final isInHouse = activeGuestIds.contains(g.id);

      if (_filter == 'in_house') return matchesQuery && isInHouse;
      if (_filter == 'past') return matchesQuery && !isInHouse;
      return matchesQuery;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Guest Directory & Verified ID Records',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.slateDark,
                ),
              ),
              Text(
                'Complete searchable database of registered guests and verified government IDs',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13, color: AppTheme.slateDark),
                decoration: InputDecoration(
                  hintText: 'Search by guest name, phone, or masked ID...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppTheme.slateMuted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.slateBorder)),
                ),
              ),
              const SizedBox(height: 10),

              // Filter Chips
              Row(
                children: [
                  _buildChip('all', 'All (${store.guests.length})'),
                  const SizedBox(width: 8),
                  _buildChip('in_house', 'In-House (${activeGuestIds.length})'),
                  const SizedBox(width: 8),
                  _buildChip('past', 'Past Guests'),
                ],
              ),
              const SizedBox(height: 14),

              // Guest Cards List
              if (filtered.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.slateBorder)),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.people_outline_rounded, size: 40, color: AppTheme.slateMuted),
                        const SizedBox(height: 8),
                        Text(
                          store.guests.isEmpty ? 'No Guests Registered Yet' : 'No matching guests found',
                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                        ),
                        Text(
                          store.guests.isEmpty ? 'Complete a check-in to auto-save guest profiles.' : 'Try adjusting your search query.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final guest = filtered[index];
                    final isInHouse = activeGuestIds.contains(guest.id);

                    return InkWell(
                      onTap: () => _showGuestProfile(context, guest),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.slateBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppTheme.brandPrimary.withValues(alpha: 0.12),
                              child: Text(
                                guest.fullName.isNotEmpty ? guest.fullName.substring(0, 1) : 'G',
                                style: const TextStyle(color: AppTheme.brandPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          guest.fullName,
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.slateDark),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isInHouse) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(color: AppTheme.statusOccupiedBg, borderRadius: BorderRadius.circular(6)),
                                          child: const Text('In-House', style: TextStyle(color: AppTheme.statusOccupied, fontSize: 8, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${guest.idType.toUpperCase()}: ${guest.idNumberMasked} • ${guest.phone}',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.slateMuted),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: AppTheme.slateMuted, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String id, String label) {
    final isSel = _filter == id;
    return InkWell(
      onTap: () => setState(() => _filter = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? AppTheme.brandPrimary : AppTheme.slateBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSel ? Colors.white : AppTheme.slateDark,
          ),
        ),
      ),
    );
  }
}
