import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/automatic_editor_service.dart';

class AutomaticTranscriptionPage extends StatefulWidget {
  const AutomaticTranscriptionPage({
    super.key,
    required this.videoPath,
    required this.projectId,
    required this.title,
  });

  final String videoPath;
  final String projectId;
  final String title;

  @override
  State<AutomaticTranscriptionPage> createState() => _AutomaticTranscriptionPageState();
}

class _AutomaticTranscriptionPageState extends State<AutomaticTranscriptionPage> {
  final _service = AutomaticEditorService();
  bool _busy = false;
  String _stage = 'O vídeo será processado no próprio aparelho.';
  String? _error;
  String? _srt;
  String? _transcript;
  double _progress = 0;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _srt = null;
      _transcript = null;
      _progress = 0;
      _stage = 'Iniciando…';
    });
    try {
      final result = await _service.transcribe(
        videoPath: widget.videoPath,
        projectId: widget.projectId,
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
        _stage = 'Transcrição concluída.';
      });
    } on Object catch (error) {
      if (mounted) setState(() {
        _error = error.toString();
        _stage = 'Não foi possível concluir.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareSrt() async {
    final content = _srt;
    if (content == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final safeName = widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${dir.path}/${safeName}_automatico.srt');
    await file.writeAsString(content, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/x-subrip')],
      text: 'Legendas automáticas de ${widget.title}',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transcrição automática')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'O áudio é extraído localmente e transcrito em português pelo Whisper. '
                'Na primeira execução, o aplicativo baixa o modelo multilíngue Tiny (aproximadamente 75 MB). '
                'Depois, a transcrição funciona offline.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_busy ? 'Processando…' : 'Gerar legendas automaticamente'),
          ),
          const SizedBox(height: 12),
          if (_busy) LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          Text(_stage, style: Theme.of(context).textTheme.bodySmall),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_transcript != null) ...[
            const SizedBox(height: 20),
            Text('Transcrição', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SelectableText(_transcript!),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _shareSrt,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Exportar legendas SRT'),
            ),
          ],
        ],
      ),
    ),
  );
}
