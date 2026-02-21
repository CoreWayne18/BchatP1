// lib/screens/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../theme.dart';
import 'setup_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl        = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _inputFocus  = FocusNode();
  bool _showFpDialog = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await context.read<ChatProvider>().sendMessage(text);
    _scrollToBottom();
  }

  Future<void> _doHandshake() async {
    await context.read<ChatProvider>().sendHandshakeInit();
  }

  void _showFingerprint() => setState(() => _showFpDialog = true);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    _scrollToBottom();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () async {
            await provider.disconnect();
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const SetupScreen()),
              (_) => false,
            );
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: provider.connected
                    ? kGreen
                    : provider.btReady ? kAmber : kRed,
                boxShadow: provider.connected
                    ? [const BoxShadow(color: kGreen, blurRadius: 6)]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            const Text('B-CHAT'),
          ],
        ),
        actions: [
          // Encryption badge
          GestureDetector(
            onTap: _showFingerprint,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: provider.encrypted ? kCyan : kGreenDark,
                ),
                borderRadius: BorderRadius.circular(20),
                color: provider.encrypted
                    ? const Color(0x1000FFCC)
                    : Colors.transparent,
              ),
              child: Text(
                provider.encrypted ? '🔐 E2E' : '⚠ PLAIN',
                style: TextStyle(
                  color: provider.encrypted ? kCyan : kTextDim,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: kBg2,
            icon: const Icon(Icons.more_vert, color: kGreenDim, size: 18),
            onSelected: (v) async {
              switch (v) {
                case 'handshake': await _doHandshake(); break;
                case 'ping': await provider.sendPing(); break;
                case 'clear': await provider.clearMessages(); break;
                case 'fp': _showFingerprint(); break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'handshake',
                  child: Text('🔑 Send Key Exchange', style: TextStyle(color: kGreen, fontSize: 13))),
              PopupMenuItem(value: 'ping',
                  child: Text('↩ Ping Peer', style: TextStyle(color: kGreen, fontSize: 13))),
              PopupMenuItem(value: 'fp',
                  child: Text('🔏 My Fingerprint', style: TextStyle(color: kGreen, fontSize: 13))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'clear',
                  child: Text('🗑 Clear History', style: TextStyle(color: kRed, fontSize: 13))),
            ],
          ),
        ],
      ),

      body: Stack(
        children: [
          Column(
            children: [
              // Info bar
              _InfoBar(provider: provider),

              // Messages
              Expanded(
                child: provider.messages.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: provider.messages.length,
                        itemBuilder: (_, i) =>
                            _MessageTile(msg: provider.messages[i]),
                      ),
              ),

              // Input bar
              _InputBar(
                ctrl: _ctrl,
                focus: _inputFocus,
                onSend: _send,
                enabled: provider.btReady,
              ),
            ],
          ),

          // Fingerprint overlay
          if (_showFpDialog)
            _FingerprintOverlay(
              fingerprint: provider.fingerprint,
              onClose: () => setState(() => _showFpDialog = false),
            ),
        ],
      ),
    );
  }
}

// ─── Info bar ───────────────────────────────────────────────────────────

class _InfoBar extends StatelessWidget {
  final ChatProvider provider;
  const _InfoBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final String statusText;
    if (provider.connected) {
      statusText = 'CONNECTED TO ${provider.peerName.toUpperCase()}';
    } else if (provider.btReady) {
      final role = provider.ble.role;
      statusText = role == BleRole.peripheral
          ? 'ADVERTISING — WAITING FOR PEER…'
          : 'SCANNING FOR HOST…';
    } else {
      statusText = 'BLUETOOTH NOT STARTED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const BoxDecoration(
        color: kBg2,
        border: Border(bottom: BorderSide(color: kGreenDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(
                  color: kGreenDim, fontSize: 10, letterSpacing: 2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            provider.ble.role == BleRole.peripheral
                ? 'HOST'
                : provider.ble.role == BleRole.central ? 'PEER' : '',
            style: const TextStyle(
                color: kGreenDark, fontSize: 9, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

// ─── Message tile ────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final Message msg;
  const _MessageTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    if (msg.type == MessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Text('▸ ', style: TextStyle(color: kGreenDark, fontSize: 11)),
            Expanded(
              child: Text(
                msg.text,
                style: const TextStyle(
                    color: kGreenDark, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.type == MessageType.error) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          '✗ ${msg.text}',
          style: const TextStyle(color: kRed, fontSize: 11),
        ),
      );
    }

    // Chat bubble
    final mine = msg.isMine;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            _Avatar(name: msg.sender),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF003309) : kBg2,
                border: Border.all(
                  color: mine ? const Color(0xFF00661A) : kGreenDark,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(10),
                  topRight: const Radius.circular(10),
                  bottomLeft: Radius.circular(mine ? 10 : 2),
                  bottomRight: Radius.circular(mine ? 2 : 10),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: const TextStyle(
                        color: Color(0xFFC8FFD0), fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.isEncrypted ? '🔒' : '⚠',
                        style: const TextStyle(fontSize: 9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _time(msg.timestamp),
                        style: const TextStyle(
                            color: kTextDim, fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            _Avatar(name: msg.sender),
          ],
        ],
      ),
    );
  }

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kGreenDark),
        color: kBg2,
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(color: kGreenDim, fontSize: 12),
      ),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('📡', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text(
            'NO MESSAGES YET',
            style: TextStyle(color: kGreenDark, letterSpacing: 4, fontSize: 12),
          ),
          SizedBox(height: 8),
          Text(
            'Waiting for peer to connect…',
            style: TextStyle(color: kTextDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Input bar ───────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode focus;
  final VoidCallback onSend;
  final bool enabled;

  const _InputBar({
    required this.ctrl,
    required this.focus,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: kBg2,
        border: Border(top: BorderSide(color: kGreenDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              focusNode: focus,
              enabled: enabled,
              style: const TextStyle(color: kGreen, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'type message…',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              onSubmitted: enabled ? (_) => onSend() : null,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44, height: 44,
            child: ElevatedButton(
              onPressed: enabled ? onSend : null,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Icon(Icons.send, size: 18, color: kGreen),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Fingerprint overlay ─────────────────────────────────────────────────

class _FingerprintOverlay extends StatelessWidget {
  final String fingerprint;
  final VoidCallback onClose;

  const _FingerprintOverlay({
    required this.fingerprint,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {}, // prevent closing when tapping card
          child: Container(
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF050F05),
              border: Border.all(color: kGreenDim),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: kGreen, blurRadius: 20, spreadRadius: -6),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🔐 MY FINGERPRINT',
                  style: TextStyle(
                      color: kCyan, fontSize: 14, letterSpacing: 3),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kBg,
                    border: Border.all(color: kGreenDark),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    fingerprint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kGreen,
                      fontSize: 13,
                      letterSpacing: 2,
                      height: 1.8,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Read this aloud to your peer.\nIf they see the same string, your connection is secure.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kGreenDim, fontSize: 11, height: 1.6),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: fingerprint));
                          onClose();
                        },
                        child: const Text('COPY'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onClose,
                        child: const Text('CLOSE'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
