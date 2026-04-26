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
  static List<String> generateSearchTokens({
    required String name,
    required Map<String, String> localizedCategories, // {'ko': '운동', 'en': 'Sports', ...}
    required List<String> tags,
    String? locationName,
  }) {
    final tokens = <String>{};

    // 1. 이름 (단어 단위 + 공백제거)
    name.toLowerCase().split(RegExp(r'\s+')).forEach((p) { if (p.length >= 2) tokens.add(p); });
    tokens.add(name.toLowerCase().replaceAll(' ', ''));

    // 2. 모든 언어의 카테고리명 추가 (가장 핵심적인 다국어 지원)
    localizedCategories.forEach((lang, value) {
      final valLower = value.toLowerCase();
      tokens.add(valLower);
      // 해당 언어의 유의어도 일부 추가
      if (_multiLangRelatedMap[lang]?.containsKey(value) ?? false) {
        tokens.addAll(_multiLangRelatedMap[lang]![value]!.map((e) => e.toLowerCase()));
      }
    });

    // 3. 태그 및 지역
    for (var t in tags) { tokens.add(t.toLowerCase()); }
    if (locationName != null) {
      locationName.toLowerCase().split(RegExp(r'[,\s]+')).forEach((p) { if (p.length >= 2) tokens.add(p); });
    }

    return tokens.toList().take(50).toList();
  }
}
