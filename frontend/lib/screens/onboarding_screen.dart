import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/storage_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/glassmorphic_container.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final StorageService _storage = StorageService();
  int _currentPage = 0;

  final List<OnboardingItem> _slides = [
    OnboardingItem(
      title: "No Accounts",
      description: "No phone numbers, no emails, no registration. Communicate instantly with complete anonymity.",
      icon: Icons.person_off_outlined,
      color: AppColors.primary,
    ),
    OnboardingItem(
      title: "Encrypted Rooms",
      description: "Every room utilizes peer-to-peer ephemeral key exchanges (X25519) and military-grade ChaCha20-Poly1305 encryption.",
      icon: Icons.vpn_key_outlined,
      color: AppColors.secondary,
    ),
    OnboardingItem(
      title: "Permanent Privacy",
      description: "Messages are stored locally only. Shred and destroy the room permanently at any time to wipe all local records.",
      icon: Icons.delete_forever_outlined,
      color: AppColors.accent,
    ),
  ];

  Future<void> _completeOnboarding() async {
    await _storage.setOnboardingComplete(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background glowing circles
          Positioned(
            top: 100,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _slides[_currentPage].color.withOpacity(0.06),
                    blurRadius: 100,
                  )
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Top bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "ENCLINE",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      TextButton(
                        onPressed: _completeOnboarding,
                        child: const Text("Skip", style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                  
                  // Slider
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        final item = _slides[index];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GlassmorphicContainer(
                              padding: const EdgeInsets.all(32),
                              backgroundOpacity: 0.03,
                              borderRadius: 24,
                              child: Icon(
                                item.icon,
                                size: 84,
                                color: item.color,
                              ),
                            ),
                            const SizedBox(height: 48),
                            Text(
                              item.title,
                              style: Theme.of(context).textTheme.headlineLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              item.description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF94A3B8),
                                height: 1.5,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  // Bottom controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Dots
                      Row(
                        children: List.generate(
                          _slides.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 6),
                            width: _currentPage == index ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: _currentPage == index
                                  ? _slides[_currentPage].color
                                  : Colors.white24,
                            ),
                          ),
                        ),
                      ),
                      
                      // Button
                      GradientButton(
                        text: _currentPage == _slides.length - 1 ? "Get Started" : "Next",
                        onPressed: () {
                          if (_currentPage < _slides.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _completeOnboarding();
                          }
                        },
                        gradient: LinearGradient(
                          colors: [
                            _slides[_currentPage].color,
                            _slides[_currentPage].color.withOpacity(0.6),
                          ],
                        ),
                        glow: [
                          BoxShadow(
                            color: _slides[_currentPage].color.withOpacity(0.25),
                            blurRadius: 16,
                            spreadRadius: -2,
                          )
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingItem {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  OnboardingItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
