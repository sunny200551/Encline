import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/room_session_controller.dart';
import '../core/storage_service.dart';
import 'onboarding_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack)),
    );

    _controller.forward();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // Fire off the pre-warm call to wake the Render server early on app start
    final defaultServer = await _storage.getDefaultServerUrl();
    if (mounted) {
      Provider.of<RoomSessionController>(context, listen: false).preWarmServer(defaultServer);
    }

    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;

    final onboardingComplete = await _storage.isOnboardingComplete();
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => 
            onboardingComplete ? const HomeScreen() : const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background subtle cyber glow
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.08),
                    blurRadius: 100,
                  )
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.05),
                    blurRadius: 120,
                  )
                ],
              ),
            ),
          ),
          
          // Main content
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Shield cyber Logo
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: AppColors.primaryGradient,
                            boxShadow: AppGlow.primaryGlow,
                          ),
                          child: const Icon(
                            Icons.security,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // App title
                        Text(
                          "ENCLINE",
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: AppColors.secondary,
                                offset: const Offset(0, 0),
                                blurRadius: 12,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        // Tagline
                        Text(
                          "Temporary Rooms. Permanent Privacy.",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
