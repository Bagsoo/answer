import '../../l10n/app_localizations.dart';

/// 그룹 유형별 카테고리 데이터
/// - categories 맵은 l10n 키만 저장
/// - 실제 표시 문자열은 AppLocalizations에서 변환
/// - 카테고리 추가 시: 1) 여기 키 추가  2) app_localizations.dart에 문자열 추가
class GroupTypeCategoryData {
  static const List<String> typeKeys = [
    'company',
    'club',
    'small_group',
    'academy',
    'school_class',
    'hobby_club',
  ];

  /// 유형별 카테고리 키 목록
  static const Map<String, List<String>> categoryKeys = {
    'company': [
      'cat_it_dev',
      'cat_marketing',
      'cat_finance',
      'cat_manufacturing',
      'cat_medical',
      'cat_education_research',
      'cat_legal',
      'cat_design_creative',
      'cat_sales',
      'cat_construction',
      'cat_media_entertainment',
      'cat_startup',
      'cat_public_nonprofit',
      'cat_other',
    ],
    'club': [
      'cat_health_fitness',
      'cat_running',
      'cat_bowling',
      'cat_tennis',
      'cat_table_tennis',
      'cat_billiards',
      'cat_golf',
      'cat_cycling',
      'cat_hiking',
      'cat_swimming',
      'cat_soccer',
      'cat_basketball',
      'cat_badminton',
      'cat_baseball',
      'cat_yoga_pilates',
      'cat_self_dev',
      'cat_business_startup',
      'cat_social_networking',
      'cat_travel',
      'cat_reading',
      'cat_cooking',
      'cat_gaming',
      'cat_music',
      'cat_photo_video',
      'cat_other',
    ],
    'small_group': [
      'cat_health_fitness',
      'cat_running',
      'cat_bowling',
      'cat_tennis',
      'cat_table_tennis',
      'cat_billiards',
      'cat_golf',
      'cat_cycling',
      'cat_hiking',
      'cat_swimming',
      'cat_soccer',
      'cat_basketball',
      'cat_badminton',
      'cat_baseball',
      'cat_yoga_pilates',
      'cat_self_dev',
      'cat_business_startup',
      'cat_social_networking',
      'cat_travel',
      'cat_food_gourmet',
      'cat_reading_study',
      'cat_cooking',
      'cat_gaming',
      'cat_music',
      'cat_other',
    ],
    'hobby_club': [
      'cat_health_fitness',
      'cat_running',
      'cat_bowling',
      'cat_tennis',
      'cat_table_tennis',
      'cat_billiards',
      'cat_golf',
      'cat_cycling',
      'cat_hiking',
      'cat_swimming',
      'cat_soccer',
      'cat_basketball',
      'cat_badminton',
      'cat_baseball',
      'cat_yoga_pilates',
      'cat_social_networking',
      'cat_travel',
      'cat_reading',
      'cat_food_gourmet',
      'cat_cooking',
      'cat_gaming',
      'cat_music',
      'cat_photo_video',
      'cat_dance',
      'cat_other',
    ],
    'academy': [
      'cat_english_academy',
      'cat_language_academy',
      'cat_entrance_exam',
      'cat_piano',
      'cat_guitar_drum',
      'cat_vocal',
      'cat_art_painting',
      'cat_sports_physical',
      'cat_coding',
      'cat_cooking_baking',
      'cat_beauty_hair',
      'cat_certificate_job',
      'cat_other',
    ],
    'school_class': [
      'cat_elementary',
      'cat_middle_school',
      'cat_high_school',
      'cat_university',
      'cat_graduate',
      'cat_same_year',
      'cat_alumni',
      'cat_other',
    ],
  };

  /// 키 → 표시 문자열 변환
  static String localizeKey(String key, AppLocalizations l) {
    switch (key) {
      // ── 회사 ──────────────────────────────────────────────────
      case 'cat_it_dev':              return l.catItDev;
      case 'cat_marketing':           return l.catMarketing;
      case 'cat_finance':             return l.catFinance;
      case 'cat_manufacturing':       return l.catManufacturing;
      case 'cat_medical':             return l.catMedical;
      case 'cat_education_research':  return l.catEducationResearch;
      case 'cat_legal':               return l.catLegal;
      case 'cat_design_creative':     return l.catDesignCreative;
      case 'cat_sales':               return l.catSales;
      case 'cat_construction':        return l.catConstruction;
      case 'cat_media_entertainment': return l.catMediaEntertainment;
      case 'cat_startup':             return l.catStartup;
      case 'cat_public_nonprofit':    return l.catPublicNonprofit;
      // ── 스포츠/취미 ───────────────────────────────────────────
      case 'cat_health_fitness':      return l.catHealthFitness;
      case 'cat_running':             return l.catRunning;
      case 'cat_bowling':             return l.catBowling;
      case 'cat_tennis':              return l.catTennis;
      case 'cat_table_tennis':        return l.catTableTennis;
      case 'cat_billiards':           return l.catBilliards;
      case 'cat_golf':                return l.catGolf;
      case 'cat_cycling':             return l.catCycling;
      case 'cat_hiking':              return l.catHiking;
      case 'cat_swimming':            return l.catSwimming;
      case 'cat_soccer':              return l.catSoccer;
      case 'cat_basketball':          return l.catBasketball;
      case 'cat_badminton':           return l.catBadminton;
      case 'cat_baseball':            return l.catBaseball;
      case 'cat_yoga_pilates':        return l.catYogaPilates;
      case 'cat_self_dev':            return l.catSelfDev;
      case 'cat_business_startup':    return l.catBusinessStartup;
      case 'cat_social_networking':   return l.catSocialNetworking;
      case 'cat_travel':              return l.catTravel2;
      case 'cat_reading':             return l.catReading;
      case 'cat_reading_study':       return l.catReadingStudy;
      case 'cat_cooking':             return l.catCooking;
      case 'cat_gaming':              return l.catGaming;
      case 'cat_music':               return l.catMusic2;
      case 'cat_photo_video':         return l.catPhotoVideo;
      case 'cat_dance':               return l.catDance;
      case 'cat_food_gourmet':        return l.catFoodGourmet;
      // ── 학원 ──────────────────────────────────────────────────
      case 'cat_english_academy':     return l.catEnglishAcademy;
      case 'cat_language_academy':    return l.catLanguageAcademy;
      case 'cat_entrance_exam':       return l.catEntranceExam;
      case 'cat_piano':               return l.catPiano;
      case 'cat_guitar_drum':         return l.catGuitarDrum;
      case 'cat_vocal':               return l.catVocal;
      case 'cat_art_painting':        return l.catArtPainting;
      case 'cat_sports_physical':     return l.catSportsPhysical;
      case 'cat_coding':              return l.catCoding;
      case 'cat_cooking_baking':      return l.catCookingBaking;
      case 'cat_beauty_hair':         return l.catBeautyHair;
      case 'cat_certificate_job':     return l.catCertificateJob;
      // ── 학교/반 ───────────────────────────────────────────────
      case 'cat_elementary':          return l.catElementary;
      case 'cat_middle_school':       return l.catMiddleSchool;
      case 'cat_high_school':         return l.catHighSchool;
      case 'cat_university':          return l.catUniversity;
      case 'cat_graduate':            return l.catGraduate;
      case 'cat_same_year':           return l.catSameYear;
      case 'cat_alumni':              return l.catAlumni;
      // ── 공통 ──────────────────────────────────────────────────
      case 'cat_other':               return l.catOther2;
      default:                        return key;
    }
  }

  /// 유형별 카테고리 표시 문자열 목록 반환
  static List<String> getCategoriesForType(
      String typeKey, AppLocalizations l) {
    final keys = categoryKeys[typeKey] ?? categoryKeys['club']!;
    return keys.map((k) => localizeKey(k, l)).toList();
  }

  /// 표시 문자열 → 키 역변환 (저장 시 사용)
  static String? labelToKey(String label, String typeKey, AppLocalizations l) {
    final keys = categoryKeys[typeKey] ?? categoryKeys['club']!;
    for (final k in keys) {
      if (localizeKey(k, l) == label) return k;
    }
    return null;
  }
}