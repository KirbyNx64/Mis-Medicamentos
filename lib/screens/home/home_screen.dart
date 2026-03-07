import 'package:flutter/material.dart';
import 'package:mis_medicamentos/db/local/medications_db.dart';
import 'package:mis_medicamentos/screens/home/home_app_bar.dart';
import 'package:mis_medicamentos/screens/home/home_progress_card.dart';
import 'package:mis_medicamentos/screens/home/home_upcoming_doses_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _dismissInfoBannerKey = 'home_info_banner_dismissed';
  int _progressRefreshToken = 0;
  int _upcomingRefreshToken = 0;
  bool _showInfoBanner = false;

  @override
  void initState() {
    super.initState();
    AppDatabase.instance.medicationsChangeToken.addListener(
      _onMedicationsChanged,
    );
    _loadInfoBannerState();
  }

  @override
  void dispose() {
    AppDatabase.instance.medicationsChangeToken.removeListener(
      _onMedicationsChanged,
    );
    super.dispose();
  }

  void _onMedicationsChanged() {
    if (!mounted) return;
    setState(() {
      _progressRefreshToken++;
      _upcomingRefreshToken++;
    });
  }

  Future<void> _refreshHome() async {
    setState(() {
      _progressRefreshToken++;
      _upcomingRefreshToken++;
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _loadInfoBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_dismissInfoBannerKey) ?? false;
    if (!mounted) return;
    setState(() {
      _showInfoBanner = !dismissed;
    });
  }

  Future<void> _dismissInfoBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dismissInfoBannerKey, true);
    if (!mounted) return;
    setState(() {
      _showInfoBanner = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HomeAppBar(),
      body: RefreshIndicator(
        onRefresh: _refreshHome,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              if (_showInfoBanner) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F1FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 30),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.info,
                              color: Color(0xFF2F80ED),
                              size: 32,
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Recuerda tomar tus medicamentos con agua y seguir las indicaciones de tu medico.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                  color: Color(0xFF38475F),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: -8,
                        right: -10,
                        child: IconButton(
                          onPressed: _dismissInfoBanner,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF6F819F),
                            size: 20,
                          ),
                          tooltip: 'Cerrar',
                          splashRadius: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              HomeProgressCard(refreshToken: _progressRefreshToken),
              const SizedBox(height: 22),
              HomeUpcomingDosesSection(
                refreshToken: _upcomingRefreshToken,
                onDoseMarked: () {
                  setState(() {
                    _progressRefreshToken++;
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
