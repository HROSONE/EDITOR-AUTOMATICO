import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../services/automatic_editor_service.dart';
import '../services/edit_timeline.dart';

class AutomaticTranscriptionPage extends StatefulWidget {
  const AutomaticTranscriptionPage({
    super.key,
    required this.videoPath,
    required this.projectId,
    required this.title,
    required this.sourceDuration,
  });

  final String videoPath;
  final String projectId;
  final String title;
  final Duration sourceDuration;

  @override
  State<AutomaticTranscriptionPage> createState() => _AutomaticTranscriptionPageState();
}

class _AutomaticTranscriptionPageState extends State<AutomaticTranscriptionPage> {
  final _service = AutomaticEditorService();
  bool _busy = false;
  bool _rendering = false;
  bool _restoring = true;
  String _stage = 'O vídeo será processado no próprio aparelho.';
  String? _error;
  String? _srt;
  String? _transcript;
  String? _srtPath;
  String? _audioPath;
  String? _modelPath;
  EditTimeline? _timeline;
  File? _renderedMp4;
  VideoPlayerController? _previewController;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _restoreState();
  }

  @override
  void dispose() {
    if (_busy || _rendering) _service.cancel();
    _previewController?.dispose();
    super.dispose();
  }

  Future<void> _loadPreview(File file) async {
    final previous = _previewController;
    final controller = VideoPlayerController.file(file);
    _previewController = controller;
    await previous?.dispose();
    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'O MP4 foi criado, mas a prévia não abriu: $error');
    }
  }

  Future<void> _restoreState() async {
    try {
      final saved = await _service.loadProjectState(widget.projectId);
      if (saved != null && mounted) {
        final timelineJson = saved['timeline'];
        final path = saved['renderedVideoPath'] as String?;
        setState(() {
          _srt = saved['srt'] as String?;
          _transcript = saved['text'] as String?;
          _srtPath = saved['srtPath'] as String?;
          _audioPath = saved['audioPath'] as String?;
          _modelPath = saved['modelPath'] as String?;
          if (timelineJson is Map) {
            _timeline = EditTimeline.fromJson(Map<String, dynamic>.from(timelineJson));
          }
          if (path != null && File(path).existsSync()) _renderedMp4 = File(path);
          _stage = 'Projeto recuperado do armazenamento local.';
        });
        if (_renderedMp4 != null) await _loadPreview(_renderedMp4!);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Não foi possível recuperar a edição: $error');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _run() async {
    if (_busy || _rendering) return;
    await _previewController?.dispose();
    _previewController = null;
    setState(() {
      _busy = true;
      _error = null;
      _srt = null;
      _transcript = null;
      _srtPath = null;
      _audioPath = null;
      _modelPath = null;
      _timeline = null;
      _renderedMp4 = null;
      _progress = 0;
      _stage = 'Iniciando…';
    });
    try {
      final result = await _service.transcribe(
        videoPath: widget.videoPath,
        projectId: widget.projectId,
        sourceDuration: widget.sourceDuration,
        onStage: (value) {
          if (mounted) setState(() => _stage = value);
        },
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _srt = result.srt;
        _transcript = result.text;
        _srtPath = result.srtPath;
        _audioPath = result.audioPath;
        _modelPath = result.modelPath;
        _timeline = result.timeline;
        _stage = 'Transcrição e plano de cortes concluídos.';
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _stage = 'Não foi possível concluir.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _cancel() {
    _service.cancel();
    setState(() => _stage = 'Solicitando cancelamento…');
  }

  AutomaticTranscription? _currentTranscription() {
    final srt = _srt;
    final transcript = _transcript;
    final srtPath = _srtPath;
    final audioPath = _audioPath;
    final modelPath = _modelPath;
    final timeline = _timeline;
    if (srt == null || transcript == null || srtPath == null ||
        audioPath == null || modelPath == null || timeline == null) {
      return null;
    }
    return AutomaticTranscription(
      srt: srt, text: transcript, srtPath: srtPath, audioPath: audioPath,
      modelPath: modelPath, timeline: timeline,
    );
  }

  Future<void> _persistCurrentState({String? renderedPath}) async {
    final transcription = _currentTranscription();
    if (transcription == null) return;
    await _service.saveProjectState(
      projectId: widget.projectId,
      transcription: transcription,
      renderedVideoPath: renderedPath ?? _renderedMp4?.path,
    );
  }

  Future<void> _restorePause(TimeRange pause) async {
    final current = _timeline;
    if (current == null) return;
    final ranges = [...current.keepRanges, pause]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <TimeRange>[];
    for (final range in ranges) {
      if (merged.isEmpty || range.start > merged.last.end) {
        merged.add(range);
      } else {
        final previous = merged.removeLast();
        merged.add(TimeRange(previous.start, range.end > previous.end ? range.end : previous.end));
      }
    }
    setState(() {
      _timeline = EditTimeline(sourceDuration: current.sourceDuration, keepRanges: merged);
      _renderedMp4 = null;
      _stage = 'Pausa restaurada. O plano de edição foi atualizado.';
    });
    await _persistCurrentState();
  }

  Future<void> _renderMp4() async {
    final srt = _srt;
    final timeline = _timeline;
    if (srt == null || timeline == null || _rendering || _busy) return;
    await _previewController?.dispose();
    _previewController = null;
    setState(() {
      _rendering = true;
      _error = null;
      _renderedMp4 = null;
    });
    try {
      final file = await _service.renderEditedMp4(
        videoPath: widget.videoPath,
        originalSrt: srt,
        projectId: widget.projectId,
        timeline: timeline,
        onStage: (value) {
          if (mounted) setState(() => _stage = value);
        },
      );
      if (mounted) {
        setState(() => _renderedMp4 = file);
        await _loadPreview(file);
        await _persistCurrentState(renderedPath: file.path);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _shareMp4() async {
    final file = _renderedMp4;
    if (file == null || !await file.exists()) return;
    await Share.shareXFiles([XFile(file.path, mimeType: 'video/mp4')],
      text: 'Vídeo editado: ${widget.title}');
  }

  Future<void> _shareSrt() async {
    final original = _srt;
    final timeline = _timeline;
    if (original == null || timeline == null) return;
    final retimed = SrtCodec.write(timeline.retimeCues(SrtCodec.parse(original)));
    final dir = await getApplicationDocumentsDirectory();
    final safeName = widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${dir.path}/${safeName}_automatico.srt');
    await file.writeAsString(retimed, flush: true);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/x-subrip')],
      text: 'Legendas sincronizadas: ${widget.title}');
  }

  String _formatTime(Duration value) {
    final h = value.inHours;
    final m = (value.inMinutes % 60).toString().padLeft(2, '0');
    final s = (value.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (value.inMilliseconds % 1000).toString().padLeft(3, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    final busy = _busy || _rendering;
    return Scaffold(
      appBar: AppBar(title: const Text('Edição automática')),
      body: SafeArea(
        child: _restoring
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'O áudio é processado localmente. O Whisper cria as legendas e o Silero identifica a fala. '
                        'O editor preserva uma margem antes e depois das falas para reduzir o risco de cortar sílabas. '
                        'Na primeira utilização, os modelos são baixados e verificados; depois, o processamento funciona offline.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: busy ? null : _run,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(_srt == null ? 'Analisar e editar automaticamente' : 'Refazer análise automática'),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: _busy && _progress > 0 ? _progress : null),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _cancel,
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar processamento'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(_stage, style: Theme.of(context).textTheme.bodySmall),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (_transcript != null && timeline != null) ...[
                    const SizedBox(height: 20),
                    Text('Resultado da análise', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      Chip(label: Text('${SrtCodec.parse(_srt ?? '').length} legendas')),
                      Chip(label: Text('${timeline.keepRanges.length} trechos mantidos')),
                      Chip(label: Text('${timeline.removedRanges.length} cortes sugeridos')),
                      Chip(label: Text('Economia: ${_formatTime(timeline.removedDuration)}')),
                    ]),
                    const SizedBox(height: 12),
                    Text('Transcrição', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    SelectableText(_transcript!),
                    const SizedBox(height: 20),
                    Text('Plano de cortes', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('As pausas são removidas automaticamente no vídeo final. Se quiser manter uma delas, restaure-a antes de renderizar.'),
                    if (timeline.removedRanges.isEmpty)
                      const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Nenhuma pausa será removida.'))
                    else
                      ...timeline.removedRanges.map((pause) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.content_cut),
                          title: Text('${_formatTime(pause.start)} – ${_formatTime(pause.end)}'),
                          subtitle: Text('Remover ${_formatTime(pause.duration)}'),
                          trailing: TextButton(
                            onPressed: busy ? null : () => _restorePause(pause),
                            child: const Text('Manter'),
                          ),
                        ),
                      )),
                    const SizedBox(height: 16),
                    Text('Trechos que serão mantidos', style: Theme.of(context).textTheme.titleMedium),
                    ...timeline.keepRanges.asMap().entries.map((entry) => ListTile(
                      dense: true,
                      leading: CircleAvatar(radius: 13, child: Text('${entry.key + 1}')),
                      title: Text('${_formatTime(entry.value.start)} – ${_formatTime(entry.value.end)}'),
                      subtitle: Text('Duração: ${_formatTime(entry.value.duration)}'),
                    )),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _shareSrt,
                      icon: const Icon(Icons.subtitles_outlined),
                      label: const Text('Exportar SRT sincronizado com os cortes'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: busy ? null : _renderMp4,
                      icon: _rendering
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.movie_creation_outlined),
                      label: Text(_rendering ? 'Renderizando vídeo…' : 'Aplicar cortes e gerar MP4 final'),
                    ),
                    if (_renderedMp4 != null) ...[
                      const SizedBox(height: 14),
                      if (_previewController != null && _previewController!.value.isInitialized) ...[
                        AspectRatio(
                          aspectRatio: _previewController!.value.aspectRatio,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: VideoPlayer(_previewController!),
                          ),
                        ),
                        ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _previewController!,
                          builder: (context, value, _) => Row(
                            children: [
                              IconButton.filled(
                                onPressed: () => value.isPlaying
                                    ? _previewController!.pause()
                                    : _previewController!.play(),
                                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                              ),
                              Expanded(
                                child: Slider(
                                  value: value.position.inMilliseconds.toDouble()
                                      .clamp(0, value.duration.inMilliseconds.toDouble().clamp(1, double.infinity))
                                      .toDouble(),
                                  max: value.duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble(),
                                  onChanged: (position) => _previewController!.seekTo(
                                    Duration(milliseconds: position.round()),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.verified_outlined),
                          title: const Text('MP4 final validado'),
                          subtitle: Text(_renderedMp4!.path, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(onPressed: _shareMp4, icon: const Icon(Icons.share)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
