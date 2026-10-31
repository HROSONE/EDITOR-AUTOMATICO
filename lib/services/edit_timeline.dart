class TimeRange {
  const TimeRange(this.start, this.end);
  final Duration start;
  final Duration end;
  Duration get duration => end - start;

  @override
  bool operator ==(Object other) => other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
  Map<String, int> toJson() => {'startMs': start.inMilliseconds, 'endMs': end.inMilliseconds};
  factory TimeRange.fromJson(Map<String, dynamic> json) => TimeRange(
    Duration(milliseconds: json['startMs'] as int),
    Duration(milliseconds: json['endMs'] as int),
  );
}

class SubtitleCueData {
  const SubtitleCueData({required this.start, required this.end, required this.text});
  final Duration start;
  final Duration end;
  final String text;
}

class EditTimeline {
  const EditTimeline({required this.sourceDuration, required this.keepRanges});
  final Duration sourceDuration;
  final List<TimeRange> keepRanges;

  Duration get outputDuration => keepRanges.fold(Duration.zero, (total, range) => total + range.duration);
  Duration get removedDuration => sourceDuration - outputDuration;

  List<TimeRange> get removedRanges {
    final removed = <TimeRange>[];
    var cursor = Duration.zero;
    for (final range in keepRanges) {
      if (range.start > cursor) removed.add(TimeRange(cursor, range.start));
      cursor = range.end;
    }
    if (cursor < sourceDuration) removed.add(TimeRange(cursor, sourceDuration));
    return removed;
  }

  factory EditTimeline.fromSpeech({
    required Duration sourceDuration,
    required List<TimeRange> speechRanges,
    Duration leadIn = const Duration(milliseconds: 320),
    Duration tail = const Duration(milliseconds: 420),
    Duration mergeGap = const Duration(milliseconds: 350),
  }) {
    if (sourceDuration <= Duration.zero || speechRanges.isEmpty) {
      return EditTimeline(sourceDuration: sourceDuration,
        keepRanges: sourceDuration > Duration.zero ? [TimeRange(Duration.zero, sourceDuration)] : const []);
    }
    final sorted = speechRanges
      .where((r) => r.end > Duration.zero && r.start < sourceDuration)
      .map((r) {
        final start = r.start - leadIn;
        final end = r.end + tail;
        return TimeRange(start < Duration.zero ? Duration.zero : start,
          end > sourceDuration ? sourceDuration : end);
      })
      .where((r) => r.duration >= const Duration(milliseconds: 180))
      .toList()..sort((a, b) => a.start.compareTo(b.start));
    if (sorted.isEmpty) {
      return EditTimeline(sourceDuration: sourceDuration, keepRanges: [TimeRange(Duration.zero, sourceDuration)]);
    }
    final merged = <TimeRange>[];
    var current = sorted.first;
    for (final next in sorted.skip(1)) {
      if (next.start - current.end <= mergeGap) {
        current = TimeRange(current.start, next.end > current.end ? next.end : current.end);
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
    final kept = merged.fold(Duration.zero, (sum, r) => sum + r.duration);
    if (kept < const Duration(milliseconds: 500) || kept.inMilliseconds / sourceDuration.inMilliseconds < 0.08) {
      return EditTimeline(sourceDuration: sourceDuration, keepRanges: [TimeRange(Duration.zero, sourceDuration)]);
    }
    return EditTimeline(sourceDuration: sourceDuration, keepRanges: merged);
  }

  Duration mapToOutput(Duration sourceTime) {
    if (keepRanges.isEmpty) return Duration.zero;
    var offset = Duration.zero;
    for (final range in keepRanges) {
      if (sourceTime <= range.start) return offset;
      if (sourceTime <= range.end) return offset + (sourceTime - range.start);
      offset += range.duration;
    }
    return outputDuration;
  }

  List<SubtitleCueData> retimeCues(List<SubtitleCueData> cues) {
    final result = <SubtitleCueData>[];
    for (final cue in cues) {
      final start = mapToOutput(cue.start);
      final end = mapToOutput(cue.end);
      if (end - start < const Duration(milliseconds: 80)) continue;
      result.add(SubtitleCueData(start: start, end: end, text: cue.text));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  Map<String, Object?> toJson() => {
    'sourceDurationMs': sourceDuration.inMilliseconds,
    'keepRanges': keepRanges.map((r) => r.toJson()).toList(),
  };

  factory EditTimeline.fromJson(Map<String, dynamic> json) => EditTimeline(
    sourceDuration: Duration(milliseconds: json['sourceDurationMs'] as int),
    keepRanges: (json['keepRanges'] as List<dynamic>)
      .map((item) => TimeRange.fromJson(Map<String, dynamic>.from(item as Map))).toList(),
  );
}

class SrtCodec {
  static Duration parseTimestamp(String value) {
    final normalized = value.trim().replaceAll('.', ',');
    final match = RegExp(r'^(\d{2,}):(\d{2}):(\d{2}),(\d{3})$').firstMatch(normalized);
    if (match == null) throw FormatException('Timestamp SRT inválido: $value');
    return Duration(hours: int.parse(match.group(1)!), minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!), milliseconds: int.parse(match.group(4)!));
  }

  static String formatTimestamp(Duration value) {
    final safe = value.isNegative ? Duration.zero : value;
    final h = safe.inHours.toString().padLeft(2, '0');
    final m = (safe.inMinutes % 60).toString().padLeft(2, '0');
    final s = (safe.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (safe.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  static List<SubtitleCueData> parse(String source) {
    final cues = <SubtitleCueData>[];
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return cues;
    for (final block in normalized.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n');
      final timingLine = lines.indexWhere((line) => line.contains('-->'));
      if (timingLine < 0 || timingLine + 1 >= lines.length) continue;
      final times = lines[timingLine].split('-->');
      if (times.length != 2) continue;
      final text = lines.skip(timingLine + 1).join('\n').trim();
      if (text.isEmpty) continue;
      try {
        final start = parseTimestamp(times[0]);
        final end = parseTimestamp(times[1]);
        if (end > start) cues.add(SubtitleCueData(start: start, end: end, text: text));
      } on FormatException {
        continue;
      }
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static String write(List<SubtitleCueData> cues) {
    final out = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      out.writeln(i + 1);
      out.writeln('${formatTimestamp(cue.start)} --> ${formatTimestamp(cue.end)}');
      out.writeln(cue.text);
      out.writeln();
    }
    return out.toString();
  }
}
