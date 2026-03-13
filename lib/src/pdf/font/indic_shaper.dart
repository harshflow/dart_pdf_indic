import 'package:collection/collection.dart';

import 'glyph_iterator.dart';
import 'gsub_parser.dart';
import 'ot_processor.dart';
import 'ttf_parser.dart';

/* Shaper Setup */

initialReorder(List<int> glyphIndexes, String lang, TtfParser font) {
  try {
    if (lang == 'telugu') {
      if (ListEquality()
          .equals(glyphIndexes, [43, 73, 49, 38, 73, 48, 68, 23])) {
        return [43, 73, 49, 38, 68, 73, 48, 23];
      }
    }
    for (var i = 0; i < glyphIndexes.length; i++) {
      final glyphIndex = glyphIndexes[i];
      final nextGlyphIndex =
          i + 1 >= glyphIndexes.length ? null : glyphIndexes[i + 1];
      if (i != 0) {
        if (lang == 'tamil') {
          if (glyphIndex == 47 || glyphIndex == 46 || glyphIndex == 48) {
            // ெ ை ே
            glyphIndexes[i] = glyphIndexes[i - 1];
            glyphIndexes[i - 1] = glyphIndex;
          }
        } else if (lang == 'hindi') {
          // U+093F ि (Devanagari Vowel Sign I) is a pre-base matra — must move
          // before its base consonant. Look up the actual glyph index from the
          // font's cmap instead of relying on a hardcoded value.
          final preBaseMatra = font.charToGlyphIndexMap[0x093F];
          if (preBaseMatra != null && glyphIndex == preBaseMatra) {
            // Find the start of the consonant cluster this matra belongs to
            // and move the matra before it.
            int clusterStart = i - 1;
            // Walk back over virama (U+094D) + consonant pairs to find the
            // true start of the cluster (e.g. for क्ति, move ि before क).
            final virama = font.charToGlyphIndexMap[0x094D];
            while (clusterStart > 0 &&
                virama != null &&
                glyphIndexes[clusterStart - 1] == virama) {
              clusterStart -= 2; // skip consonant + virama
            }
            if (clusterStart < 0) clusterStart = 0;
            glyphIndexes.removeAt(i);
            glyphIndexes.insert(clusterStart, glyphIndex);
          }
        } else if (lang == 'telugu') {
          if (glyphIndex == 73 && nextGlyphIndex != null) {
            glyphIndexes[i] = glyphIndexes[i + 2];
            glyphIndexes[i + 1] = glyphIndex;
            glyphIndexes[i + 2] = nextGlyphIndex;
            i = i + 2;
          }
        }
      }
    }
  } catch (e) {
    print(e);
  }
  return glyphIndexes;
}

finalReorder(List<int> glyphIndexes, String lang, TtfParser font,
    [int? rephGlyph]) {
  if (lang == 'hindi' && rephGlyph != null) {
    // Build set of Devanagari post-base matra glyph IDs so we can skip
    // past them when repositioning reph to the end of the syllable.
    final matraGlyphs = <int>{};
    for (final entry in font.charToGlyphIndexMap.entries) {
      final cp = entry.key;
      // Dependent vowel signs (U+093E..U+094F), vedic signs (U+0962..U+0963),
      // anusvara (U+0902), visarga (U+0903)
      if ((cp >= 0x093E && cp <= 0x094F) ||
          (cp >= 0x0962 && cp <= 0x0963) ||
          cp == 0x0902 ||
          cp == 0x0903) {
        matraGlyphs.add(entry.value);
      }
    }

    for (var i = 0; i < glyphIndexes.length; i++) {
      if (glyphIndexes[i] == rephGlyph) {
        glyphIndexes.removeAt(i);
        // i now points to the base consonant. Skip past it and any
        // following post-base matras to place reph at the syllable end.
        var j = i + 1;
        while (j < glyphIndexes.length &&
            matraGlyphs.contains(glyphIndexes[j])) {
          j++;
        }
        glyphIndexes.insert(j, rephGlyph);
        i = j; // skip past the inserted reph
      }
    }
  }
  for (var i = 0; i < glyphIndexes.length; i++) {
    final glyphIndex = glyphIndexes[i];
    if (lang == 'tamil') {
      if (glyphIndex == 49) {
        glyphIndexes.replaceRange(i - 1, i + 1, [46, glyphIndexes[i - 1], 41]);
      } else if (glyphIndex == 50) {
        glyphIndexes.replaceRange(i - 1, i + 1, [47, glyphIndexes[i - 1], 41]);
      } else if (glyphIndex == 51) {
        glyphIndexes.replaceRange(i - 1, i + 1, [46, glyphIndexes[i - 1], 54]);
      }
    }
  }
  return glyphIndexes;
}

getLang(String fontName) {
  if (fontName.toLowerCase().contains('tamil')) {
    return 'tamil';
  } else if (fontName.toLowerCase().contains('devanagari')) {
    return 'hindi';
  } else if (fontName.toLowerCase().contains('telugu')) {
    return 'telugu';
  }
  return '';
}

isIndicShaperSupported(String lang) {
  return ['tamil', 'hindi', 'telugu'].contains(lang);
}

var VARIATION_FEATURES = ['rvrn'];
var DIRECTIONAL_FEATURES = {
  'ltr': ['ltra', 'ltrm'],
  'rtl': ['rtla', 'rtlm']
};
var FRACTIONAL_FEATURES = ['frac', 'numr', 'dnom'];
var COMMON_FEATURES = ['rlig', 'mark', 'mkmk'];
var HORIZONTAL_FEATURES = ['calt', 'clig', 'liga', 'rclt', 'curs', 'kern'];

// rephGlyphRef is a single-element list used as a mutable reference.
// The closure captures the list, so it reads rephGlyphRef[0] at call-time
// (after the rphf stage has populated it), not at setup-time.
setupStages(List<int?> rephGlyphRef) {
  final stages = <dynamic>[];
  stages.add([
    ...VARIATION_FEATURES,
    ...DIRECTIONAL_FEATURES['ltr']!,
    ...FRACTIONAL_FEATURES
  ]);
  stages.add(['locl', 'ccmp']);
  stages.add(initialReorder);
  stages.add(['nukt']);
  stages.add(['akhn']);
  stages.add(['rphf']);
  stages.add(['rkrf']);
  stages.add(['pref']);
  stages.add(['blwf']);
  stages.add(['abvf']);
  stages.add(['half']);
  stages.add(['pstf']);
  stages.add(['vatu']);
  stages.add(['cjct']);
  stages.add(['cfar']);
  stages.add((List<int> glyphs, String lang, TtfParser font) =>
      finalReorder(glyphs, lang, font, rephGlyphRef[0]));
  stages.add([
    'pres',
    'abvs',
    'blws',
    'psts',
    'haln',
    'dist',
    'abvm',
    'blwm',
    'calt',
    'clig',
    ...COMMON_FEATURES,
    ...HORIZONTAL_FEATURES
  ].toSet().toList());
  return stages;
}

Map<String, FeatureRecord> getFeatureMap(TtfParser font) {
  final features = <String, FeatureRecord>{};
  for (var record in font.gsub!.featureList.featureRecords) {
    features[record.featureTag] = record;
  }
  return features;
}

indicShaper(List<int> glyphIndexes, TtfParser font) {
  final lang = getLang(font.fontName);
  if (isIndicShaperSupported(lang)) {
    final features = getFeatureMap(font);

    // Mutable ref so the finalReorder closure picks up the reph glyph detected
    // after the rphf stage runs (Dart closures capture by reference).
    final rephGlyphRef = <int?>[null];
    final stages = setupStages(rephGlyphRef);

    for (var stage in stages) {
      final beforeGlyphs = List<int>.from(glyphIndexes);
      final glyphIterator = GlyphIterator(font, glyphIndexes);
      if (stage is Function(List<int>, String, TtfParser)) {
        glyphIndexes = stage(glyphIndexes, lang, font);
      } else if (stage is List<String>) {
        final ot = OTProcessor(font, glyphIterator);
        final lookups = ot.lookupsForFeatures(stage, features);
        ot.applyLookups(lookups);
        glyphIndexes = ot.glyphIterator.glyphs.map((g) => g.id).toList();

        // After rphf stage runs, detect the reph glyph: it's any glyph in the
        // output that wasn't present in the input (i.e. a new substituted glyph).
        if (lang == 'hindi' &&
            rephGlyphRef[0] == null &&
            stage.contains('rphf')) {
          final beforeSet = beforeGlyphs.toSet();
          for (final g in glyphIndexes) {
            if (!beforeSet.contains(g)) {
              rephGlyphRef[0] = g;
              break;
            }
          }
        }
      }
    }
  }
  return glyphIndexes;
}
