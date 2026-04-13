import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

Future<List<String>> _getRegisteredEmails() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('registered_emails') ?? <String>[];
}

Future<void> _registerEmail(String email) async {
  final prefs = await SharedPreferences.getInstance();
  final emails = await _getRegisteredEmails();
  final normalizedEmail = email.toLowerCase();
  if (!emails.contains(normalizedEmail)) {
    emails.add(normalizedEmail);
    await prefs.setStringList('registered_emails', emails);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  runApp(const PasswordGeneratorApp());
}

enum AppScreen { auth, otp, dashboard }

class PasswordGeneratorApp extends StatelessWidget {
  const PasswordGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SECUREPASS',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF8B5CF6),
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1F3A),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4F46E5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFF1A1F3A),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
        ),
      ),
      home: const PasswordVaultPage(),
    );
  }
}

class PasswordEntry {
  final String id;
  String title;
  String username;
  String encryptedPassword;

  PasswordEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.encryptedPassword,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'encryptedPassword': encryptedPassword,
      };

  static PasswordEntry fromJson(Map<String, dynamic> json) {
    return PasswordEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      username: json['username'] as String,
      encryptedPassword: json['encryptedPassword'] as String,
    );
  }
}

class PasswordVaultPage extends StatefulWidget {
  const PasswordVaultPage({super.key});

  @override
  State<PasswordVaultPage> createState() => _PasswordVaultPageState();
}

class _PasswordVaultPageState extends State<PasswordVaultPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  AppScreen _screen = AppScreen.auth;
  String _activeEmail = '';
  String _pendingOtp = '';
  DateTime? _otpExpiresAt;
  String _statusMessage = '';
  Timer? _otpTimer;
  Timer? _autoLogoutTimer;
  int _otpCountdown = 0;
  int _resendCountdown = 0;
  bool _showPasswords = false;
  bool _showGeneratedPassword = true;
  String _generatedPassword = '';
  int _passwordLength = 16;
  bool _includeUppercase = true;
  bool _includeLowercase = true;
  bool _includeNumbers = true;
  bool _includeSpecialChars = true;

  List<PasswordEntry> _entries = [];
  bool _firebaseEnabled = false;

  @override
  void initState() {
    super.initState();
    _ensureFirebaseAvailability();
  }

  Future<void> _ensureFirebaseAvailability() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      setState(() {
        _firebaseEnabled = true;
      });
    } catch (e) {
      debugPrint('Firebase unavailable: $e');
    }
  }

  @override
  void dispose() {
    _autoLogoutTimer?.cancel();
    _otpTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _generateOtp(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(10).toString()).join();
  }

  String _generatePassword() {
    const uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const lowercase = 'abcdefghijklmnopqrstuvwxyz';
    const numbers = '0123456789';
    const specialChars = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    String chars = '';
    if (_includeLowercase) chars += lowercase;
    if (_includeUppercase) chars += uppercase;
    if (_includeNumbers) chars += numbers;
    if (_includeSpecialChars) chars += specialChars;

    if (chars.isEmpty) {
      chars = lowercase;
    }

    final random = Random.secure();
    final password = StringBuffer();
    for (int i = 0; i < _passwordLength; i++) {
      password.write(chars[random.nextInt(chars.length)]);
    }

    return password.toString();
  }

  void _resetAutoLogoutTimer() {
    _autoLogoutTimer?.cancel();
    if (_screen != AppScreen.dashboard) return;
    _autoLogoutTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out due to inactivity')),
        );
        setState(() {
          _screen = AppScreen.auth;
          _activeEmail = '';
          _entries = [];
          _statusMessage = '';
        });
      }
    });
  }

  Future<SharedPreferences> _prefs() async {
    return SharedPreferences.getInstance();
  }

  String _normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r"^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z\d\-.]+");
    return regex.hasMatch(email);
  }

  String _encryptionKey(String email) {
    final salt = 'passwordless-vault-salt';
    final digest = sha256.convert(utf8.encode('$email|$salt')).bytes;
    return base64Url.encode(digest).substring(0, 32);
  }

  String _encryptPassword(String password, String email) {
    final key = encrypt.Key.fromUtf8(_encryptionKey(email));
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(password, iv: iv);
    final bytes = iv.bytes + encrypted.bytes;
    return base64UrlEncode(bytes);
  }

  String _decryptPassword(String cipherText, String email) {
    try {
      final data = base64Url.decode(cipherText);
      final iv = encrypt.IV(data.sublist(0, 16));
      final encryptedBytes = data.sublist(16);
      final key = encrypt.Key.fromUtf8(_encryptionKey(email));
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      final decrypted = encrypter.decrypt(encrypt.Encrypted(Uint8List.fromList(encryptedBytes)), iv: iv);
      return decrypted;
    } catch (_) {
      return '••••••••';
    }
  }

  Future<void> _saveEntriesLocally() async {
    final prefs = await _prefs();
    final storeText = prefs.getString('vault_store');
    final store = storeText == null ? <String, dynamic>{} : jsonDecode(storeText) as Map<String, dynamic>;
    final encryptedEntries = _entries.map((entry) => entry.toJson()).toList(growable: false);
    store[_activeEmail] = {'entries': encryptedEntries};
    await prefs.setString('vault_store', jsonEncode(store));
  }

  Future<void> _saveEntriesToFirebase() async {
    try {
      final entriesJson = _entries.map((entry) => entry.toJson()).toList(growable: false);
      await FirebaseFirestore.instance.collection('vault').doc(_activeEmail).set(
        {
          'entries': entriesJson,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
    } catch (e) {
      debugPrint('Failed to save entries to Firebase: $e');
    }
  }

  Future<void> _saveEntries() async {
    await _saveEntriesLocally();
    if (_firebaseEnabled) {
      await _saveEntriesToFirebase();
    }
  }

  Future<void> _loadUserDataLocally(String email) async {
    final prefs = await _prefs();
    final storeText = prefs.getString('vault_store');
    final store = storeText == null ? <String, dynamic>{} : jsonDecode(storeText) as Map<String, dynamic>;
    final userData = store[email] as Map<String, dynamic>?;
    if (userData == null) {
      _entries = [];
      store[email] = {'entries': []};
      await prefs.setString('vault_store', jsonEncode(store));
      return;
    }

    final rawEntries = (userData['entries'] as List<dynamic>).cast<Map<String, dynamic>>();
    _entries = rawEntries.map((raw) => PasswordEntry.fromJson(raw)).toList(growable: true);
  }

  Future<void> _loadUserData(String email) async {
    _entries = [];
    if (_firebaseEnabled) {
      try {
        final snapshot = await FirebaseFirestore.instance.collection('vault').doc(email).get();
        if (snapshot.exists) {
          final data = snapshot.data();
          final rawEntries = (data?['entries'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          _entries = rawEntries.map((raw) => PasswordEntry.fromJson(raw)).toList(growable: true);
          if (_entries.isNotEmpty) {
            await _saveEntriesLocally();
            return;
          }
        }
      } catch (e) {
        debugPrint('Failed to load entries from Firebase: $e');
      }
    }
    await _loadUserDataLocally(email);
  }

  Future<void> _sendOtp() async {
    final email = _normalizeEmail(_emailController.text);
    if (email.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an email address.';
      });
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() {
        _statusMessage = 'Please enter a valid email address.';
      });
      return;
    }

    await _registerEmail(email);

    final otp = _generateOtp(6);
    _pendingOtp = otp;
    _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));
    _otpCountdown = 180;
    _resendCountdown = 30;
    await _saveOtpData(email, otp, _otpExpiresAt!);
    _startOtpTimer();

    setState(() {
      _screen = AppScreen.otp;
      _statusMessage = 'OTP sent to $email. Enter it below to continue.';
      _activeEmail = email;
    });

    if (kDebugMode) {
      debugPrint('DEBUG OTP FOR $email: $otp');
    }
  }

  Future<void> _verifyOtp() async {
    final submitted = _otpController.text.trim();
    if (submitted.isEmpty) {
      setState(() {
        _statusMessage = 'Enter the OTP sent to your email.';
      });
      return;
    }

    if (_pendingOtp.isEmpty || _otpExpiresAt == null) {
      await _loadOtpDataForActiveEmail();
    }

    final now = DateTime.now();
    if (_pendingOtp.isEmpty || _otpExpiresAt == null || now.isAfter(_otpExpiresAt!)) {
      setState(() {
        _statusMessage = 'OTP expired. Resend to get a new code.';
      });
      return;
    }
    if (submitted != _pendingOtp) {
      setState(() {
        _statusMessage = 'Invalid OTP. Please try again.';
      });
      return;
    }

    _pendingOtp = '';
    await _loginUser(_activeEmail);
  }

  Future<void> _saveOtpData(String email, String otp, DateTime expiresAt) async {
    final prefs = await _prefs();
    await prefs.setString('pending_otp_email', email);
    await prefs.setString('pending_otp_code', otp);
    await prefs.setInt('pending_otp_expires_at', expiresAt.millisecondsSinceEpoch);
  }

  Future<void> _loadOtpDataForActiveEmail() async {
    final prefs = await _prefs();
    final storedEmail = prefs.getString('pending_otp_email');
    if (storedEmail != _activeEmail) {
      return;
    }

    final storedOtp = prefs.getString('pending_otp_code');
    final expiryMs = prefs.getInt('pending_otp_expires_at');
    if (storedOtp != null && expiryMs != null) {
      _pendingOtp = storedOtp;
      _otpExpiresAt = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      _otpCountdown = max(0, _otpExpiresAt!.difference(DateTime.now()).inSeconds);
    }
  }

  Future<void> _loginUser(String email) async {
    await _loadUserData(email);
    setState(() {
      _screen = AppScreen.dashboard;
      _statusMessage = 'Welcome, $email';
      _otpController.clear();
      _searchController.clear();
      _showPasswords = false;
    });
    _resetAutoLogoutTimer();
    // Show welcome back message for existing users with data
    if (_entries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Welcome back! ${_entries.length} password${_entries.length == 1 ? '' : 's'} loaded.'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;
    if (_activeEmail.isEmpty) {
      setState(() {
        _statusMessage = 'Enter your email first to resend the OTP.';
      });
      return;
    }
    await _sendOtp();
    setState(() {
      _statusMessage = 'OTP resent to $_activeEmail.';
    });
  }

  void _startOtpTimer() {
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_otpCountdown > 0) _otpCountdown--;
        if (_resendCountdown > 0) _resendCountdown--;
      });
    });
  }

  void _signOut() {
    _otpTimer?.cancel();
    _autoLogoutTimer?.cancel();
    setState(() {
      _screen = AppScreen.auth;
      _activeEmail = '';
      _entries = [];
      _statusMessage = 'Signed out successfully.';
    });
  }

  List<PasswordEntry> get _filteredEntries {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries.where((entry) {
      return entry.title.toLowerCase().contains(query) || entry.username.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showEntrySheet([PasswordEntry? existing, String? generatedPassword]) async {
    _resetAutoLogoutTimer();
    final titleController = TextEditingController(text: existing?.title ?? '');
    final usernameController = TextEditingController(text: existing?.username ?? '');
    final passwordController = TextEditingController(text: generatedPassword ?? (existing == null ? '' : _decryptPassword(existing.encryptedPassword, _activeEmail)));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1F3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        bool showPassword = generatedPassword != null && generatedPassword.isNotEmpty;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing == null ? 'Add New Entry' : 'Edit Entry', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Title',
                      labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
                      prefixIcon: const Icon(Icons.label, color: Color(0xFFA78BFA)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username / Email / ID',
                      labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
                      prefixIcon: const Icon(Icons.person, color: Color(0xFFA78BFA)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: passwordController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
                            prefixIcon: const Icon(Icons.lock, color: Color(0xFFA78BFA)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                showPassword ? Icons.visibility_off : Icons.visibility,
                                color: const Color(0xFFA78BFA),
                              ),
                              onPressed: () {
                                setModalState(() {
                                  showPassword = !showPassword;
                                });
                              },
                            ),
                          ),
                          obscureText: !showPassword,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 28),
                        onPressed: () {
                          final generated = _generatePassword();
                          passwordController.text = generated;
                          setModalState(() {
                            showPassword = true;
                          });
                        },
                        tooltip: 'Generate Password',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        final username = usernameController.text.trim();
                        final password = passwordController.text.trim();
                        if (title.isEmpty || username.isEmpty || password.isEmpty) {
                          return;
                        }
                        final encrypted = _encryptPassword(password, _activeEmail);
                        if (existing == null) {
                          final entry = PasswordEntry(
                            id: Uuid().v4(),
                            title: title,
                            username: username,
                            encryptedPassword: encrypted,
                          );
                          setState(() {
                            _entries.insert(0, entry);
                          });
                        } else {
                          setState(() {
                            existing.title = title;
                            existing.username = username;
                            existing.encryptedPassword = encrypted;
                          });
                        }
                        final navigator = Navigator.of(context);
                        await _saveEntries();
                        if (!mounted) return;
                        navigator.pop();
                      },
                      child: Text(existing == null ? 'Save Entry' : 'Update Entry', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteEntry(String id) async {
    _resetAutoLogoutTimer();
    setState(() {
      _entries.removeWhere((entry) => entry.id == id);
    });
    await _saveEntries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted')));
    }
  }

  Future<void> _copyToClipboard(String value, String label) async {
    _resetAutoLogoutTimer();
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _screen == AppScreen.dashboard ? 'SECUREPASS' : 'Secure Passwordless Login',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        centerTitle: true,
        actions: _screen == AppScreen.dashboard
            ? [
                IconButton(
                  icon: const Icon(Icons.logout, color: Color(0xFFA78BFA)),
                  onPressed: _signOut,
                  tooltip: 'Sign Out',
                ),
              ]
            : null,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0E27), Color(0xFF16213E)],
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildBody(context),
        ),
      ),
      floatingActionButton: _screen == AppScreen.dashboard
          ? FloatingActionButton(
              onPressed: () => _showEntrySheet(),
              backgroundColor: const Color(0xFF8B5CF6),
              elevation: 8,
              tooltip: 'Add New Entry',
              child: const Icon(Icons.add, size: 28),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_screen) {
      case AppScreen.auth:
        return _buildAuthScreen();
      case AppScreen.otp:
        return _buildOtpScreen();
      case AppScreen.dashboard:
        return _buildDashboard(context);
    }
  }

  Widget _buildAuthScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.vertical - 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1F2937), Color(0xFF111827)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withAlpha(51),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    children: [
                      const Icon(Icons.security, size: 48, color: Color(0xFF8B5CF6)),
                      const SizedBox(height: 16),
                      const Text('SECUREPASS', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text('Secure Passwordless Login', style: TextStyle(fontSize: 14, color: Color(0xFFA78BFA))),
                      const SizedBox(height: 24),
                      const Text('Enter your email to receive a one-time login code.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Email address',
                          labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
                          prefixIcon: const Icon(Icons.email, color: Color(0xFFA78BFA)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                          ),
                          onPressed: _sendOtp,
                          child: const Text('Send OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(51),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withAlpha(128)),
                          ),
                          child: Text(_statusMessage, style: const TextStyle(color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                      if (kDebugMode && _pendingOtp.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withAlpha(51),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withAlpha(128)),
                          ),
                          child: Column(
                            children: [
                              const Text('TEST MODE - OTP Generated:', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              SelectableText(
                                _pendingOtp,
                                style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontFamily: 'Courier'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.vertical - 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1F2937), Color(0xFF111827)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withAlpha(51),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    children: [
                      const Icon(Icons.verified_user, size: 48, color: Color(0xFF8B5CF6)),
                      const SizedBox(height: 16),
                      const Text('Enter OTP', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('A one-time code has been sent to', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                      Text(_activeEmail.isNotEmpty ? _activeEmail : 'your email', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 4),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'Enter 6-digit OTP',
                          labelStyle: const TextStyle(color: Color(0xFFA78BFA)),
                          prefixIcon: const Icon(Icons.link, color: Color(0xFFA78BFA)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Expires in', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(_formatDuration(_otpCountdown), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFCA5A5))),
                            ],
                          ),
                          Container(width: 1, height: 40, color: Colors.white10),
                          Column(
                            children: [
                              const Text('Resend in', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              Text(_formatDuration(_resendCountdown), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 8,
                          ),
                          onPressed: _verifyOtp,
                          child: const Text('Verify OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _resendCountdown == 0 ? _resendOtp : null,
                        child: const Text('Resend OTP', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _screen = AppScreen.auth;
                            _otpController.clear();
                            _statusMessage = '';
                            _otpTimer?.cancel();
                          });
                        },
                        child: const Text('Back to Email', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.normal)),
                      ),
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(51),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withAlpha(128)),
                          ),
                          child: Text(_statusMessage, style: const TextStyle(color: Colors.orange, fontSize: 13)),
                        ),
                      ],
                      if (_pendingOtp.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(38),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('A one-time code was generated. Enter it above to continue.', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final entries = _filteredEntries;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Password Generator Card - TOP
            _buildPasswordGeneratorCard(),
            const SizedBox(height: 16),
            // Search and Welcome Section
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(77),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome, ${_activeEmail.split('@')[0]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                    const SizedBox(height: 4),
                    const Text('Your vault is secure and synced', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search passwords...',
                        hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFA78BFA)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFFA78BFA)),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withAlpha(51),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${entries.length} saved', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(
                            _showPasswords ? Icons.visibility_off : Icons.visibility,
                            color: const Color(0xFF8B5CF6),
                            size: 24,
                          ),
                          onPressed: () {
                            setState(() {
                              _showPasswords = !_showPasswords;
                            });
                          },
                          tooltip: _showPasswords ? 'Hide passwords' : 'Show passwords',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 64, color: Colors.white30),
                        const SizedBox(height: 16),
                        Text(
                          'No saved passwords yet',
                          style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add your first account',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: List.generate(entries.length, (index) {
                      final entry = entries[index];
                      final password = _decryptPassword(entry.encryptedPassword, _activeEmail);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1F3A),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(51),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(entry.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, color: Color(0xFFA78BFA)),
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                      ],
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showEntrySheet(entry);
                                        } else if (value == 'delete') {
                                          _deleteEntry(entry.id);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(entry.username, style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 14)),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(77),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _showPasswords ? password : '••••••••••••',
                                          style: const TextStyle(letterSpacing: 2.0, color: Colors.white, fontFamily: 'Courier'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 22, color: Color(0xFF8B5CF6)),
                                      onPressed: () => _copyToClipboard(password, 'Password'),
                                      tooltip: 'Copy password',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _buildPasswordGeneratorCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D1B69), Color(0xFF1A0F3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withAlpha(77),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ExpansionTile(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 24),
            SizedBox(width: 12),
            Text('Password Generator', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        collapsedTextColor: Colors.white,
        textColor: Colors.white,
        collapsedIconColor: const Color(0xFF8B5CF6),
        iconColor: const Color(0xFF8B5CF6),
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Generated Password Display
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(77),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF8B5CF6).withAlpha(77)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _generatedPassword.isEmpty
                                ? 'Tap Generate to create a password'
                                : (_showGeneratedPassword ? _generatedPassword : '••••••••••••••••••••••'),
                            style: const TextStyle(fontSize: 14, letterSpacing: 1.0, color: Colors.white, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_generatedPassword.isNotEmpty) ...[
                          IconButton(
                            icon: Icon(
                              _showGeneratedPassword ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: const Color(0xFF8B5CF6),
                            ),
                            onPressed: () {
                              setState(() {
                                _showGeneratedPassword = !_showGeneratedPassword;
                              });
                            },
                            tooltip: _showGeneratedPassword ? 'Hide password' : 'Show password',
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20, color: Color(0xFF8B5CF6)),
                            onPressed: () => _copyToClipboard(_generatedPassword, 'Password'),
                            tooltip: 'Copy password',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password Length Slider
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Password Length', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withAlpha(51),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$_passwordLength', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Slider(
                        value: _passwordLength.toDouble(),
                        min: 8,
                        max: 32,
                        divisions: 24,
                        activeColor: const Color(0xFF8B5CF6),
                        inactiveColor: Colors.white.withAlpha(51),
                        onChanged: (value) {
                          setState(() {
                            _passwordLength = value.toInt();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Character Type Checkboxes
                  const Text('Character Types', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Uppercase (A-Z)', style: TextStyle(fontSize: 13, color: Colors.white)),
                    value: _includeUppercase,
                    activeColor: const Color(0xFF8B5CF6),
                    checkColor: Colors.white,
                    onChanged: (value) {
                      setState(() => _includeUppercase = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Lowercase (a-z)', style: TextStyle(fontSize: 13, color: Colors.white)),
                    value: _includeLowercase,
                    activeColor: const Color(0xFF8B5CF6),
                    checkColor: Colors.white,
                    onChanged: (value) {
                      setState(() => _includeLowercase = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Numbers (0-9)', style: TextStyle(fontSize: 13, color: Colors.white)),
                    value: _includeNumbers,
                    activeColor: const Color(0xFF8B5CF6),
                    checkColor: Colors.white,
                    onChanged: (value) {
                      setState(() => _includeNumbers = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('Special (!@#\$%^&*)', style: TextStyle(fontSize: 13, color: Colors.white)),
                    value: _includeSpecialChars,
                    activeColor: const Color(0xFF8B5CF6),
                    checkColor: Colors.white,
                    onChanged: (value) {
                      setState(() => _includeSpecialChars = value ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),

                  // Generate Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 6,
                      ),
                      icon: const Icon(Icons.refresh, size: 22),
                      label: const Text('Generate Password', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        setState(() {
                          _generatedPassword = _generatePassword();
                          _showGeneratedPassword = true;
                        });
                      },
                    ),
                  ),
                  if (_generatedPassword.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
                        ),
                        icon: const Icon(Icons.save, size: 22),
                        label: const Text('Save Generated Password', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        onPressed: () => _showEntrySheet(null, _generatedPassword),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Uuid {
  final Random _random = Random.secure();

  Uuid();

  String v4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .replaceRange(8, 8, '-')
        .replaceRange(13, 13, '-')
        .replaceRange(18, 18, '-')
        .replaceRange(23, 23, '-');
  }
}
