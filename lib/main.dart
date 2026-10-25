import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JRAiApp());
}

/// المتغير المرجعي لاسم ملف النموذج المستهدف زرعه في التطبيق
const String kModelFileName = 'qwen2.5-3b-instruct-q4_k_m.gguf';

class JRAiApp extends StatefulWidget {
  const JRAiApp({super.key});

  @override
  State<JRAiApp> createState() => _JRAiAppState();
}

class _JRAiAppState extends State<JRAiApp> {
  // للتحكم في لغة الواجهة (العربية كافتراضي)
  Locale _currentLocale = const Locale('ar');

  void _toggleLanguage() {
    setState(() {
      _currentLocale = _currentLocale.languageCode == 'ar'
          ? const Locale('en')
          : const Locale('ar');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'JR AI',
      locale: _currentLocale,
      // ضبط الاتجاهات تلقائياً بناءً على اللغة
      builder: (context, child) {
        return Directionality(
          textDirection: _currentLocale.languageCode == 'ar'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        );
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0F1D), // أزرق غامق جداً
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1E293B),
          secondary: Color(0xFFB45309), // ذهبي غامق
          surface: Color(0xFF111827),
        ),
      ),
      home: HomeScreen(
        currentLocale: _currentLocale,
        onToggleLanguage: _toggleLanguage,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Models - نماذج البيانات للحفظ وعدم النسيان
// -----------------------------------------------------------------------------

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isUser': isUser,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        text: json['text'],
        isUser: json['isUser'],
        timestamp: DateTime.parse(json['timestamp']),
      );
}

class ChatSession {
  final String id;
  String title;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
  });

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

// -----------------------------------------------------------------------------
// Home Screen - الشاشة الرئيسية مع الأنيميشن والشاتات
// -----------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  final Locale currentLocale;
  final VoidCallback onToggleLanguage;

  const HomeScreen({
    super.key,
    required this.currentLocale,
    required this.onToggleLanguage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // وحدات التحكم بالأنيميشن للضوء الذهبي المتحرك
  late AnimationController _goldAnimationController;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // قائمة جلسات المحادثة
  List<ChatSession> _sessions = [];
  String _activeSessionId = '';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();

    // إعداد حركة التدرج الذهبي الغامق
    _goldAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _loadSavedSessions();
  }

  @override
  void dispose() {
    _goldAnimationController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // حفظ واسترجاع الشاتات (منع النسيان عند إغلاق التطبيق)
  // ---------------------------------------------------------------------------

  void _loadSavedSessions() {
    // في المرحلة القادمة سنربط SharedPreferences بشكل مباشر هنا
    // تم إنشاء جلسة افتراضية للاستعراض
    if (_sessions.isEmpty) {
      final defaultSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: widget.currentLocale.languageCode == 'ar'
            ? 'محادثة جديدة'
            : 'New Conversation',
        messages: [
          ChatMessage(
            id: '1',
            text: widget.currentLocale.languageCode == 'ar'
                ? 'أهلاً بك! نموذج JR AI جاهز ومستعد للعمل محلياً.'
                : 'Welcome! JR AI model is ready to work locally.',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        ],
      );
      _sessions.add(defaultSession);
      _activeSessionId = defaultSession.id;
    }
  }

  void _createNewChat() {
    final isAr = widget.currentLocale.languageCode == 'ar';
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: isAr
          ? 'محادثة ${_sessions.length + 1}'
          : 'Chat ${_sessions.length + 1}',
      messages: [],
    );
    setState(() {
      _sessions.add(newSession);
      _activeSessionId = newSession.id;
    });
    Navigator.pop(context); // إغلاق الـ Drawer
  }

  ChatSession get _activeSession {
    return _sessions.firstWhere(
      (s) => s.id == _activeSessionId,
      orElse: () => _sessions.first,
    );
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _activeSession.messages.add(userMsg);
      if (_activeSession.messages.length == 1) {
        _activeSession.title = text.length > 20 ? '${text.substring(0, 20)}...' : text;
      }
      _inputController.clear();
      _isGenerating = true;
    });

    _scrollToBottom();

    // محاكاة استجابة الواجهة تمهيداً لزرع المحرك البرمجي
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final aiMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: widget.currentLocale.languageCode == 'ar'
            ? 'تم استقبال رسالتك بنجاح داخل واجهة JR AI.'
            : 'Message received successfully inside JR AI interface.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      setState(() {
        _activeSession.messages.add(aiMsg);
        _isGenerating = false;
      });
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

  // ---------------------------------------------------------------------------
  // تصميم الواجهة الشكلي
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isAr = widget.currentLocale.languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFD97706), size: 22),
            const SizedBox(width: 8),
            Text(
              'JR AI',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade200,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB45309), width: 0.8),
              ),
              child: Text(
                isAr ? 'أوفلاين' : 'Offline',
                style: const TextStyle(fontSize: 10, color: Color(0xFFFBBF24)),
              ),
            ),
          ],
        ),
        actions: [
          // زر تغيير اللغة
          IconButton(
            icon: const Icon(Icons.language, color: Colors.white70),
            onPressed: widget.onToggleLanguage,
            tooltip: isAr ? 'English' : 'عربي',
          ),
        ],
      ),

      // شريط الـ 3 شرط (القائمة الجانبية للشاتات)
      drawer: _buildDrawer(isAr),

      body: AnimatedBuilder(
        animation: _goldAnimationController,
        builder: (context, child) {
          return Column(
            children: [
              // قائمة الرسائل
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _activeSession.messages.length,
                  itemBuilder: (context, index) {
                    final msg = _activeSession.messages[index];
                    return _buildMessageBubble(msg);
                  },
                ),
              ),

              if (_isGenerating)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isAr ? 'جاري التفكير...' : 'Thinking...',
                        style: const TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ],
                  ),
                ),

              // منطقة إدخال النص مع التدرج الذهبي المتحرك
              _buildInputArea(isAr),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // عناصر الواجهة الفرعية (Widgets)
  // ---------------------------------------------------------------------------

  Widget _buildDrawer(bool isAr) {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: Color(0xFF0A0F1D),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFB45309),
                  radius: 22,
                  child: Icon(Icons.psychology, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JR AI Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      kModelFileName,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add, color: Color(0xFFFBBF24)),
            title: Text(
              isAr ? 'محادثة جديدة' : 'New Chat',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: _createNewChat,
          ),
          const Divider(color: Color(0xFF1E293B)),
          Expanded(
            child: ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected = session.id == _activeSessionId;
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: const Color(0xFF1E293B),
                  leading: Icon(
                    Icons.chat_bubble_outline,
                    color: isSelected ? const Color(0xFFFBBF24) : Colors.grey,
                  ),
                  title: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade400,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _activeSessionId = session.id;
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    // حركة التدرج الذهبي الغامق للكبسولة
    final goldAnimValue = _goldAnimationController.value;

    final userGradient = const LinearGradient(
      colors: [Color(0xFF1E3A8A), Color(0xFF1E293B)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final aiGradient = LinearGradient(
      colors: [
        const Color(0xFF111827),
        Color.lerp(const Color(0xFF1F2937), const Color(0xFF78350F), goldAnimValue)!,
        const Color(0xFF0F172A),
      ],
      begin: Alignment(-1.0 + (goldAnimValue * 2), -1.0),
      end: Alignment(1.0 - (goldAnimValue * 2), 1.0),
    );

    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        decoration: BoxDecoration(
          gradient: msg.isUser ? userGradient : aiGradient,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 18),
          ),
          border: Border.all(
            color: msg.isUser
                ? const Color(0xFF3B82F6).withOpacity(0.4)
                : const Color(0xFFB45309).withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          msg.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isAr) {
    final goldValue = _goldAnimationController.value;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        border: Border(
          top: BorderSide(
            color: Color.lerp(
              const Color(0xFF1E293B),
              const Color(0xFF92400E),
              goldValue,
            )!,
            width: 1.2,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Color.lerp(
                    const Color(0xFF334155),
                    const Color(0xFFB45309),
                    goldValue,
                  )!,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: isAr ? 'اكتب رسالتك هنا...' : 'Type your message...',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFD97706),
                  Color.lerp(const Color(0xFFB45309), const Color(0xFF78350F), goldValue)!,
                ],
              ),
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
