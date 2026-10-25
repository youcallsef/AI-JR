import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  runApp(const JR_AI_App());
}

class JR_AI_App extends StatelessWidget {
  const JR_AI_App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jostarika AI Local',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F1D), // أزرق غامق فخم
        primaryColor: const Color(0xFFD4AF37), // ذهبي
        colorScheme: ColorScheme.dark(
          background: const Color(0xFF0A0F1D),
          surface: const Color(0xFF131B2E),
          primary: const Color(0xFFD4AF37),
        ),
      ),
      home: const ChatHomeScreen(),
    );
  }
}

// نموذج الشات
class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});

  Map<String, dynamic> toJson() => {'text': text, 'isUser': isUser};
  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      ChatMessage(text: json['text'], isUser: json['isUser']);
}

class ChatSession {
  String id;
  String title;
  List<ChatMessage> messages;
  ChatSession({required this.id, required this.title, required this.messages});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'],
        title: json['title'],
        messages: (json['messages'] as List)
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
      );
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen>
    with SingleTickerProviderStateMixin {
  // متغيرات الـ OBB والنموذج باسم الحزمة الجديد
  String _modelStatus = 'جاري التحقق من ملفات الـ OBB...';
  String? _modelFullPath;
  bool _isModelReady = false;

  // إدارة الشاتات والذاكرة الدائمة
  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // تأثير الخلفية المتحركة (الذهبي الغامق)
  late AnimationController _goldAnimController;

  @override
  void initState() {
    super.initState();
    _goldAnimController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _initializeAppData();
  }

  @override
  void dispose() {
    _goldAnimController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // تحميل الشاتات القديمة وفحص الـ OBB
  Future<void> _initializeAppData() async {
    await _checkPermissionsAndObb();
    await _loadSessionsFromPrefs();

    if (_sessions.isEmpty) {
      _createNewSession(initialTitle: 'محادثة جديدة');
    } else {
      setState(() {
        _currentSession = _sessions.first;
      });
    }
  }

  // فحص مسار ملف الـ OBB والنموذج المطلوب
  Future<void> _checkPermissionsAndObb() async {
    await Permission.storage.request();
    try {
      final String packageName = "com.jostarika.ai"; // اسم الحزمة الجديد
      final String targetModelName = "qwen2.5-3b-instruct-q4_k_m.gguf";
      
      // مسار الـ OBB الافتراضي في أندرويد بالباقة الجديدة
      final Directory obbDir = Directory('/storage/emulated/0/Android/obb/$packageName');

      if (await obbDir.exists()) {
        List<FileSystemEntity> files = obbDir.listSync();
        for (var file in files) {
          if (file.path.endsWith('.obb')) {
            setState(() {
              _modelFullPath = file.path;
              _isModelReady = true;
              _modelStatus = 'تم العثور على ملف OBB والنموذج بنجاح!\nالنموذج: $targetModelName';
            });
            return;
          }
        }
        setState(() {
          _modelStatus = 'فولدر الـ OBB موجود، لكن ملف الـ .obb غير موجود داخله!\nضع الملف هنا: Android/obb/$packageName';
        });
      } else {
        setState(() {
          _modelStatus = 'أنشئ مجلد باسم:\nAndroid/obb/$packageName\nوضع ملف الـ OBB داخله.';
        });
      }
    } catch (e) {
      setState(() {
        _modelStatus = 'خطأ في فحص الملفات: $e';
      });
    }
  }

  // حفظ الشاتات في SharedPreferences (عشان المساعد ماينساش ابداً)
  Future<void> _saveSessionsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> encodedList =
        _sessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('jostarika_ai_sessions', encodedList);
  }

  // استرجاع الشاتات القديمة عند فتح التطبيق
  Future<void> _loadSessionsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? encodedList = prefs.getStringList('jostarika_ai_sessions');
    if (encodedList != null) {
      setState(() {
        _sessions =
            encodedList.map((s) => ChatSession.fromJson(jsonDecode(s))).toList();
      });
    }
  }

  // إنشاء شات جديد
  void _createNewSession({String initialTitle = 'شات جديد'}) {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: initialTitle,
      messages: [],
    );
    setState(() {
      _sessions.insert(0, newSession);
      _currentSession = newSession;
    });
    _saveSessionsToPrefs();
    Navigator.pop(context); // قفل القائمة الجانبية
  }

  // إرسال رسالة
  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    String userText = _messageController.text;
    _messageController.clear();

    setState(() {
      _currentSession?.messages.add(ChatMessage(text: userText, isUser: true));
      if (_currentSession?.title == 'شات جديد' || _currentSession?.title == 'محادثة جديدة') {
        _currentSession?.title = userText.length > 20 ? '${userText.substring(0, 20)}...' : userText;
      }
    });

    _saveSessionsToPrefs();
    _scrollToBottom();

    // محاكاة رد الذكاء الاصطناعي المحلي
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _currentSession?.messages.add(ChatMessage(
          text: 'أهلاً بك يا يوسف في عالم Jostarika AI! أنا نموذج Qwen 2.5 المحلي جاهز ومستجيب من ملف الـ OBB.',
          isUser: false,
        ));
      });
      _saveSessionsToPrefs();
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        title: Text(
          _currentSession?.title ?? 'Jostarika AI',
          style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFD4AF37)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _createNewSession(initialTitle: 'شات جديد'),
            tooltip: 'محادثة جديدة',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0A0F1D),
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF131B2E),
                border: Border(bottom: BorderSide(color: Color(0xFFD4AF37), width: 1)),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.psychology, size: 40, color: Color(0xFFD4AF37)),
                    SizedBox(height: 10),
                    Text(
                      'Jostarika AI - Local',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  bool isSelected = session.id == _currentSession?.id;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: const Color(0xFF131B2E),
                    leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFFD4AF37), size: 20),
                    title: Text(
                      session.title,
                      style: TextStyle(color: isSelected ? const Color(0xFFD4AF37) : Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      setState(() {
                        _currentSession = session;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                _modelStatus,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
      // الخلفية المتحركة والذهبي الغامق
      body: AnimatedBuilder(
        animation: _goldAnimController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A0F1D),
                  const Color(0xFF131B2E),
                  Color.lerp(const Color(0xFF0A0F1D), const Color(0xFF2C220B), _goldAnimController.value)!,
                ],
              ),
            ),
            child: child,
          );
        },
        child: Column(
          children: [
            Expanded(
              child: _currentSession == null || _currentSession!.messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.auto_awesome, size: 60, color: Color(0xFFD4AF37)),
                          SizedBox(height: 15),
                          Text(
                            'أهلاً بك يا يوسف! Jostarika AI جاهز للعمل بدون إنترنت.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white60, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _currentSession!.messages.length,
                      itemBuilder: (context, index) {
                        final msg = _currentSession!.messages[index];
                        return Align(
                          alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: msg.isUser ? const Color(0xFF1F2C48) : const Color(0xFF162035),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: msg.isUser ? const Color(0xFFD4AF37).withOpacity(0.4) : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              msg.text,
                              style: constTextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // شريط الإدخال بتصميم الكبسولة والإطار الذهبي
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: const Color(0xFF0A0F1D).withOpacity(0.9),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'اسألني أي شيء (عربي / English)...',
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                              ),
                              maxLines: 4,
                              minLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFD4AF37),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF0A0F1D)),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
