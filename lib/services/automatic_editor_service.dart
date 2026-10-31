import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

class DetectedPause {
  const DetectedPause({required this.start, required this.end});
  final Duration start;
  final Duration end;
  Duration get duration => end - start;
}

class AutomaticTranscription {
  const AutomaticTranscription({
    required this.srt,
    required this.text,
    required this.audioPath,
    required this.modelPath,
    required this.longPauses,
  });

  final String srt;
  final String text;
  final String audioPath;
  final String modelPath;
  final List<DetectedPause> longPauses;
}

/// Local-only audio preparation and Portuguese transcription.
///
/// The model is downloaded only after the user explicitly starts the operation.
/// Video/audio bytes are never uploaded by this service.
class AutomaticEditorService {
  static const modelFileName = 'ggml-tiny.bin';
  static const modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin';

  Future<AutomaticTranscription> transcribe({
    required String videoPath,
    required String projectId,
    required void Function(String stage) onStage,
    required void Function(double progress) onProgress,
  }) async {
    final video = File(videoPath);
    if (!await video.exists()) {
      throw const FileSystemException('O vídeo original não foi encontrado.');
    }

    final support = await getApplicationSupportDirectory();
    final workDir = Directory('${support.path}/automatic_editor/$projectId');
    await workDir.create(recursive: true);
    final wav = File('${workDir.path}/audio_16k_mono.wav');

    onStage('Preparando áudio do vídeo…');
    final command = [
      '-y',
      '-i', _quote(video.path),
      '-vn',
      '-ac', '1',
      '-ar', '16000',
      '-c:a', 'pcm_s16le',
      _quote(wav.path),
    ].join(' ');
    final extraction = await FFmpegKit.execute(command);
    final extractionCode = await extraction.getReturnCode();
    if (!ReturnCode.isSuccess(extractionCode) || !await wav.exists()) {
      final logs = await extraction.getOutput();
      throw StateError('Não foi possível extrair o áudio. ${logs ?? 'FFmpeg falhou.'}');
    }

    onStage('Verificando o modelo de português…');
    final manager = WhisperModelManager();
    WhisperEngine? engine;
    WhisperVad? vad;
    try {
      var model = await manager.find(modelFileName);
      if (model == null) {
        onStage('Baixando o modelo Whisper Tiny (multilíngue)…');
        await for (final item in manager.download(
          Uri.parse(modelUrl),
          modelFileName,
        )) {
          onProgress(item.fraction.clamp(0.0, 1.0));
        }
        model = await manager.find(modelFileName);
      }
      if (model == null) {
        throw StateError('O download do modelo não foi concluído.');
      }

      onStage('Carregando Whisper no dispositivo…');
      engine = await WhisperEngine.load(model.path);
      onStage('Transcrevendo em português…');
      final samples = await WhisperAudio.readWav(wav);

      onStage('Baixando/verificando o detector Silero VAD…');
      var vadModel = await manager.findCatalogModel(WhisperModelCatalog.sileroVad);
      if (vadModel == null) {
        await for (final item in manager.downloadCatalogModel(WhisperModelCatalog.sileroVad)) {
          onProgress(item.fraction.clamp(0.0, 1.0));
        }
        vadModel = await manager.findCatalogModel(WhisperModelCatalog.sileroVad);
      }
      if (vadModel == null) {
        throw StateError('Não foi possível instalar o modelo Silero VAD.');
      }
      onStage('Detectando fala e pausas…');
      vad = WhisperVad.load(vadModel.path, useGpu: false, threads: 2);
      final speechRanges = vad.segments(
        samples,
        threshold: 0.5,
        minSpeechMs: 250,
        minSilenceMs: 500,
        speechPadMs: 140,
      );
      final longPauses = <DetectedPause>[];
      for (var i = 1; i < speechRanges.length; i++) {
        final gapStart = speechRanges[i - 1].end;
        final gapEnd = speechRanges[i].start;
        if (gapEnd - gapStart >= const Duration(milliseconds: 1200)) {
          longPauses.add(DetectedPause(start: gapStart, end: gapEnd));
        }
      }

      onStage('Transcrevendo em português…');
      final task = engine.transcribe(
        samples,
        options: const TranscribeOptions(
          language: 'pt',
          tokenTimestamps: true,
          threads: 4,
          noContext: true,
        ),
      );
      task.progress.listen((value) {
        onProgress((value / 100).clamp(0.0, 1.0));
      });
      final result = await task.result;
      final srt = result.toSrt();
      if (srt.trim().isEmpty) {
        throw StateError('O Whisper não encontrou fala para legendar neste vídeo.');
      }

      final srtFile = File('${workDir.path}/legendas_automaticas.srt');
      await srtFile.writeAsString(srt, flush: true);
      onProgress(1);
      return AutomaticTranscription(
        srt: srt,
        text: result.text,
        audioPath: wav.path,
        modelPath: model.path,
        longPauses: longPauses,
      );
    } finally {
      vad?.dispose();
      await engine?.dispose();
      await manager.close();
    }
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
