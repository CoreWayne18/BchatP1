// lib/providers/chat_provider.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../services/ble_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

// ─── Packet types ────────────────────────────────────────────────────────
const _tHandshake    = 'hs';
const _tHandshakeAck = 'hs_ack';
const _tChat         = 'chat';
const _tPing         = 'ping';

class ChatProvider extends ChangeNotifier {
  final BleService     ble     = BleService();
  final CryptoService  crypto  = CryptoService();
  final StorageService storage = StorageService();

  final List<Message> messages = [];

  String  username    = '';
  String  peerName    = '';
  String  fingerprint = '';
  bool    encrypted   = false;
  bool    connected   = false;
  bool    btReady     = false;

  StreamSubscription? _dataSub;
  StreamSubscription? _statusSub;

  // ── Init ──────────────────────────────────────────────────────────────

  Future<void> init(String name) async {
    username = name;
    await crypto.init();
    fingerprint = crypto.fingerprint();

    // Load stored messages
    final stored = await storage.loadMessages();
    messages.addAll(stored);

    // BLE data stream
    _dataSub = ble.dataStream.listen(_onPacket);
    _statusSub = ble.statusStream.listen((msg) {
      addSystem(msg);
    });

    notifyListeners();
  }

  // ── BLE role start ─────────────────────────────────────────────────────

  Future<bool> requestPermissions() => ble.requestPermissions();

  Future<void> becomePeripheral() async {
    await ble.startPeripheral();
    btReady = true;
    notifyListeners();
  }

  Future<void> becomeCentral() async {
    await ble.startScan();
    btReady = true;
    notifyListeners();
  }

  // ── Packet handling ────────────────────────────────────────────────────

  void _onPacket(String raw) {
    Map<String, dynamic> pkt;
    try {
      pkt = jsonDecode(raw);
    } catch (_) {
      return;
    }

    final type = pkt['t'] as String?;
    switch (type) {
      case _tPing:
        addSystem('Ping from ${pkt['u'] ?? '?'}');
        break;

      case _tHandshake:
      case _tHandshakeAck:
        _handleHandshake(pkt);
        break;

      case _tChat:
        _handleChat(pkt);
        break;
    }
  }

  void _handleHandshake(Map<String, dynamic> pkt) {
    final pub  = pkt['pub'] as String?;
    final name = pkt['u']   as String? ?? 'peer';
    if (pub == null) return;

    peerName = name;
    try {
      crypto.deriveSharedKey(pub);
      encrypted = true;
      connected = true;
      addSystem('✓ Key exchange complete with $peerName. E2E encryption active.');
    } catch (e) {
      addSystem('Key exchange failed: $e');
    }

    // Reply with ack if this was the first hs (not ack)
    if (pkt['t'] == _tHandshake) {
      _sendHandshake(ack: true);
    }

    notifyListeners();
  }

  void _handleChat(Map<String, dynamic> pkt) {
    final sender = pkt['u'] as String? ?? peerName;
    String text;
    bool wasEncrypted = false;

    if (pkt['enc'] != null && crypto.hasSharedKey) {
      try {
        text = crypto.decrypt(pkt['enc'] as String);
        wasEncrypted = true;
      } catch (_) {
        text = '[DECRYPTION FAILED]';
      }
    } else {
      text = pkt['txt'] as String? ?? '';
    }

    final msg = Message(
      id: pkt['id'] as String? ?? const Uuid().v4(),
      text: text,
      sender: sender,
      timestamp: DateTime.now(),
      isMine: false,
      isEncrypted: wasEncrypted,
    );

    messages.add(msg);
    storage.saveMessage(msg);
    notifyListeners();
  }

  // ── Send ───────────────────────────────────────────────────────────────

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final id = const Uuid().v4();
    Map<String, dynamic> pkt;

    if (crypto.hasSharedKey) {
      final enc = crypto.encrypt(text);
      pkt = { 't': _tChat, 'id': id, 'u': username, 'enc': enc };
    } else {
      pkt = { 't': _tChat, 'id': id, 'u': username, 'txt': text };
    }

    await ble.send(jsonEncode(pkt));

    final msg = Message(
      id: id,
      text: text,
      sender: username,
      timestamp: DateTime.now(),
      isMine: true,
      isEncrypted: crypto.hasSharedKey,
    );
    messages.add(msg);
    storage.saveMessage(msg);
    notifyListeners();
  }

  Future<void> sendHandshakeInit() async {
    await _sendHandshake(ack: false);
    addSystem('Handshake sent. Waiting for peer…');
  }

  Future<void> _sendHandshake({required bool ack}) async {
    final pub = crypto.exportPublicKey();
    final pkt = {
      't': ack ? _tHandshakeAck : _tHandshake,
      'u': username,
      'pub': pub,
    };
    await ble.send(jsonEncode(pkt));
  }

  Future<void> sendPing() async {
    await ble.send(jsonEncode({ 't': _tPing, 'u': username }));
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void addSystem(String text) {
    messages.add(Message.system(text));
    notifyListeners();
  }

  Future<void> clearMessages() async {
    await storage.clearMessages();
    messages.removeWhere((m) => m.type == MessageType.chat);
    notifyListeners();
  }

  Future<void> disconnect() async {
    await ble.disconnect();
    connected = false;
    encrypted = false;
    btReady = false;
    peerName = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _statusSub?.cancel();
    ble.dispose();
    super.dispose();
  }
}
