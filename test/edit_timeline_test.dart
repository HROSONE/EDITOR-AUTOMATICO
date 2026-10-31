import 'package:flutter_test/flutter_test.dart';
import 'package:editor_automatico/services/edit_timeline.dart';

void main() {
  group('EditTimeline', () {
    test('preserves speech margins and removes long silent gaps', () {
      final timeline = EditTimeline.fromSpeech(
        sourceDuration: const Duration(seconds: 10),
        speechRanges: const [
          TimeRange(Duration(seconds: 1), Duration(seconds: 2)),
          TimeRange(Duration(seconds: 5), Duration(seconds: 6)),
          TimeRange(Duration(seconds: 8), Duration(seconds: 9)),
        ],
      );

      expect(timeline.keepRanges, hasLength(3));
      expect(timeline.keepRanges.first.start, const Duration(milliseconds: 680));
      expect(timeline.keepRanges.first.end, const Duration(milliseconds: 2420));
      expect(timeline.removedRanges, hasLength(4));
      expect(timeline.outputDuration, lessThan(const Duration(seconds: 10)));
      expect(timeline.removedDuration, greaterThan(const Duration(seconds: 4)));
    });

    test('does not cut a video when VAD finds no speech', () {
      final timeline = EditTimeline.fromSpeech(
        sourceDuration: const Duration(seconds: 12),
        speechRanges: const [],
      );
      expect(timeline.keepRanges, [TimeRange(Duration.zero, const Duration(seconds: 12))]);
      expect(timeline.removedRanges, isEmpty);
    });

    test('maps timestamps across removed sections', () {
      final timeline = EditTimeline(
        sourceDuration: const Duration(seconds: 10),
        keepRanges: const [
          TimeRange(Duration(seconds: 1), Duration(seconds: 3)),
          TimeRange(Duration(seconds: 6), Duration(seconds: 9)),
        ],
      );
      expect(timeline.mapToOutput(const Duration(seconds: 2)), const Duration(seconds: 1));
      expect(timeline.mapToOutput(const Duration(seconds: 7)), const Duration(seconds: 3));
      expect(timeline.mapToOutput(const Duration(seconds: 5)), const Duration(seconds: 2));
    });

    test('round-trips the timeline through JSON', () {
      final original = EditTimeline.fromSpeech(
        sourceDuration: const Duration(seconds: 10),
        speechRanges: const [TimeRange(Duration(seconds: 1), Duration(seconds: 3))],
      );
      final restored = EditTimeline.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );
      expect(restored.sourceDuration, original.sourceDuration);
      expect(restored.keepRanges, original.keepRanges);
    });
  });

  group('SrtCodec', () {
    test('parses and writes multiline SRT', () {
      const input = '1\n00:00:01,000 --> 00:00:02,500\nOlá mundo\nsegunda linha\n\n';
      final cues = SrtCodec.parse(input);
      expect(cues, hasLength(1));
      expect(cues.single.text, 'Olá mundo\nsegunda linha');
      expect(SrtCodec.parse(SrtCodec.write(cues)), hasLength(1));
    });

    test('retimes subtitles after removed pauses', () {
      final timeline = EditTimeline(
        sourceDuration: const Duration(seconds: 10),
        keepRanges: const [
          TimeRange(Duration(seconds: 1), Duration(seconds: 3)),
          TimeRange(Duration(seconds: 6), Duration(seconds: 9)),
        ],
      );
      final cues = timeline.retimeCues([
        SubtitleCueData(
          start: const Duration(seconds: 6, milliseconds: 500),
          end: const Duration(seconds: 7),
          text: 'Depois do corte',
        ),
      ]);
      expect(cues, hasLength(1));
      expect(cues.single.start, const Duration(seconds: 2, milliseconds: 500));
      expect(cues.single.end, const Duration(seconds: 3));
    });

    test('accepts dot or comma decimal separators', () {
      expect(SrtCodec.parseTimestamp('00:00:01.250'), const Duration(milliseconds: 1250));
      expect(SrtCodec.parseTimestamp('00:00:01,250'), const Duration(milliseconds: 1250));
    });
  });
}
