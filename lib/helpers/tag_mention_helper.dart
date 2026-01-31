// lib/helpers/tag_mention_helper.dart
class TagMentionHelper {
  static final RegExp hashtag = RegExp(r'\B#([a-zA-Z0-9_]+)');
  static final RegExp mention = RegExp(r'\B@([a-zA-Z0-9_\.]+)'); // allow dot

  // Extract mentions from text
  static List<String> extractMentions(String text) {
    return mention
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  // Extract hashtags from text
  static List<String> extractHashtags(String text) {
    return hashtag
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet()
        .toList();
  }

  /// Split into parts: normal, hashtag, mention
  /// part = { text, type: "text"|"hashtag"|"mention", value? }
  static List<Map<String, dynamic>> split(String text) {
    final matches = <RegExpMatch>[]
      ..addAll(hashtag.allMatches(text))
      ..addAll(mention.allMatches(text));

    if (matches.isEmpty) {
      return [
        {"text": text, "type": "text"}
      ];
    }

    // sort by start index
    matches.sort((a, b) => a.start.compareTo(b.start));

    final parts = <Map<String, dynamic>>[];
    int last = 0;

    for (final m in matches) {
      if (m.start > last) {
        parts.add({"text": text.substring(last, m.start), "type": "text"});
      }

      final raw = text.substring(m.start, m.end);
      final val = m.group(1);

      if (raw.startsWith("#")) {
        parts.add({"text": raw, "type": "hashtag", "value": val});
      } else if (raw.startsWith("@")) {
        parts.add({"text": raw, "type": "mention", "value": val});
      } else {
        parts.add({"text": raw, "type": "text"});
      }

      last = m.end;
    }

    if (last < text.length) {
      parts.add({"text": text.substring(last), "type": "text"});
    }

    return parts;
  }
}
