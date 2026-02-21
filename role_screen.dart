// lib/screens/role_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../theme.dart';
import 'chat_screen.dart';

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});
  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  bool _loading = false;

  Future<void> _pick(bool isHost) async {
    setState(() => _loading = true);

    final provider = context.read<ChatProvider>();

    final granted = await provider.requestPermissions();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions required'),
            backgroundColor: kRed,
          ),
        );
      }
      setState(() => _loading = false);
      return;
    }

    if (isHost) {
      await provider.becomePeripheral();
    } else {
      await provider.becomeCentral();
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChatScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('B-CHAT')),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kGreen),
                  SizedBox(height: 20),
                  Text('INITIALIZING BLUETOOTH…',
                      style: TextStyle(color: kGreenDim, letterSpacing: 3)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Identity card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kBg2,
                      border: Border.all(color: kGreenDark),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('IDENTITY',
                            style: TextStyle(
                                color: kTextDim, fontSize: 9, letterSpacing: 4)),
                        const SizedBox(height: 6),
                        Text(provider.username,
                            style: const TextStyle(color: kCyan, fontSize: 18)),
                        const SizedBox(height: 6),
                        Text(
                          provider.fingerprint,
                          style: const TextStyle(
                              color: kTextDim, fontSize: 9, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    'SELECT ROLE',
                    style: TextStyle(
                        color: kGreenDim, fontSize: 11, letterSpacing: 5),
                  ),
                  const SizedBox(height: 20),

                  // HOST
                  _RoleCard(
                    icon: '📡',
                    title: 'HOST',
                    subtitle: 'Advertise as BLE peripheral.\nOther device scans and connects to you.',
                    onTap: () => _pick(true),
                  ),
                  const SizedBox(height: 14),

                  // JOIN
                  _RoleCard(
                    icon: '🔍',
                    title: 'JOIN',
                    subtitle: 'Scan for a nearby BChat host.\nConnect to their BLE peripheral.',
                    onTap: () => _pick(false),
                  ),

                  const Spacer(),
                  const Text(
                    'ONE DEVICE MUST HOST, THE OTHER JOINS.\nBOTH USE THE SAME APP.',
                    style: TextStyle(
                        color: kTextDim, fontSize: 9, letterSpacing: 2,
                        height: 1.8),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kBg2,
          border: Border.all(color: kGreenDark),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: kGreen,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: kGreenDim, fontSize: 11, height: 1.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: kGreenDark),
          ],
        ),
      ),
    );
  }
}
