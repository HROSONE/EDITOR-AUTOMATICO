import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import 'edit_timeline.dart';

class AutomaticTranscription {
  const AutomaticTranscription({
    required this.srt, required this.text, required this.audioPath,
    required this.modelPath, required this.timeline, required this.srtPath,
  });
  final String srt;
  final String text;
  final String audioPath;
  final String modelPath;
  final EditTimeline timeline;
  final String srtPath;
  List<TimeRange> get longPauses => timeline.removedRanges
      .where((r) => r.duration >= const Duration(milliseconds: 1200)).toList();
}

class AutomaticEditorService {
  WhisperTask? _activeWhisperTask;
  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
    _activeWhisperTask?.cancel();
    FFmpegKit.cancel();
  }

  Future<Directory> _projectDirectory(String projectId) async {
    final support = await getApplicationSupportDirectory();
    final safeId = projectId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final directory = Directory('${support.path}/automatic_editor/$safeId');
    await directory.create(recursive: true);
    return directory;
  }

  Future<AutomaticTranscription> transcribe({
    required String videoPath,
    required String projectId,
    required Duration sourceDuration,
    required void Function(String stage) onStage,
    required void Function(double progress) onProgress,
  }) async {
    _cancelRequested = false;
    final video = File(videoPath);
    if (!await video.exists()) throw const FileSystemException('O vídeo original não foi encontrado.');
    if (sourceDuration <= Duration.zero) throw StateError('A duração do vídeo é inválida.');

    final workDir = await _projectDirectory(projectId);
    final wav = File('${workDir.path}/audio_16k_mono.wav');
    onStage('Preparando áudio do vídeo…');
    final extraction = await FFmpegKit.execute([
      '-y', '-i', _quote(video.path), '-vn', '-ac', '1', '-ar', '16000',
      '-c:a', 'pcm_s16le', _quote(wav.path),
    ].join(' '));
    final extractionCode = await extraction.getReturnCode();
    if (_cancelRequested || ReturnCode.isCancel(extractionCode)) throw StateError('Processamento cancelado.');
    if (!ReturnCode.isSuccess(extractionCode) || !await wav.exists() || await wav.length() < 44) {
      throw StateError('Não foi possível extrair o áudio. ${await extraction.getOutput() ?? 'FFmpeg falhou.'}');
    }

    onStage('Verificando o modelo multilíngue Whisper Tiny…');
    final manager = WhisperModelManager();
    WhisperEngine? engine;
    WhisperVad? vad;
    try {
      var model = await manager.findCatalogModel(WhisperModelCatalog.tiny);
      if (model == null) {
        onStage('Baixando modelo Whisper Tiny verificado…');
        await for (final item in manager.downloadCatalogModel(WhisperModelCatalog.tiny)) {
          if (_cancelRequested) throw StateError('Download cancelado.');
          onProgress((item.fraction ?? 0.0).clamp(0.0, 1.0).toDouble());
        }
        model = await manager.findCatalogModel(WhisperModelCatalog.tiny);
      }
      if (model == null) throw StateError('O modelo Whisper não foi instalado corretamente.');

      onStage('Carregando Whisper no dispositivo…');
      engine = await WhisperEngine.load(model.path);
      final samples = await WhisperAudio.readWav(wav);

      onStage('Verificando modelo Silero VAD…');
      var vadModel = await manager.findCatalogModel(WhisperModelCatalog.sileroVad);
      if (vadModel == null) {
        onStage('Baixando detector Silero VAD verificado…');
        await for (final item in manager.downloadCatalogModel(WhisperModelCatalog.sileroVad)) {
          if (_cancelRequested) throw StateError('Download cancelado.');
          onProgress(item.fraction.clamp(0.0, 1.0).toDouble());
        }
        vadModel = await manager.findCatalogModel(WhisperModelCatalog.sileroVad);
      }
      if (vadModel == null) throw StateError('O detector Silero VAD não foi instalado corretamente.');

      onStage('Detectando fala e planejando cortes seguros…');
      vad = WhisperVad.load(vadModel.path, useGpu: false, threads: 2);
      final speech = vad.segments(samples, threshold: 0.5, minSpeechMs: 250,
        minSilenceMs: 500, speechPadMs: 120);
      final timeline = EditTimeline.fromSpeech(
        sourceDuration: sourceDuration,
        speechRanges: speech.map((s) => TimeRange(s.start, s.end)).toList(),
      );

      if (_cancelRequested) throw StateError('Processamento cancelado.');
      onStage('Transcrevendo em português…');
      final task = engine.transcribe(samples, options: const TranscribeOptions(
        language: 'pt', tokenTimestamps: true, threads: 4, noContext: true,
      ));
      _activeWhisperTask = task;
      final subscription = task.progress.listen((value) {
        if (!_cancelRequested) onProgress((value / 100).clamp(0.0, 1.0).toDouble());
      });
      late final WhisperResult result;
      try {
        result = await task.result;
      } finally {
        await subscription.cancel();
        _activeWhisperTask = null;
      }
      if (_cancelRequested) throw StateError('Transcrição cancelada.');

      final srt = result.toSrt();
      if (srt.trim().isEmpty) throw StateError('O Whisper não encontrou fala para legendar neste vídeo.');
      final srtFile = File('${workDir.path}/legendas_originais.srt');
      await srtFile.writeAsString(srt, flush: true);
      final transcription = AutomaticTranscription(
        srt: srt, text: result.text, audioPath: wav.path,
        modelPath: model.path, timeline: timeline, srtPath: srtFile.path,
      );
      await saveProjectState(projectId: projectId, transcription: transcription);
      onProgress(1);
      return transcription;
    } finally {
      _activeWhisperTask = null;
      vad?.dispose();
      engine?.dispose();
      manager.close();
    }
  }

  Future<void> saveProjectState({
    required String projectId,
    required AutomaticTranscription transcription,
    String? renderedVideoPath,
  }) async {
    final directory = await _projectDirectory(projectId);
    final file = File('${directory.path}/project_state.json');
    await file.writeAsString(jsonEncode({
      'version': 1, 'srt': transcription.srt, 'text': transcription.text,
      'audioPath': transcription.audioPath, 'modelPath': transcription.modelPath,
      'srtPath': transcription.srtPath, 'timeline': transcription.timeline.toJson(),
      'renderedVideoPath': renderedVideoPath,
      'updatedAt': DateTime.now().toIso8601String(),
    }), flush: true);
  }

  Future<Map<String, dynamic>?> loadProjectState(String projectId) async {
    final directory = await _projectDirectory(projectId);
    final file = File('${directory.path}/project_state.json');
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } on Object {
      return null;
    }
  }

  Future<File> renderEditedMp4({
    required String videoPath,
    required String originalSrt,
    required String projectId,
    required EditTimeline timeline,
    required void Function(String stage) onStage,
  }) async {
    _cancelRequested = false;
    if (timeline.keepRanges.isEmpty) throw StateError('O plano de edição não contém trechos de vídeo.');
    final source = File(videoPath);
    if (!await source.exists()) throw const FileSystemException('O vídeo original não foi encontrado.');
    final directory = await _projectDirectory(projectId);
    final retimedCues = timeline.retimeCues(SrtCodec.parse(originalSrt));
    final retimedSrt = File('${directory.path}/legendas_editadas.srt');
    await retimedSrt.writeAsString(SrtCodec.write(retimedCues), flush: true);

    onStage('Verificando faixas de áudio e vídeo…');
    final probe = await FFprobeKit.getMediaInformation(videoPath);
    final media = await probe.getMediaInformation();
    if (media == null) throw StateError('Não foi possível ler as informações do vídeo.');
    final streams = media.getStreams() ?? [];
    final hasAudio = streams.any((stream) => stream.getType() == 'audio');
    if (!streams.any((stream) => stream.getType() == 'video')) {
      throw StateError('O arquivo não contém uma faixa de vídeo reconhecida.');
    }

    final graph = StringBuffer();
    for (var i = 0; i < timeline.keepRanges.length; i++) {
      final range = timeline.keepRanges[i];
      final start = _seconds(range.start);
      final end = _seconds(range.end);
      graph.write('[0:v:0]trim=start=$start:end=$end,setpts=PTS-STARTPTS[v$i];');
      if (hasAudio) graph.write('[0:a:0]atrim=start=$start:end=$end,asetpts=PTS-STARTPTS[a$i];');
    }
    if (hasAudio) {
      final inputs = List.generate(timeline.keepRanges.length, (i) => '[v$i][a$i]').join();
      graph.write('$inputs'
          'concat=n=${timeline.keepRanges.length}:v=1:a=1[vcat][acat];');
    } else {
      final inputs = List.generate(timeline.keepRanges.length, (i) => '[v$i]').join();
      graph.write('$inputs'
          'concat=n=${timeline.keepRanges.length}:v=1:a=0[vcat];');
    }
    graph.write('[vcat]subtitles=filename=\'${_escapeFilterPath(retimedSrt.path)}\':charenc=UTF-8[vout]');

    final filterScript = File('${directory.path}/render_filter.txt');
    await filterScript.writeAsString(graph.toString(), flush: true);
    final temporary = File('${directory.path}/video_final_tmp.mp4');
    final output = File('${directory.path}/video_final.mp4');
    if (await temporary.exists()) await temporary.delete();

    onStage('Aplicando cortes e sincronizando legendas…');
    final command = [
      '-y', '-i', _quote(source.path), '-filter_complex_script', _quote(filterScript.path),
      '-map', '[vout]',
      if (hasAudio) ...['-map', '[acat]', '-c:a', 'aac', '-b:a', '160k'],
      '-c:v', 'mpeg4', '-q:v', '3', '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart', _quote(temporary.path),
    ].join(' ');
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    if (_cancelRequested || ReturnCode.isCancel(code)) {
      if (await temporary.exists()) await temporary.delete();
      throw StateError('Renderização cancelada.');
    }
    if (!ReturnCode.isSuccess(code) || !await temporary.exists() || await temporary.length() < 1024) {
      final logs = await session.getOutput();
      if (await temporary.exists()) await temporary.delete();
      throw StateError('Falha ao renderizar o MP4 editado. ${logs ?? 'FFmpeg falhou.'}');
    }

    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);
    onStage('Validando arquivo MP4 final…');
    final validation = await FFprobeKit.getMediaInformation(output.path);
    final validatedMedia = await validation.getMediaInformation();
    final outputStreams = validatedMedia?.getStreams() ?? [];
    final outputDurationSeconds = double.tryParse(validatedMedia?.getDuration() ?? '');
    final expectedDurationSeconds = timeline.outputDuration.inMilliseconds / 1000;
    final toleranceSeconds = expectedDurationSeconds < 10 ? 2.0 : expectedDurationSeconds * 0.05;
    final hasVideoOutput = outputStreams.any((stream) => stream.getType() == 'video');
    final hasAudioOutput = outputStreams.any((stream) => stream.getType() == 'audio');
    if (validatedMedia == null ||
        outputDurationSeconds == null ||
        !hasVideoOutput ||
        (hasAudio && !hasAudioOutput) ||
        (outputDurationSeconds - expectedDurationSeconds).abs() > toleranceSeconds) {
      await output.delete();
      throw StateError('O MP4 foi criado, mas falhou na validação de faixas ou duração.');
    }
    onStage('Vídeo editado e validado.');
    return output;
  }

  String _seconds(Duration duration) =>
      (duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(6);

  String _escapeFilterPath(String path) => path
      .replaceAll(r'\', r'\\').replaceAll(':', r'\:').replaceAll("'", r"\'");

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
