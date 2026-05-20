// Generates assets/sounds/alarm.wav — a calm, bell-like ascending chime that
// loops cleanly (it ends in silence so audioplayers' loop mode doesn't click).
//
// Run once after changing the sound:  dart run tool/gen_alarm.dart
//
// Pure Dart, no Flutter — synthesizes 16-bit mono PCM and wraps it in a
// minimal RIFF/WAVE header.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int _sampleRate = 44100;

void main() {
  // A gentle C-major arpeggio (C5 E5 G5 C6) — soft attack, long bell decay.
  const notes = <double>[523.25, 659.25, 783.99, 1046.50];
  const noteDur = 0.42; // seconds of audible tone per note
  const gap = 0.10; // small overlap-free spacing between notes
  const tail = 0.85; // trailing silence so the loop breathes

  final total =
      ((notes.length * (noteDur + gap)) + tail) * _sampleRate;
  final samples = Float64List(total.round());

  for (var n = 0; n < notes.length; n++) {
    final freq = notes[n];
    final startSample = (n * (noteDur + gap) * _sampleRate).round();
    final lenSamples = (noteDur * _sampleRate).round();
    for (var i = 0; i < lenSamples; i++) {
      final t = i / _sampleRate;
      // Exponential decay envelope with a 6 ms fade-in (no attack click).
      final env = exp(-4.2 * t) * (1 - exp(-t / 0.006));
      // Fundamental plus a quiet second harmonic for a soft bell timbre.
      final v = sin(2 * pi * freq * t) +
          0.32 * sin(2 * pi * freq * 2 * t) +
          0.12 * sin(2 * pi * freq * 3 * t);
      final idx = startSample + i;
      if (idx < samples.length) samples[idx] += 0.42 * env * v;
    }
  }

  // Normalize to avoid clipping from overlapping harmonics.
  var peak = 0.0;
  for (final s in samples) {
    peak = max(peak, s.abs());
  }
  final scale = peak > 0 ? 0.89 / peak : 1.0;

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i] * scale * 32767).clamp(-32768, 32767).round();
  }

  final bytes = _wav(pcm, _sampleRate);
  final out = File('assets/sounds/alarm.wav');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  stdout.writeln(
      'Wrote ${out.path} (${bytes.length} bytes, '
      '${(pcm.length / _sampleRate).toStringAsFixed(2)}s)');
}

Uint8List _wav(Int16List pcm, int sampleRate) {
  final dataBytes = pcm.length * 2;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  str('RIFF');
  u32(36 + dataBytes);
  str('WAVE');
  str('fmt ');
  u32(16); // PCM fmt chunk size
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate (mono, 16-bit)
  u16(2); // block align
  u16(16); // bits per sample
  str('data');
  u32(dataBytes);
  final le = ByteData(dataBytes);
  for (var i = 0; i < pcm.length; i++) {
    le.setInt16(i * 2, pcm[i], Endian.little);
  }
  b.add(le.buffer.asUint8List());
  return b.toBytes();
}
