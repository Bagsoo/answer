class SearchDictionary {
  /// 언어별 연관어 사전 (ko, en, ja)
  static const Map<String, Map<String, List<String>>> _multiLangRelatedMap = {
    'ko': {
      '운동': ['스포츠', '다이어트', '체력', '헬스', '피트니스'],
      '유도': ['무술', '격투기', '호신술'],
      '친목': ['모임', '동호회', '사교', '친구'],
      '맛집': ['음식', '요리', '카페', '투어'],
      'IT': ['개발', '코딩', '프로그래밍', '테크'],
    },
    'en': {
      'sports': ['exercise', 'fitness', 'workout', 'gym', 'health'],
      'judo': ['martial arts', 'combat', 'self-defense'],
      'social': ['gathering', 'club', 'community', 'friends'],
      'food': ['gourmet', 'cooking', 'restaurant', 'cafe'],
      'it': ['development', 'coding', 'programming', 'tech'],
    },
    'ja': {
      '運動': ['スポーツ', 'ダイエット', 'フィットネス', 'ジム'],
      '柔道': ['武道', '格闘技', '護身術'],
      '親睦': ['オフ会', 'サークル', 'コミュニティ', '友達'],
      'グルメ': ['料理', '食べ歩き', 'カフェ', 'レストラン'],
      'IT': ['開発', 'コーディング', 'プログラミング', 'テック'],
    },
  };

  /// 입력된 쿼리에 대해 모든 언어의 유의어를 뒤져서 확장 (최대 10개)
  static List<String> expandQuery(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return [];

    final results = <String>{trimmed};

    for (final langMap in _multiLangRelatedMap.values) {
      for (final entry in langMap.entries) {
        if (trimmed.contains(entry.key.toLowerCase()) || entry.key.toLowerCase().contains(trimmed)) {
          results.addAll(entry.value.map((e) => e.toLowerCase()));
        }
      }
    }

    return results.toList().take(10).toList();
  }

  /// 그룹 생성 시 모든 언어의 카테고리명을 토큰으로 저장
  /// 이 로직을 통해 일본어 유저가 'Sports'라고 검색해도 한국어 운동 그룹을 찾을 수 있음
  /// 그리고 이름/지역/태그는 prefix 토큰도 저장해서 부분 검색이 가능하게 한다.
  static List<String> generateSearchTokens({
    required String name,
    required Map<String, String> localizedCategories, // {'ko': '운동', 'en': 'Sports', ...}
    required List<String> tags,
    String? locationName,
  }) {
    final tokens = <String>{};

    // 1. 이름 (단어 단위 + 공백제거 + prefix)
    _addSearchTokens(tokens, name);

    // 2. 모든 언어의 카테고리명 추가 (가장 핵심적인 다국어 지원)
    localizedCategories.forEach((lang, value) {
      _addSearchTokens(tokens, value);
      // 해당 언어의 유의어도 일부 추가
      if (_multiLangRelatedMap[lang]?.containsKey(value) ?? false) {
        for (final related in _multiLangRelatedMap[lang]![value]!) {
          _addSearchTokens(tokens, related);
        }
      }
    });

    // 3. 태그 및 지역
    for (var t in tags) { _addSearchTokens(tokens, t); }
    if (locationName != null) {
      _addSearchTokens(tokens, locationName);
    }

    return tokens.toList().take(50).toList();
  }

  static void _addSearchTokens(Set<String> tokens, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (compact.length >= 2) {
      tokens.add(compact);
      _addPrefixes(tokens, compact);
    }

    for (final part in normalized.split(RegExp(r'[,\s]+'))) {
      if (part.length < 2) continue;
      tokens.add(part);
      _addPrefixes(tokens, part);
    }
  }

  static void _addPrefixes(Set<String> tokens, String value) {
    final maxLen = value.length < 12 ? value.length : 12;
    for (var i = 2; i <= maxLen; i++) {
      tokens.add(value.substring(0, i));
    }
  }
}
