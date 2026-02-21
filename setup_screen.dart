// lib/screens/setup_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme.dart';
import 'role_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController(text: 'Operator_X');
  late AnimationController _flickerCtrl;
  late Animation<double> _flicker;

  @override
  void initState() {
    super.initState();
    _flickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _flicker = Tween<double>(begin: 1.0, end: 0.3).animate(_flickerCtrl);

    // Random flicker effect
    Future.delayed(const Duration(seconds: 2), _doFlicker);
  }

  void _doFlicker() async {
    if (!mounted) return;
    await _flickerCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 80));
    await _flickerCtrl.reverse();
    await Future.delayed(const Duration(seconds: 4));
    _doFlicker();
  }

  @override
  void dispose() {
    _flickerCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<ChatProvider>();
    await provider.init(name);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // Grid background
          CustomPaint(
            painter: _GridPainter(),
            size: MediaQuery.of(context).size,
          ),
          // Scanlines
          IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x08000000)],
                  stops: [0, 1],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  AnimatedBuilder(
                    animation: _flicker,
                    builder: (_, __) => Opacity(
                      opacity: _flicker.value,
                      child: const Text(
                        'BCHAT',
                        style: TextStyle(
                          color: kGreen,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 12,
                          shadows: [
                            Shadow(color: kGreen, blurRadius: 20),
                            Shadow(color: kGreen, blurRadius: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'OFFLINE · ENCRYPTED · BLUETOOTH',
                    style: TextStyle(
                      color: kTextDim,
                      fontSize: 10,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Input
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CODENAME',
                          style: TextStyle(
                            color: kTextDim,
                            fontSize: 10,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _ctrl,
                          textAlign: TextAlign.center,
                          maxLength: 20,
                          style: const TextStyle(
                            color: kGreen,
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: 'enter codename',
                          ),
                          onSubmitted: (_) => _init(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Init button
                  SizedBox(
                    width: 280,
                    child: ElevatedButton(
                      onPressed: _init,
                      child: const Text('INITIALIZE TERMINAL'),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Requirement note
                  const Text(
                    'Android 6.0+ · Bluetooth LE required',
                    style: TextStyle(color: kTextDim, fontSize: 10, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid background painter ────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x07003309)
      ..strokeWidth = 1;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
