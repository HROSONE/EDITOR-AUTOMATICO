import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EditorAutomaticoApp());
}

class VideoProject {
  const VideoProject({required this.id, required this.title, required this.path, required this.addedAt});
  final String id;
  final String title;
  final String path;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
    'id': id, 'title': title, 'path': path, 'addedAt': addedAt.toIso8601String(),
  };

  factory VideoProject.fromJson(Map<String, dynamic> json) => VideoProject(
    id: json['id'] as String,
    title: json['title'] as String,
    path: json['path'] as String,
    addedAt: DateTime.parse(json['addedAt'] as String),
  );
}

class ProjectStore {
  static const _key = 'saved_video_projects_v1';

  Future<List<VideoProject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final items = jsonDecode(raw) as List<dynamic>;
      return items.map((item) => VideoProject.fromJson(Map<String, dynamic>.from(item as Map)))
        .where((project) => File(project.path).existsSync()).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    } on Object {
      return [];
    }
  }

  Future<void> save(List<VideoProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(projects.map((p) => p.toJson()).toList()));
  }
}

class EditorAutomaticoApp extends StatelessWidget {
  const EditorAutomaticoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Editor Automático',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B6CFF), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101014),
      useMaterial3: true,
    ),
    home: const EditorHomePage(),
  );
}

class EditorHomePage extends StatefulWidget {
  const EditorHomePage({super.key});
  @override
  State<EditorHomePage> createState() => _EditorHomePageState();
}

class _EditorHomePageState extends State<EditorHomePage> {
  final _store = ProjectStore();
  List<VideoProject> _projects = [];
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final projects = await _store.load();
    if (!mounted) return;
    setState(() { _projects = projects; _loading = false; });
  }

  Future<void> _importVideo() async {
    if (_importing) return;
    setState(() { _importing = true; _error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false, withData: false);
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw const FileSystemException('O seletor não forneceu um caminho acessível para o vídeo.');
      }
      final source = File(sourcePath);
      if (!await source.exists()) throw const FileSystemException('O arquivo selecionado não existe.');
      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('\${appDir.path}/videos');
      await mediaDir.create(recursive: true);
      final ext = (picked.extension ?? 'mp4').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final destination = File('\${mediaDir.path}/$id.\${ext.isEmpty ? 'mp4' : ext}');
      await source.copy(destination.path);
      final project = VideoProject(id: id, title: picked.name, path: destination.path, addedAt: DateTime.now());
      final updated = [project, ..._projects];
      await _store.save(updated);
      if (!mounted) return;
      setState(() => _projects = updated);
      await _openProject(project);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível importar o vídeo: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openProject(VideoProject project) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoEditorPage(project: project)));
    await _loadProjects();
  }

  Future<void> _deleteProject(VideoProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir projeto?'),
        content: Text('O vídeo “\${project.title}” será removido do aplicativo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final file = File(project.path);
      if (await file.exists()) await file.delete();
      final updated = _projects.where((p) => p.id != project.id).toList();
      await _store.save(updated);
      if (mounted) setState(() => _projects = updated);
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível excluir: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Editor Automático'), actions: [
      IconButton(tooltip: 'Sobre', onPressed: () => showAboutDialog(
        context: context, applicationName: 'Editor Automático', applicationVersion: '0.2.0',
        applicationLegalese: 'Processamento local. Seus vídeos não são enviados automaticamente.',
      ), icon: const Icon(Icons.info_outline)),
    ]),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _importing ? null : _importVideo,
      icon: _importing
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.add),
      label: Text(_importing ? 'Importando…' : 'Importar vídeo'),
    ),
    body: SafeArea(child: _loading
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(onRefresh: _loadProjects, child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF30244F), Color(0xFF1B1A28)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.movie_filter_outlined, size: 38),
              SizedBox(height: 14),
              Text('Seu vídeo. Seu dispositivo. Seu controle.', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Importe um arquivo, assista e prepare seu projeto. Os arquivos ficam armazenados localmente no aplicativo.'),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 26),
          Row(children: [
            Text('Seus projetos', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text('\${_projects.length}'),
          ]),
          const SizedBox(height: 12),
          if (_projects.isEmpty)
            const Card(child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(children: [
                Icon(Icons.video_library_outlined, size: 42),
                SizedBox(height: 12),
                Text('Nenhum vídeo por aqui ainda.'),
                Text('Toque em “Importar vídeo” para começar.'),
              ]),
            ))
          else
            ..._projects.map((project) => Card(
              margin: const EdgeInsets.only(bottom: 9),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
                title: Text(project.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('Adicionado em \${project.addedAt.day.toString().padLeft(2, '0')}/\${project.addedAt.month.toString().padLeft(2, '0')}/\${project.addedAt.year}'),
                onTap: () => _openProject(project),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) { if (value == 'delete') _deleteProject(project); },
                  itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Excluir projeto'))],
                ),
              ),
            )),
          const SizedBox(height: 26),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Etapas do editor', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const _Stage(title: 'Importação e reprodução local', status: 'Disponível', done: true, icon: Icons.check_circle),
              const _Stage(title: 'Legendas manuais e exportação SRT', status: 'Disponível', done: true, icon: Icons.subtitles),
              const _Stage(title: 'Detecção automática de silêncio (VAD)', status: 'Motor pendente', icon: Icons.graphic_eq),
              const _Stage(title: 'Transcrição automática (Whisper)', status: 'Motor pendente', icon: Icons.record_voice_over),
              const _Stage(title: 'Cortes e renderização MP4', status: 'Motor pendente', icon: Icons.content_cut),
            ]),
          )),
        ],
      )),
    ),
  );
}

class _Stage extends StatelessWidget {
  const _Stage({required this.title, required this.status, required this.icon, this.done = false});
  final String title;
  final String status;
  final IconData icon;
  final bool done;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Icon(icon, size: 20, color: done ? Colors.greenAccent : Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 10),
      Expanded(child: Text(title)),
      const SizedBox(width: 8),
      Text(status, style: Theme.of(context).textTheme.labelSmall),
    ]),
  );
}

class SubtitleCue {
  SubtitleCue({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;
}

class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({super.key, required this.project});
  final VideoProject project;
  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;
  final List<SubtitleCue> _cues = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.project.path));
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      if (mounted) setState(() => _loading = false);
    } on Object catch (error) {
      if (mounted) setState(() { _loading = false; _error = 'Não foi possível abrir o vídeo: $error'; });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _addCue() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final textController = TextEditingController();
    final start = controller.value.position;
    final end = Duration(milliseconds: (start.inMilliseconds + 2500).clamp(0, controller.value.duration.inMilliseconds).toInt());
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova legenda'),
        content: TextField(controller: textController, autofocus: true, maxLines: 3,
          decoration: const InputDecoration(hintText: 'Digite o texto', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, textController.text.trim()), child: const Text('Adicionar')),
        ],
      ),
    );
    textController.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      _cues.add(SubtitleCue(start: start, end: end, text: result));
      _cues.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  String _srtTime(Duration value) {
    final h = value.inHours.toString().padLeft(2, '0');
    final m = (value.inMinutes % 60).toString().padLeft(2, '0');
    final s = (value.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (value.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  String _clock(Duration value) => '\${value.inMinutes.toString().padLeft(2, '0')}:\${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _exportSrt() async {
    if (_cues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione pelo menos uma legenda primeiro.')));
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final base = widget.project.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('\${dir.path}/\${base}_legendas.srt');
      final out = StringBuffer();
      for (var i = 0; i < _cues.length; i++) {
        final cue = _cues[i];
        out.writeln(i + 1);
        out.writeln('\${_srtTime(cue.start)} --> \${_srtTime(cue.end)}');
        out.writeln(cue.text);
        out.writeln();
      }
      await file.writeAsString(out.toString(), flush: true);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/x-subrip')], text: 'Legendas de \${widget.project.title}');
    } on Object catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao exportar SRT: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.project.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Exportar SRT', onPressed: _exportSrt, icon: const Icon(Icons.file_download_outlined))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        AspectRatio(aspectRatio: 16 / 9, child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
          child: Center(child: _loading
            ? const CircularProgressIndicator()
            : _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))
              : controller != null && controller.value.isInitialized
                ? ClipRRect(borderRadius: BorderRadius.circular(14), child: VideoPlayer(controller))
                : const Icon(Icons.videocam_off, size: 48)),
        )),
        if (controller != null && controller.value.isInitialized) ...[
          const SizedBox(height: 12),
          ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) {
            final max = value.duration.inMilliseconds.toDouble().clamp(1, double.infinity);
            return Column(children: [
              Slider(value: value.position.inMilliseconds.toDouble().clamp(0, max).toDouble(), max: max,
                onChanged: (v) => controller.seekTo(Duration(milliseconds: v.round()))),
              Row(children: [
                Text(_clock(value.position)), const Spacer(),
                IconButton.filled(onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow)),
                const Spacer(), Text(_clock(value.duration)),
              ]),
            ]);
          }),
        ],
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('Legendas', style: Theme.of(context).textTheme.titleLarge)),
          FilledButton.tonalIcon(onPressed: _loading || _error != null ? null : _addCue,
            icon: const Icon(Icons.add), label: const Text('Adicionar')),
        ]),
        if (_cues.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 22),
            child: Text('Nenhuma legenda. Posicione o vídeo e adicione uma legenda manualmente. A transcrição automática ainda não está integrada.', textAlign: TextAlign.center))
        else
          ..._cues.asMap().entries.map((entry) {
            final index = entry.key;
            final cue = entry.value;
            return Card(child: ListTile(
              leading: Text('\${index + 1}'),
              title: Text(cue.text),
              subtitle: Text('\${_clock(cue.start)} – \${_clock(cue.end)}'),
              onTap: () => controller?.seekTo(cue.start),
              trailing: IconButton(tooltip: 'Excluir legenda', onPressed: () => setState(() => _cues.removeAt(index)), icon: const Icon(Icons.delete_outline)),
            ));
          }),
        const SizedBox(height: 16),
        const Card(child: Padding(padding: EdgeInsets.all(14),
          child: Text('O SRT é exportado separadamente. Este MVP ainda não corta o vídeo nem grava legendas dentro do MP4.'))),
      ])),
    );
  }
}
