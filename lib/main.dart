import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
          brightness: Brightness.dark,
          scaffoldBackgroundColor: ink,
          colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.dark),
          appBarTheme: const AppBarTheme(backgroundColor: ink, foregroundColor: Colors.white),
          cardTheme: CardThemeData(color: const Color(0xFF1B1D22), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
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
  factory Book.fromJson(Map<String, dynamic> j) => Book(path: j['path'], name: j['name'], page: j['page'] ?? 1);
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
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('books') ?? [];
    books = raw.map((e) => Book.fromJson(jsonDecode(e))).where((b) => File(b.path).existsSync()).toList();
    if (mounted) setState(() => loading = false);
  }

  Future<void> saveBooks() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('books', books.map((b) => jsonEncode(b.toJson())).toList());
  }

  Future<void> addPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: false);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final existing = books.indexWhere((b) => b.path == path);
    if (existing < 0) books.insert(0, Book(path: path, name: result.files.single.name));
    await saveBooks();
    if (mounted) {
      setState(() {});
      openBook(books.firstWhere((b) => b.path == path));
    }
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
          appBar: AppBar(title: const Text('رفيق القراءة', style: TextStyle(fontWeight: FontWeight.bold)), actions: [
            IconButton(onPressed: addPdf, icon: const Icon(Icons.add_rounded), tooltip: 'إضافة كتاب PDF')
          ]),
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
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.menu_book_rounded, size: 76, color: gold),
                        const SizedBox(height: 18),
                        const Text('مكتبتك تبدأ من هنا', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('افتح ملف PDF من هاتفك، وسنحفظ موضع قراءتك لتعود إليه لاحقاً.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .65))),
                        const SizedBox(height: 22),
                        FilledButton.icon(onPressed: addPdf, icon: const Icon(Icons.add), label: const Text('إضافة أول كتاب')),
                      ]),
                    ))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      itemCount: books.length,
                      itemBuilder: (context, i) {
                        final b = books[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: const CircleAvatar(backgroundColor: Color(0xFF332B1B), child: Icon(Icons.picture_as_pdf, color: gold)),
                            title: Text(b.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('آخر موضع قراءة: الصفحة ${b.page}'),
                            onTap: () => openBook(b),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) { if (v == 'delete') removeBook(b); },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('إزالة من المكتبة'))],
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

class _ReaderPageState extends State<ReaderPage> {
  late PdfControllerPinch controller;
  int page = 1;
  int totalPages = 1;
  bool autoPlay = false;
  double speed = 1;
  Timer? timer;
  List<int> bookmarks = [];

  @override
  void initState() {
    super.initState();
    page = widget.book.page;
    controller = PdfControllerPinch(document: PdfDocument.openFile(widget.book.path), initialPage: page);
    loadBookmarks();
  }

  Future<void> loadBookmarks() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('marks_${widget.book.path}') ?? [];
    if (mounted) setState(() => bookmarks = raw.map(int.parse).toList()..sort());
  }

  Future<void> savePosition(int value) async {
    page = value;
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('books') ?? [];
    final updated = raw.map((e) {
      final b = Book.fromJson(jsonDecode(e));
      return jsonEncode(Book(path: b.path, name: b.name, page: b.path == widget.book.path ? value : b.page).toJson());
    }).toList();
    await p.setStringList('books', updated);
    if (mounted) setState(() {});
  }

  Future<void> addBookmark() async {
    if (!bookmarks.contains(page)) bookmarks.add(page);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('marks_${widget.book.path}', bookmarks.map((e) => e.toString()).toList());
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ الصفحة $page كعلامة مرجعية')));
    }
  }

  void toggleAuto() {
    if (autoPlay) {
      timer?.cancel();
      setState(() => autoPlay = false);
    } else {
      setState(() => autoPlay = true);
      timer = Timer.periodic(Duration(milliseconds: (5000 / speed).round()), (_) {
        if (!mounted) return;
        if (page < totalPages) {
          controller.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        } else {
          timer?.cancel();
          setState(() => autoPlay = false);
        }
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            actions: [
              IconButton(onPressed: addBookmark, icon: const Icon(Icons.bookmark_add_outlined), tooltip: 'إضافة علامة'),
              PopupMenuButton<int>(
                icon: const Icon(Icons.bookmarks_outlined),
                onSelected: (v) { controller.jumpToPage(v); savePosition(v); },
                itemBuilder: (_) => bookmarks.map((v) => PopupMenuItem(value: v, child: Text('الصفحة $v'))).toList(),
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: PdfViewPinch(
                controller: controller,
                onDocumentLoaded: (document) {
                  totalPages = document.pagesCount;
                  if (mounted) setState(() {});
                },
                onPageChanged: (value) => savePosition(value),
                builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                  options: const DefaultBuilderOptions(),
                  documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                  pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: gold)),
                  errorBuilder: (_, error) => Center(child: Text('تعذر فتح الملف: $error', textAlign: TextAlign.center)),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              decoration: const BoxDecoration(color: Color(0xFF1B1D22), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('صفحة $page من $totalPages'),
                  Row(children: [
                    IconButton(onPressed: page > 1 ? () => controller.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_right)),
                    IconButton(onPressed: page < totalPages ? () => controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut) : null, icon: const Icon(Icons.chevron_left)),
                  ]),
                ]),
                Row(children: [
                  IconButton(onPressed: toggleAuto, icon: Icon(autoPlay ? Icons.pause_circle : Icons.play_circle, color: gold, size: 34)),
                  const Text('التمرير التلقائي'),
                  const Spacer(),
                  Text('السرعة ${speed.toStringAsFixed(1)}×'),
                ]),
                Slider(value: speed, min: .5, max: 3, divisions: 5, activeColor: gold, onChanged: (v) {
                  setState(() => speed = v);
                  if (autoPlay) { timer?.cancel(); timer = null; toggleAuto(); }
                }),
                const Text('كبّر الصفحة بإصبعيك. حفظ موضع القراءة والعلامات يتم تلقائياً.', style: TextStyle(fontSize: 11, color: Colors.white60)),
              ]),
            ),
          ]),
        ),
      );
}
