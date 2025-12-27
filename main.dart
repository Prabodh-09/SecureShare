import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:local_auth/local_auth.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted data (no-op on web)
  await LocalStorageService.instance.loadAll();

  runApp(const SecureShareApp());
}

/// Root MaterialApp widget
class SecureShareApp extends StatelessWidget {
  const SecureShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureShare',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}


/// Simple user model for prototype
class AppUser {
  final String id;
  final String username;
  final String email;
  final String phone;

  bool biometricEnabled;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    this.biometricEnabled = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phone': phone,
      'biometricEnabled': biometricEnabled,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      id: map['id'] as String,
      username: map['username'] as String,
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      biometricEnabled: map['biometricEnabled'] as bool? ?? false,
    );
  }
}


/// Represents a file shared from one user to another (prototype model)
class SharedFile {
  final String id;
  final String ownerId;          // original owner of the file
  final String sharedByUserId;   // who performed this share (owner or receiver)
  final String recipientId;      // who receives it in this hop

  final String fileName;
  final int fileSizeBytes;
  final String fileTypeHint;
  final DateTime sentAt;

  /// Per-file symmetric AES key ID (conceptual)
  final String encryptionKeyId;

  /// Simulated “wrapped” key for the recipient (like RSA-encrypted AES key)
  final String wrappedKeyForRecipient;

  /// AES-encrypted file content (base64)
  final String? encryptedContentBase64;

  /// SHA-256 hash (hex) of the encrypted content (integrity)
  final String? fileHashHex;

  /// For demo: store AES key and IV in base64 (in real system these would be protected)
  final String? aesKeyBase64;
  final String? ivBase64;

  /// Owner-controlled permission: can recipient download (export) the file?
  bool canDownload;

  /// When the recipient first downloaded the file (null if never)
  DateTime? firstDownloadedAt;

  /// How many times the recipient downloaded
  int downloadCount;

  SharedFile({
    required this.id,
    required this.ownerId,
    required this.sharedByUserId,
    required this.recipientId,
    required this.fileName,
    required this.fileSizeBytes,
    required this.fileTypeHint,
    required this.sentAt,
    required this.encryptionKeyId,
    required this.wrappedKeyForRecipient,
    this.encryptedContentBase64,
    this.fileHashHex,
    this.aesKeyBase64,
    this.ivBase64,
    this.canDownload = false,
    this.firstDownloadedAt,
    this.downloadCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'sharedByUserId': sharedByUserId,
      'recipientId': recipientId,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'fileTypeHint': fileTypeHint,
      'sentAt': sentAt.toIso8601String(),
      'encryptionKeyId': encryptionKeyId,
      'wrappedKeyForRecipient': wrappedKeyForRecipient,
      'encryptedContentBase64': encryptedContentBase64,
      'fileHashHex': fileHashHex,
      'aesKeyBase64': aesKeyBase64,
      'ivBase64': ivBase64,
      'canDownload': canDownload,
      'firstDownloadedAt': firstDownloadedAt?.toIso8601String(),
      'downloadCount': downloadCount,
    };
  }

  factory SharedFile.fromMap(Map<String, dynamic> map) {
    return SharedFile(
      id: map['id'] as String,
      ownerId: map['ownerId'] as String,
      sharedByUserId: map['sharedByUserId'] as String,
      recipientId: map['recipientId'] as String,
      fileName: map['fileName'] as String,
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
      fileTypeHint: map['fileTypeHint'] as String? ?? 'unknown',
      sentAt: DateTime.parse(map['sentAt'] as String),
      encryptionKeyId: map['encryptionKeyId'] as String,
      wrappedKeyForRecipient: map['wrappedKeyForRecipient'] as String,
      encryptedContentBase64: map['encryptedContentBase64'] as String?,
      fileHashHex: map['fileHashHex'] as String?,
      aesKeyBase64: map['aesKeyBase64'] as String?,
      ivBase64: map['ivBase64'] as String?,
      canDownload: map['canDownload'] as bool? ?? false,
      firstDownloadedAt: map['firstDownloadedAt'] != null
          ? DateTime.parse(map['firstDownloadedAt'] as String)
          : null,
      downloadCount: (map['downloadCount'] as num?)?.toInt() ?? 0,
    );
  }
}




/// In-memory "database" for prototype: users + shared files
class MockDb {
  static final List<AppUser> users = [];
  static final List<SharedFile> sharedFiles = [];

  static AppUser createOrGetUser(
    String username,
    String email,
    String phone, {
    required bool biometricEnabled,
  }) {
    final existing = users.where((u) => u.username == username).toList();
    if (existing.isNotEmpty) {
      existing.first.biometricEnabled = biometricEnabled;
      // persist update
      LocalStorageService.instance.saveAll();
      return existing.first;
    }

    final newUser = AppUser(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      username: username,
      email: email,
      phone: phone,
      biometricEnabled: biometricEnabled,
    );
    users.add(newUser);
    LocalStorageService.instance.saveAll();
    return newUser;
  }

  static void addSharedFile(SharedFile file) {
    sharedFiles.add(file);
    LocalStorageService.instance.saveAll();
  }

  static List<SharedFile> filesForRecipient(String userId) {
    return sharedFiles.where((f) => f.recipientId == userId).toList();
  }

  static List<SharedFile> filesForOwner(String ownerId) {
    return sharedFiles.where((f) => f.ownerId == ownerId).toList();
  }
}

/// -------------------- LOCAL STORAGE SERVICE (JSON FILES) --------------------

class LocalStorageService {
  LocalStorageService._internal();
  static final LocalStorageService instance = LocalStorageService._internal();

  static const String _usersFileName = 'secure_share_users.json';
  static const String _filesFileName = 'secure_share_shared_files.json';

  Future<Directory> _getAppDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  Future<void> loadAll() async {
    if (kIsWeb) {
      // Skip persistence on web
      return;
    }

    try {
      final dir = await _getAppDir();

      final usersFile = File('${dir.path}/$_usersFileName');
      if (await usersFile.exists()) {
        final jsonStr = await usersFile.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr);
        MockDb.users
          ..clear()
          ..addAll(list.map((e) => AppUser.fromMap(e as Map<String, dynamic>)));
      }

      final filesFile = File('${dir.path}/$_filesFileName');
      if (await filesFile.exists()) {
        final jsonStr = await filesFile.readAsString();
        final List<dynamic> list = jsonDecode(jsonStr);
        MockDb.sharedFiles
          ..clear()
          ..addAll(
              list.map((e) => SharedFile.fromMap(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Error loading local data: $e');
    }
  }

  Future<void> saveAll() async {
    if (kIsWeb) {
      // Skip persistence on web
      return;
    }

    try {
      final dir = await _getAppDir();

      final usersFile = File('${dir.path}/$_usersFileName');
      final filesFile = File('${dir.path}/$_filesFileName');

      final usersJson =
          jsonEncode(MockDb.users.map((u) => u.toMap()).toList());
      final filesJson =
          jsonEncode(MockDb.sharedFiles.map((f) => f.toMap()).toList());

      await usersFile.writeAsString(usersJson);
      await filesFile.writeAsString(filesJson);
    } catch (e) {
      debugPrint('Error saving local data: $e');
    }
  }
}

/// -------------------- BIOMETRIC AUTH SERVICE --------------------

class BiometricAuthService {
  BiometricAuthService._internal();
  static final BiometricAuthService instance = BiometricAuthService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> authenticate(
      BuildContext context, String localizedReason) async {
    // On web or unsupported platforms, fall back to a dialog
    if (kIsWeb) {
      return await _showFallbackDialog(context, localizedReason);
    }

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();

      if (!canCheck || !isSupported) {
        // Device does not support real biometrics -> fallback dialog
        return await _showFallbackDialog(context, localizedReason);
      }

      final didAuth = await _localAuth.authenticate(
        localizedReason: localizedReason,
      );

      if (!didAuth) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication failed.')),
        );
      }

      return didAuth;
    } catch (e) {
      // Any error -> fallback dialog to keep prototype usable everywhere
      return await _showFallbackDialog(
        context,
        '$localizedReason\n\n(Real biometric failed: $e)\nSimulate instead?',
      );
    }
  }

  Future<bool> _showFallbackDialog(
      BuildContext context, String reason) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Biometric check'),
        content: Text(
          '$reason\n\n'
          'This is a fallback dialog (web/unsupported device).\n'
          'Tap "Simulate OK" to proceed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Simulate OK'),
          ),
        ],
      ),
    );
    return result == true;
  }
}

/// -------------------- LOGIN / REGISTER PAGE --------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isLoading = false;

  /// User’s choice: do they want biometric protection enabled?
  bool _biometricOptIn = false;

  /// Did they “pass” the biometric check at login (simulated for now)?
  bool _biometricVerified = false;

    Future<void> _doBiometricCheck() async {
    final ok = await BiometricAuthService.instance.authenticate(
      context,
      'Confirm your identity to enable biometric protection for this account.',
    );

    setState(() {
      _biometricVerified = ok;
    });

    if (_biometricVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric verified for this login.')),
      );
    }
  }


  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (_biometricOptIn && !_biometricVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'You chose biometric protection. Please complete the biometric check first.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    // Create or get existing user, store whether biometric is enabled
    final user = MockDb.createOrGetUser(
      username,
      email,
      phone,
      biometricEnabled: _biometricOptIn,
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardPage(currentUser: user),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    final form = Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a username' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              prefixIcon: Icon(Icons.email),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Enable biometric protection?'),
            subtitle: const Text(
                'If enabled, app will require fingerprint for send/receive actions.'),
            value: _biometricOptIn,
            onChanged: (v) {
              setState(() {
                _biometricOptIn = v;
                if (!v) _biometricVerified = false;
              });
            },
          ),
          if (_biometricOptIn) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _doBiometricCheck,
                icon: const Icon(Icons.fingerprint),
                label: Text(
                  _biometricVerified
                      ? 'Biometric OK'
                      : 'Tap to simulate fingerprint',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_isLoading ? 'Please wait...' : 'Continue'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tip: use different usernames to simulate sender & receiver.\n'
            'Biometric here is simulated; on a real device we will plug in fingerprint APIs.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 500 : 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SecureShare',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Prototype: Login / Biometric Enrollment',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                form,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -------------------- DASHBOARD PAGE --------------------

class DashboardPage extends StatelessWidget {
  final AppUser currentUser;

  const DashboardPage({super.key, required this.currentUser});

  void _goTo(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = MockDb.users;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard - ${currentUser.username}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                currentUser.biometricEnabled ? 'Biometric: ON' : 'Biometric: OFF',
                style: TextStyle(
                  color: currentUser.biometricEnabled
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Biometric status'),
              subtitle: Text(
                currentUser.biometricEnabled
                    ? 'This user requires biometric for sensitive actions.'
                    : 'Biometric is disabled for this user.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.send),
              title: const Text('Send File'),
              subtitle:
                  const Text('Pick a recipient and attach a file (in-memory)'),
              onTap: () => _goTo(
                context,
                SendFilePage(currentUser: currentUser),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inbox),
              title: const Text('My Received Files'),
              subtitle: const Text('See files shared with you'),
              onTap: () => _goTo(
                  context, ReceivedFilesPage(currentUser: currentUser)),
            ),
          ),
          const SizedBox(height: 12),
          Card(
  child: ListTile(
    leading: const Icon(Icons.admin_panel_settings),
    title: const Text('Owner: Manage Access / Downloads'),
    subtitle: const Text('Control who can download your shared files'),
    onTap: () => _goTo(
        context, OwnerAccessPage(currentUser: currentUser)),
  ),
),
const SizedBox(height: 12),
Card(
  child: ListTile(
    leading: const Icon(Icons.table_chart),
    title: const Text('Sharing Log (All Files)'),
    subtitle: const Text('Tabular view of all shares & permissions'),
    onTap: () => _goTo(
      context,
      SharingLogPage(currentUser: currentUser),
    ),
  ),
),
const SizedBox(height: 24),
const Text(
  'Registered users (mock):',
  style: TextStyle(fontWeight: FontWeight.bold),
),

          const SizedBox(height: 8),
          ...users.map(
            (u) => ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline),
              title: Text(u.username),
              subtitle: Text(
                'id: ${u.id} | biometric: ${u.biometricEnabled ? 'ON' : 'OFF'}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -------------------- BIOMETRIC HELPER (SIMULATED) --------------------

Future<bool> requireBiometricIfEnabled(
    BuildContext context, AppUser user, String actionName) async {
  if (!user.biometricEnabled) {
    // No biometric required, allow directly
    return true;
  }

  final ok = await BiometricAuthService.instance.authenticate(
    context,
    'Biometric required for action:\n$actionName',
  );

  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Biometric check failed or cancelled.')),
    );
    return false;
  }

  return true;
}


/// -------------------- SEND FILE PAGE --------------------

class SendFilePage extends StatefulWidget {
  final AppUser currentUser;

  const SendFilePage({super.key, required this.currentUser});

  @override
  State<SendFilePage> createState() => _SendFilePageState();
}

class _SendFilePageState extends State<SendFilePage> {
AppUser? _selectedRecipient;
String? _selectedFileName;
int? _selectedFileSize;
String? _selectedFileType;
Uint8List? _selectedFileBytes;
 // raw file bytes for encryption


Future<void> _pickFile() async {
  // Open system file picker
  final XFile? file = await openFile();

  if (file == null) {
    // user cancelled
    return;
  }

  // Read bytes
  final bytes = await file.readAsBytes();
  final name = file.name; // like "document.txt"
  final size = bytes.lengthInBytes;

  // Get extension
  String ext = 'unknown';
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex != -1 && dotIndex < name.length - 1) {
    ext = name.substring(dotIndex + 1).toLowerCase();
  }

  setState(() {
    _selectedFileName = name;
    _selectedFileSize = size;
    _selectedFileType = ext;
    _selectedFileBytes = bytes;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Selected file: $_selectedFileName ($_selectedFileSize bytes)',
      ),
    ),
  );
}

    Map<String, String> _encryptAndHash(Uint8List plainBytes) {
    // Generate AES-256 key & IV
    final key = enc.Key.fromSecureRandom(32); // 256-bit
    final iv = enc.IV.fromSecureRandom(16);   // 128-bit IV

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv).bytes;
    final encryptedBase64 = base64Encode(encrypted);

    final hash = sha256.convert(encrypted).toString(); // hex

    return {
      'encrypted': encryptedBase64,
      'hash': hash,
      'key': base64Encode(key.bytes),
      'iv': base64Encode(iv.bytes),
    };
  }





  Future<void> _send() async {
    if (_selectedRecipient == null || _selectedFileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select recipient & file first.')),
      );
      return;
    }

    // Biometric check for sender
    final ok = await requireBiometricIfEnabled(
      context,
      widget.currentUser,
      'Send file "${_selectedFileName!}" to ${_selectedRecipient!.username}',
    );
    if (!ok) return;

    // Generate IDs
    final fileId = DateTime.now().microsecondsSinceEpoch.toString();
    final encryptionKeyId = 'key_$fileId';

    // For prototype: simulate wrapped key string
    final wrappedKey =
        'wrapped_${_selectedRecipient!.id}_$encryptionKeyId';

    String? encryptedBase64;
    String? hashHex;
    String? aesKeyB64;
    String? ivB64;

    if (_selectedFileBytes != null) {
      final result = _encryptAndHash(_selectedFileBytes!);
      encryptedBase64 = result['encrypted'];
      hashHex = result['hash'];
      aesKeyB64 = result['key'];
      ivB64 = result['iv'];
    }

    final shared = SharedFile(
      id: fileId,
      ownerId: widget.currentUser.id,
      sharedByUserId: widget.currentUser.id, // owner is sharer in first hop
      recipientId: _selectedRecipient!.id,
      fileName: _selectedFileName!,
      fileSizeBytes: _selectedFileSize ?? 0,
      fileTypeHint: _selectedFileType ?? 'unknown',
      sentAt: DateTime.now(),
      encryptionKeyId: encryptionKeyId,
      wrappedKeyForRecipient: wrappedKey,
      encryptedContentBase64: encryptedBase64,
      fileHashHex: hashHex,
      aesKeyBase64: aesKeyB64,
      ivBase64: ivB64,
      canDownload: false,
    );

    MockDb.addSharedFile(shared);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Encrypted & sent "${_selectedFileName!}" to ${_selectedRecipient!.username}.',
        ),
      ),
    );

    setState(() {
      _selectedFileName = null;
      _selectedFileSize = null;
      _selectedFileType = null;
      _selectedFileBytes = null;
      _selectedRecipient = null;
    });
  }



  @override
  Widget build(BuildContext context) {
    final others =
        MockDb.users.where((u) => u.id != widget.currentUser.id).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Send File')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 1: Choose recipient',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (others.isEmpty)
              const Text(
                  'No other users yet. Go back and create more users from login screen.'),
            if (others.isNotEmpty)
              DropdownButton<AppUser>(
                value: _selectedRecipient,
                hint: const Text('Select a recipient'),
                isExpanded: true,
                items: others
                    .map(
                      (u) => DropdownMenuItem(
                        value: u,
                        child: Text(u.username),
                      ),
                    )
                    .toList(),
                onChanged: (u) => setState(() => _selectedRecipient = u),
              ),
            const SizedBox(height: 24),
            const Text(
              'Step 2: Pick file (fake for now)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Choose file'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedFileName ?? 'No file selected',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.send),
                label: const Text('Send (with biometric)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------- RECEIVED FILES PAGE --------------------

class ReceivedFilesPage extends StatelessWidget {
  final AppUser currentUser;

  const ReceivedFilesPage({super.key, required this.currentUser});

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  Future<void> _openDecrypted(BuildContext context, SharedFile f) async {
  // Biometric check first
  final ok = await requireBiometricIfEnabled(
    context,
    currentUser,
    'Open file "${f.fileName}"',
  );
  if (!ok) return;

  // Navigate to full-screen viewer page
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FileViewerPage(
        currentUser: currentUser,
        file: f,
      ),
    ),
  );
}


  Future<void> _downloadFile(BuildContext context, SharedFile f) async {
    final ok = await requireBiometricIfEnabled(
      context,
      currentUser,
      'Download file "${f.fileName}"',
    );
    if (!ok) return;

    if (!f.canDownload) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Owner has not allowed download/export for this file yet.'),
        ),
      );
      return;
    }

    if (f.firstDownloadedAt == null) {
      f.firstDownloadedAt = DateTime.now();
    }
    f.downloadCount += 1;
    LocalStorageService.instance.saveAll();


    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloading "${f.fileName}" (simulated). '
          'Total downloads: ${f.downloadCount}.',
        ),
      ),
    );

    // NOTE: In a real app, here we would write decrypted bytes to device storage.
  }

  Future<void> _shareFileToAnother(
    BuildContext context,
    SharedFile original,
  ) async {
    // anyone except current user
    final others =
        MockDb.users.where((u) => u.id != currentUser.id).toList();

    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No other users available to share with.')),
      );
      return;
    }

    final selected = await showDialog<AppUser>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Share "${original.fileName}" to...'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: others
                .map(
                  (u) => ListTile(
                    title: Text(u.username),
                    subtitle: Text('id: ${u.id}'),
                    onTap: () => Navigator.of(ctx).pop(u),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected == null) return;

    // Biometric check for sharer (this receiver)
    final ok = await requireBiometricIfEnabled(
      context,
      currentUser,
      'Share file "${original.fileName}" to ${selected.username}',
    );
    if (!ok) return;

    final newId = DateTime.now().microsecondsSinceEpoch.toString();

    final shared = SharedFile(
      id: newId,
      ownerId: original.ownerId,              // original owner stays same
      sharedByUserId: currentUser.id,         // this hop shared by current user
      recipientId: selected.id,               // new receiver
      fileName: original.fileName,
      fileSizeBytes: original.fileSizeBytes,
      fileTypeHint: original.fileTypeHint,
      sentAt: DateTime.now(),
      encryptionKeyId: original.encryptionKeyId,
      wrappedKeyForRecipient:
          'wrapped_${selected.id}_${original.encryptionKeyId}',
      encryptedContentBase64: original.encryptedContentBase64,
      fileHashHex: original.fileHashHex,
      aesKeyBase64: original.aesKeyBase64,
      ivBase64: original.ivBase64,
      canDownload: false,
      firstDownloadedAt: null,
      downloadCount: 0,
    );

    MockDb.addSharedFile(shared);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Shared "${original.fileName}" from '
          '${currentUser.username} to ${selected.username}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myFiles = MockDb.filesForRecipient(currentUser.id);

    return Scaffold(
      appBar: AppBar(title: const Text('My Received Files')),
      body: myFiles.isEmpty
          ? const Center(
              child: Text(
                'No files received yet.\n'
                'Send a file to this user from another account.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: myFiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final f = myFiles[index];
                final owner = MockDb.users.firstWhere(
                  (u) => u.id == f.ownerId,
                  orElse: () => AppUser(
                    id: 'unknown',
                    username: 'Unknown',
                    email: '',
                    phone: '',
                  ),
                );

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'From: ${owner.username}\n'
                          'Type: ${f.fileTypeHint}, Size: ${_formatSize(f.fileSizeBytes)}\n'
                          'Key: ${f.encryptionKeyId}\n'
                          'Downloads: ${f.downloadCount} '
                          '${f.firstDownloadedAt != null ? "(since ${f.firstDownloadedAt})" : "(never)"}\n'
                          'Sent: ${f.sentAt}',
                          maxLines: 6,
                        ),
                        const SizedBox(height: 12),
                        // Buttons nicely aligned in one row using Wrap
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ElevatedButton(
                              onPressed: () => _openDecrypted(context, f),
                              child: const Text('Open'),
                            ),
                            ElevatedButton(
                              onPressed: () => _downloadFile(context, f),
                              child: const Text('Download'),
                            ),
                            OutlinedButton(
                              onPressed: () => _shareFileToAnother(
                                context,
                                f,
                              ),
                              child: const Text('Share'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          f.canDownload
                              ? 'Download: Allowed'
                              : 'Download: Not allowed by owner',
                          style: TextStyle(
                            fontSize: 12,
                            color: f.canDownload
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}


/// -------------------- OWNER ACCESS / APPROVAL PAGE --------------------

class OwnerAccessPage extends StatefulWidget {
  final AppUser currentUser;
  const OwnerAccessPage({super.key, required this.currentUser});

  @override
  State<OwnerAccessPage> createState() => _OwnerAccessPageState();
}

class _OwnerAccessPageState extends State<OwnerAccessPage> {
  @override
  Widget build(BuildContext context) {
    final mySharedFiles = MockDb.filesForOwner(widget.currentUser.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Owner: Manage Access')),
      body: mySharedFiles.isEmpty
          ? const Center(
              child: Text(
                'You have not sent any files yet.\nGo to "Send File" to share.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: mySharedFiles.length,
              itemBuilder: (context, index) {
                final f = mySharedFiles[index];
                final recipient = MockDb.users.firstWhere(
                  (u) => u.id == f.recipientId,
                  orElse: () => AppUser(
                    id: 'unknown',
                    username: 'Unknown',
                    email: '',
                    phone: '',
                  ),
                );
                return Card(
                  child: ListTile(
                    title: Text(f.fileName),
                    subtitle: Text(
                      'Recipient: ${recipient.username}\nSent: ${f.sentAt}',
                      maxLines: 2,
                    ),
                    isThreeLine: true,
                    trailing: Switch(
                      value: f.canDownload,
                      onChanged: (val) async {
  final ok = await requireBiometricIfEnabled(
    context,
    widget.currentUser,
    '${val ? "Allow" : "Revoke"} download for ${recipient.username}',
  );
  if (!ok) return;

  setState(() {
    f.canDownload = val;
  });
  LocalStorageService.instance.saveAll();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '${val ? "Allowed" : "Revoked"} download for ${recipient.username} on "${f.fileName}".',
      ),
    ),
  );
},

                    ),
                  ),
                );
              },
            ),
    );
  }
}
/// -------------------- SHARING LOG PAGE (TABULAR VIEW) --------------------

class SharingLogPage extends StatelessWidget {
  final AppUser currentUser;
  const SharingLogPage({super.key, required this.currentUser});

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final allFiles = MockDb.sharedFiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sharing Log (All Files)'),
      ),
      body: allFiles.isEmpty
          ? const Center(
              child: Text(
                'No files have been shared yet.',
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
child: DataTable(
  columns: const [
    DataColumn(label: Text('File')),
    DataColumn(label: Text('Type')),
    DataColumn(label: Text('Size')),
    DataColumn(label: Text('Owner')),
    DataColumn(label: Text('Shared By')),
    DataColumn(label: Text('Recipient')),
    DataColumn(label: Text('Key ID')),
    DataColumn(label: Text('Wrapped Key (short)')),
    DataColumn(label: Text('Sent At')),
    DataColumn(label: Text('Allowed')),
    DataColumn(label: Text('Downloads')),
    DataColumn(label: Text('First Downloaded')),
  ],
 rows: allFiles.map((f) {
  final owner = MockDb.users.firstWhere(
    (u) => u.id == f.ownerId,
    orElse: () => AppUser(
      id: 'unknown',
      username: 'Unknown',
      email: '',
      phone: '',
    ),
  );
  final sharedBy = MockDb.users.firstWhere(
    (u) => u.id == f.sharedByUserId,
    orElse: () => AppUser(
      id: 'unknown',
      username: 'Unknown',
      email: '',
      phone: '',
    ),
  );
  final rec = MockDb.users.firstWhere(
    (u) => u.id == f.recipientId,
    orElse: () => AppUser(
      id: 'unknown',
      username: 'Unknown',
      email: '',
      phone: '',
    ),
  );

  return DataRow(
    cells: [
      DataCell(
        Text(f.fileName),
        // tap file name to view full history
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FileHistoryPage(
                currentUser: currentUser,
                encryptionKeyId: f.encryptionKeyId,
              ),
            ),
          );
        },
      ),
      DataCell(Text(f.fileTypeHint)),
      DataCell(Text(_formatSize(f.fileSizeBytes))),
      DataCell(Text(owner.username)),
      DataCell(Text(sharedBy.username)),
      DataCell(Text(rec.username)),
      DataCell(Text(f.encryptionKeyId)),
      DataCell(
        Text(
          f.wrappedKeyForRecipient.length > 12
              ? '${f.wrappedKeyForRecipient.substring(0, 12)}...'
              : f.wrappedKeyForRecipient,
        ),
      ),
      DataCell(
        Text(
          f.sentAt.toString(),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DataCell(
        Text(
          f.canDownload ? 'YES' : 'NO',
          style: TextStyle(
            color: f.canDownload ? Colors.green : Colors.red,
          ),
        ),
      ),
      DataCell(Text(f.downloadCount.toString())),
      DataCell(
        Text(
          f.firstDownloadedAt?.toString() ?? 'Never',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}).toList(),

),
            ),
    );
  }
}
/// -------------------- FILE HISTORY PAGE (PER-FILE SHARING CHAIN) --------------------

class FileHistoryPage extends StatelessWidget {
  final AppUser currentUser;
  final String encryptionKeyId;

  const FileHistoryPage({
    super.key,
    required this.currentUser,
    required this.encryptionKeyId,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    // All hops for this file (same encryptionKeyId)
    final hops = MockDb.sharedFiles
        .where((f) => f.encryptionKeyId == encryptionKeyId)
        .toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    if (hops.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('File History'),
        ),
        body: Center(
          child: Text(
            'No history found for key: $encryptionKeyId',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final first = hops.first;
    final owner = MockDb.users.firstWhere(
      (u) => u.id == first.ownerId,
      orElse: () => AppUser(
        id: 'unknown',
        username: 'Unknown',
        email: '',
        phone: '',
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('File History'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.fileName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Owner: ${owner.username}\n'
                    'Type: ${first.fileTypeHint}, '
                    'Size: ${_formatSize(first.fileSizeBytes)}\n'
                    'Key ID: ${first.encryptionKeyId}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sharing chain:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ...hops.map((f) {
            final sharedBy = MockDb.users.firstWhere(
              (u) => u.id == f.sharedByUserId,
              orElse: () => AppUser(
                id: 'unknown',
                username: 'Unknown',
                email: '',
                phone: '',
              ),
            );
            final recipient = MockDb.users.firstWhere(
              (u) => u.id == f.recipientId,
              orElse: () => AppUser(
                id: 'unknown',
                username: 'Unknown',
                email: '',
                phone: '',
              ),
            );

            return Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text('${sharedBy.username} → ${recipient.username}'),
                subtitle: Text(
                  'Sent: ${f.sentAt}\n'
                  'Download allowed: ${f.canDownload ? "YES" : "NO"}\n'
                  'Downloads: ${f.downloadCount} '
                  '${f.firstDownloadedAt != null ? "(since ${f.firstDownloadedAt})" : "(never)"}',
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
/// -------------------- FILE VIEWER PAGE (DECRYPTED VIEW) --------------------

class FileViewerPage extends StatelessWidget {
  final AppUser currentUser;
  final SharedFile file;

  const FileViewerPage({
    super.key,
    required this.currentUser,
    required this.file,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = kb * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  Future<Map<String, dynamic>> _decryptAndVerify() async {
    if (file.encryptedContentBase64 == null ||
        file.aesKeyBase64 == null ||
        file.ivBase64 == null) {
      throw Exception(
          'No encrypted content / key / IV stored for this file (demo).');
    }

    final encryptedBytes = base64Decode(file.encryptedContentBase64!);

    // integrity check with SHA-256
    if (file.fileHashHex != null) {
      final calcHash = sha256.convert(encryptedBytes).toString();
      if (calcHash != file.fileHashHex) {
        throw Exception('Integrity check failed (SHA-256 mismatch).');
      }
    }

    final keyBytes = base64Decode(file.aesKeyBase64!);
    final ivBytes = base64Decode(file.ivBase64!);

    final key = enc.Key(keyBytes);
    final iv = enc.IV(ivBytes);

    final encrypter = enc.Encrypter(
      enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );

    final decryptedBytes =
        encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv);

    return {
      'bytes': decryptedBytes,
    };
  }

  @override
  Widget build(BuildContext context) {
    final owner = MockDb.users.firstWhere(
      (u) => u.id == file.ownerId,
      orElse: () => AppUser(
        id: 'unknown',
        username: 'Unknown',
        email: '',
        phone: '',
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('View: ${file.fileName}'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _decryptAndVerify(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error opening file:\n${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final bytes = snapshot.data!['bytes'] as List<int>;

          Widget contentWidget;

          if (file.fileTypeHint.toLowerCase() == 'txt') {
            final text = utf8.decode(bytes, allowMalformed: true);
            contentWidget = SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(text),
            );
          } else if (['png', 'jpg', 'jpeg'].contains(
              file.fileTypeHint.toLowerCase())) {
            contentWidget = Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Text(
                      'Decrypted image (${_formatSize(bytes.length)})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Image.memory(
                      Uint8List.fromList(bytes),
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              ),
            );
          } else {
            contentWidget = Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Decrypted ${_formatSize(bytes.length)} of data.\n\n'
                'Preview is only implemented for .txt and image files in this prototype.\n\n'
                'File type: ${file.fileTypeHint}',
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'File: ${file.fileName}\n'
                    'Owner: ${owner.username}\n'
                    'Size: ${_formatSize(file.fileSizeBytes)}\n'
                    'Type: ${file.fileTypeHint}\n'
                    'Key ID: ${file.encryptionKeyId}',
                  ),
                ),
              ),
              const Divider(height: 0),
              Expanded(child: contentWidget),
            ],
          );
        },
      ),
    );
  }
}
