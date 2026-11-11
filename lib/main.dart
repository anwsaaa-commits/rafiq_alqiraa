import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gold = Color(0xFFD6AD55);
const ink = Color(0xFF101114);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RafiqApp());
}

class RafiqApp extends StatelessWidget {
  const RafiqApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'رفيق القراءة',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F1E9),
          colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.light),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F1E9), foregroundColor: ink),
          cardTheme: CardThemeData(color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        ),
        home: const LibraryPage(),
      );
}

class Book {
  final String path;
  final String name;
  final int page;

  Book({required this.path, required this.name, this.page = 1});

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'page': page};

  factory Book.fromJson(Map<String, dynamic> j) =>
      Book(path: j['path'], name: j['name'], page: j['page'] ?? 1);
}

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Book> books = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadBooks();
  }

  Future<void> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('books') ?? [];
    books = raw
        .map((e) => Book.fromJson(jsonDecode(e)))
        .where((b) => File(b.path).existsSync())
        .toList();
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveBooks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('books', books.map((b) => jsonEncode(b.toJson())).toList());
  }

  Future<void> addPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: false,
    );
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    final existing = books.indexWhere((b) => b.path == path);
    if (existing < 0) {
      books.insert(0, Book(path: path, name: result.files.single.name));
    }
    await saveBooks();
    if (!mounted) return;
    setState(() {});
    await openBook(books.firstWhere((b) => b.path == path));
  }

  Future<void> openBook(Book book) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(book: book)));
    await loadBooks();
  }

  Future<void> removeBook(Book book) async {
    books.removeWhere((b) => b.path == book.path);
    await saveBooks();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('رفيق القراءة', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(onPressed: addPdf, icon: const Icon(Icons.add_rounded), tooltip: 'إضافة كتاب PDF'),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: addPdf,
            backgroundColor: gold,
            foregroundColor: ink,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('فتح كتاب PDF'),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : books.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 76, color: gold),
                            const SizedBox(height: 18),
                            const Text('مكتبتك تبدأ من هنا', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(
                              'افتح ملف PDF من هاتفك، وسنحفظ موضع قراءتك لتعود إليه لاحقاً.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black.withValues(alpha: .62)),
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(onPressed: addPdf, icon: const Icon(Icons.add), label: const Text('إضافة أول كتاب')),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: books.length,
                      itemBuilder: (context, i) {
                        final book = books[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFF5EBD5),
                              child: Icon(Icons.picture_as_pdf, color: gold),
                            ),
                            title: Text(book.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('آخر موضع قراءة: الصفحة ${book.page}'),
                            onTap: () => openBook(book),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'delete') removeBook(book);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'delete', child: Text('إزالة من المكتبة')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      );
}

class ReaderPage extends StatefulWidget {
  final Book book;

  const ReaderPage({super.key, required this.book});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with WidgetsBindingObserver {
  late final PdfController controller;
  int page = 1;
  int totalPages = 1;
  bool darkMode = false;
  bool controlsVisible = true;
  bool landscapeMode = false;
  List<int> bookmarks = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    page = widget.book.page;
    controller = PdfController(
      document: PdfDocument.openFile(widget.book.path),
      initialPage: page,
    );
    loadReaderSettings();
    loadBookmarks();
  }

  Future<void> loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      darkMode = prefs.getBool('reader_dark_mode') ?? false;
    });
  }

  Future<void> toggleDarkMode() async {
    final next = !darkMode;
    setState(() => darkMode = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_dark_mode', next);
  }

  Future<void> loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('marks_${widget.book.path}') ?? [];
    if (mounted) {
      setState(() => bookmarks = raw.map(int.parse).toList()..sort());
    }
  }

  Future<void> savePosition(int value) async {
    page = value;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('books') ?? [];
    final updated = raw.map((entry) {
      final book = Book.fromJson(jsonDecode(entry));
      return jsonEncode(Book(
        path: book.path,
        name: book.name,
        page: book.path == widget.book.path ? value : book.page,
      ).toJson());
    }).toList();
    await prefs.setStringList('books', updated);
    if (mounted) setState(() {});
  }

  Future<void> addBookmark() async {
    if (!bookmarks.contains(page)) bookmarks.add(page);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('marks_${widget.book.path}', bookmarks.map((e) => e.toString()).toList());
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الصفحة $page كعلامة مرجعية')),
    );
  }

  Future<void> goToPage(int value) async {
    if (value < 1 || value > totalPages) return;
    controller.jumpToPage(value);
    await savePosition(value);
    if (mounted) setState(() => controlsVisible = false);
  }

  @override
  void didChangeMetrics() {
    final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final ratio = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final isLandscape = size.width / ratio > size.height / ratio;
    if (isLandscape != landscapeMode && mounted) {
      setState(() {
        landscapeMode = isLandscape;
        controlsVisible = !isLandscape;
      });
      SystemChrome.setEnabledSystemUIMode(
        isLandscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    controller.dispose();
    super.dispose();
  }

  Widget buildReaderControls(BuildContext context, ScrollController sheetScrollController) {
    final surface = darkMode ? const Color(0xFF202127) : Colors.white;
    final foreground = darkMode ? Colors.white : ink;
    return Material(
      color: surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ListView(
        controller: sheetScrollController,
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: darkMode ? Colors.white38 : Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'أدوات القراءة',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: foreground),
                ),
              ),
              IconButton(
                tooltip: 'إخفاء الأدوات',
                onPressed: () => setState(() => controlsVisible = false),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: foreground),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text('الصفحة $page من $totalPages', style: TextStyle(color: foreground))),
              IconButton(
                tooltip: 'الصفحة السابقة',
                onPressed: page > 1 ? () => controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
                icon: Icon(Icons.chevron_right, color: foreground),
              ),
              IconButton(
                tooltip: 'الصفحة التالية',
                onPressed: page < totalPages ? () => controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null,
                icon: Icon(Icons.chevron_left, color: foreground),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: addBookmark,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('حفظ علامة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: toggleDarkMode,
                  icon: Icon(darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  label: Text(darkMode ? 'الوضع النهاري' : 'الوضع الليلي'),
                ),
              ),
            ],
          ),
          if (bookmarks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('العلامات المرجعية', style: TextStyle(fontWeight: FontWeight.bold, color: foreground)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: bookmarks.map((mark) => ActionChip(
                label: Text('صفحة $mark'),
                onPressed: () => goToPage(mark),
              )).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'اسحب القائمة للأعلى لعرض الأدوات، وللأسفل لإخفائها. القراءة تمرير رأسي متواصل.',
            style: TextStyle(fontSize: 11, color: foreground.withValues(alpha: .65)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = darkMode ? const Color(0xFF111216) : const Color(0xFFE9E6DE);
    final foreground = darkMode ? Colors.white : ink;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: ThemeData(
          useMaterial3: true,
          brightness: darkMode ? Brightness.dark : Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: darkMode ? Brightness.dark : Brightness.light),
          scaffoldBackgroundColor: background,
        ),
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            return Scaffold(
              backgroundColor: background,
              appBar: isLandscape
                  ? null
                  : AppBar(
                      backgroundColor: background,
                      foregroundColor: foreground,
                      title: Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                      actions: [
                        IconButton(
                          tooltip: darkMode ? 'الوضع النهاري' : 'الوضع الليلي',
                          onPressed: toggleDarkMode,
                          icon: Icon(darkMode ? Icons.light_mode : Icons.dark_mode),
                        ),
                      ],
                    ),
              body: Stack(
                children: [
                  Positioned.fill(
                    child: darkMode
                        ? ColorFiltered(
                            colorFilter: const ColorFilter.matrix(<double>[
                              -1, 0, 0, 0, 255,
                              0, -1, 0, 0, 255,
                              0, 0, -1, 0, 255,
                              0, 0, 0, 1, 0,
                            ]),
                            child: PdfView(
                              controller: controller,
                              scrollDirection: Axis.vertical,
                              pageSnapping: false,
                              physics: const BouncingScrollPhysics(),
                              onDocumentLoaded: (document) {
                                totalPages = document.pagesCount;
                                if (mounted) setState(() {});
                              },
                              onPageChanged: savePosition,
                              builders: PdfViewBuilders<DefaultBuilderOptions>(
                                options: const DefaultBuilderOptions(),
                                documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                                pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                                errorBuilder: (_, error) => Center(child: Text('تعذر فتح الملف: $error', textAlign: TextAlign.center)),
                              ),
                            ),
                          )
                        : PdfView(
                            controller: controller,
                            scrollDirection: Axis.vertical,
                            pageSnapping: false,
                            physics: const BouncingScrollPhysics(),
                            onDocumentLoaded: (document) {
                              totalPages = document.pagesCount;
                              if (mounted) setState(() {});
                            },
                            onPageChanged: savePosition,
                            builders: PdfViewBuilders<DefaultBuilderOptions>(
                              options: const DefaultBuilderOptions(),
                              documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                              pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                              errorBuilder: (_, error) => Center(child: Text('تعذر فتح الملف: $error', textAlign: TextAlign.center)),
                            ),
                          ),
                  ),
                  if (!isLandscape)
                    DraggableScrollableSheet(
                      initialChildSize: .105,
                      minChildSize: .085,
                      maxChildSize: .68,
                      snap: true,
                      snapSizes: const [.105, .68],
                      builder: buildReaderControls,
                    ),
                  if (isLandscape && controlsVisible)
                    Positioned(
                      top: 12,
                      right: 12,
                      left: 12,
                      child: SafeArea(
                        child: Card(
                          color: darkMode ? const Color(0xEE202127) : const Color(0xEEF8F6F0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text('صفحة $page من $totalPages', style: TextStyle(color: foreground))),
                                IconButton(onPressed: toggleDarkMode, icon: Icon(darkMode ? Icons.light_mode : Icons.dark_mode)),
                                IconButton(onPressed: addBookmark, icon: const Icon(Icons.bookmark_add_outlined)),
                                IconButton(
                                  tooltip: 'إخفاء الأدوات',
                                  onPressed: () => setState(() => controlsVisible = false),
                                  icon: const Icon(Icons.visibility_off_outlined),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (isLandscape && !controlsVisible)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: SafeArea(
                        child: FloatingActionButton.small(
                          heroTag: 'landscape-reader-controls',
                          backgroundColor: darkMode ? const Color(0xDD202127) : const Color(0xEEF8F6F0),
                          foregroundColor: foreground,
                          onPressed: () => setState(() => controlsVisible = true),
                          child: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
