import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_palette.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/ui_kit.dart';

/// One sense of a word.
class DictMeaning {
  DictMeaning(this.partOfSpeech, this.definitions, this.examples);
  final String partOfSpeech;
  final List<String> definitions;
  final List<String> examples;
}

/// A full lookup result: definitions + thesaurus (synonyms/antonyms).
class DictEntry {
  DictEntry({
    required this.word,
    required this.phonetic,
    required this.meanings,
    required this.synonyms,
    required this.antonyms,
  });

  final String word;
  final String phonetic;
  final List<DictMeaning> meanings;
  final List<String> synonyms;
  final List<String> antonyms;
}

class DictionaryService {
  static const _base =
      'https://api.dictionaryapi.dev/api/v2/entries/en/';
  static const _timeout = Duration(seconds: 9);

  /// Returns null when the word has no entry (HTTP 404).
  static Future<DictEntry?> lookup(String word) async {
    final uri = Uri.parse('$_base${Uri.encodeComponent(word.trim())}');
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw Exception('Lookup failed (${res.statusCode})');
    }

    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) return null;

    final meanings = <DictMeaning>[];
    final syn = <String>{};
    final ant = <String>{};
    String phonetic = '';

    for (final entryRaw in list) {
      final entry = entryRaw as Map<String, dynamic>;
      if (phonetic.isEmpty) {
        phonetic = (entry['phonetic'] as String?) ?? '';
        if (phonetic.isEmpty) {
          for (final p in (entry['phonetics'] as List? ?? const [])) {
            final t = (p as Map)['text'] as String?;
            if (t != null && t.isNotEmpty) {
              phonetic = t;
              break;
            }
          }
        }
      }
      for (final mRaw in (entry['meanings'] as List? ?? const [])) {
        final m = mRaw as Map<String, dynamic>;
        for (final s in (m['synonyms'] as List? ?? const [])) {
          syn.add(s.toString());
        }
        for (final a in (m['antonyms'] as List? ?? const [])) {
          ant.add(a.toString());
        }
        final defs = <String>[];
        final examples = <String>[];
        for (final dRaw in (m['definitions'] as List? ?? const [])) {
          final d = dRaw as Map<String, dynamic>;
          final def = d['definition'] as String?;
          if (def != null) defs.add(def);
          final ex = d['example'] as String?;
          if (ex != null && ex.isNotEmpty) examples.add(ex);
          for (final s in (d['synonyms'] as List? ?? const [])) {
            syn.add(s.toString());
          }
          for (final a in (d['antonyms'] as List? ?? const [])) {
            ant.add(a.toString());
          }
        }
        if (defs.isNotEmpty) {
          meanings.add(DictMeaning(
            (m['partOfSpeech'] as String?) ?? '',
            defs,
            examples,
          ));
        }
      }
    }

    return DictEntry(
      word: (list.first as Map)['word'] as String? ?? word,
      phonetic: phonetic,
      meanings: meanings,
      synonyms: syn.toList(),
      antonyms: ant.toList(),
    );
  }
}

class DictionaryCard extends StatefulWidget {
  const DictionaryCard({super.key});

  @override
  State<DictionaryCard> createState() => _DictionaryCardState();
}

class _DictionaryCardState extends State<DictionaryCard> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  DictEntry? _entry;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search([String? word]) async {
    final q = (word ?? _controller.text).trim();
    if (q.isEmpty) return;
    if (word != null) _controller.text = word;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await DictionaryService.lookup(q);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entry = result;
        _error = result == null ? 'No entry found for "$q".' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entry = null;
        _error = 'Network error. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      title: 'Dictionary & thesaurus',
      icon: Icons.menu_book_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      hintText: 'Look up a word…'),
                ),
              ),
              const SizedBox(width: 8),
              SoftButton(
                label: 'Search',
                icon: Icons.search_rounded,
                filled: true,
                onTap: _search,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildResult(),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_error != null) {
      return EmptyHint(_error!, icon: Icons.search_off_rounded);
    }
    final e = _entry;
    if (e == null) {
      return const EmptyHint(
        'Search for a definition, or tap a synonym to explore.',
        icon: Icons.auto_stories_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(e.word,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            if (e.phonetic.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(e.phonetic,
                  style: const TextStyle(
                      color: AppPalette.textSecondary,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
        const SizedBox(height: 12),
        for (final m in e.meanings.take(3)) ...[
          Text(m.partOfSpeech,
              style: const TextStyle(
                  color: AppPalette.lavender,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (var i = 0; i < m.definitions.take(2).length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('•  ${m.definitions[i]}',
                  style: const TextStyle(height: 1.35)),
            ),
          if (m.examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('“${m.examples.first}”',
                  style: const TextStyle(
                      color: AppPalette.textSecondary,
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 8),
        ],
        if (e.synonyms.isNotEmpty)
          _chips('Synonyms', e.synonyms, AppPalette.mint),
        if (e.antonyms.isNotEmpty)
          _chips('Antonyms', e.antonyms, AppPalette.peach),
      ],
    );
  }

  Widget _chips(String label, List<String> words, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in words.take(12))
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _search(w),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: color.withValues(alpha: 0.45)),
                      ),
                      child: Text(w,
                          style: TextStyle(
                              color: color,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
