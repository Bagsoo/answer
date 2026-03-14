import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PollService {
  final _db = FirebaseFirestore.instance;
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── 투표 생성 ─────────────────────────────────────────────────────────────
  Future<String?> createPoll({
    required String roomId,
    required String title,
    required String type,          // 'regular' | 'date'
    required bool isAnonymous,
    required bool isMultiple,
    required List<String> options, // 날짜 투표는 ISO8601 문자열
    DateTime? endsAt,
    String creatorName = '',
  }) async {
    if (_myUid.isEmpty) return null;
    try {
      final optionList = options.asMap().entries.map((e) => {
        'id': e.key.toString(),
        'text': e.value,
        'voters': <Map<String, dynamic>>[],      // 실명: [{uid, name, photo_url}]
        'anonymous_voter_ids': <String>[],        // 익명/실명 모두 중복 체크용
        'vote_count': 0,
      }).toList();

      final ref = await _db
          .collection('chat_rooms')
          .doc(roomId)
          .collection('polls')
          .add({
        'title': title,
        'type': type,
        'is_anonymous': isAnonymous,
        'is_multiple': isMultiple,
        'options': optionList,
        'created_by': _myUid,
        'creator_name': creatorName,
        'created_at': FieldValue.serverTimestamp(),
        'ends_at': endsAt != null ? Timestamp.fromDate(endsAt) : null,
        'is_closed': false,
        'schedule_saved': false,
      });
      return ref.id;
    } catch (e) {
      debugPrint('createPoll error: $e');
      return null;
    }
  }

  // ── 투표하기 ──────────────────────────────────────────────────────────────
  Future<bool> vote({
    required String roomId,
    required String pollId,
    required List<String> optionIds,
    required bool isAnonymous,
    required bool isMultiple,
    required List<Map<String, dynamic>> currentOptions,
    required String myName,
    String? myPhotoUrl,           // 나중에 프로필 사진 추가 시 사용
  }) async {
    if (_myUid.isEmpty) return false;
    try {
      // 내가 이미 투표한 옵션 ID 목록 (anonymous_voter_ids로 중복 체크)
      final alreadyVoted = <String>[];
      for (final opt in currentOptions) {
        final anonVoters =
            List<String>.from(opt['anonymous_voter_ids'] as List? ?? []);
        if (anonVoters.contains(_myUid)) {
          alreadyVoted.add(opt['id'] as String);
        }
      }

      final updatedOptions = currentOptions.map((opt) {
        final id = opt['id'] as String;

        // 실명 투표자 목록 [{uid, name, photo_url}]
        final voters = List<Map<String, dynamic>>.from(
            (opt['voters'] as List? ?? []).map((v) => Map<String, dynamic>.from(v as Map)));
        // 중복 체크용 (익명/실명 모두)
        final anonVoters =
            List<String>.from(opt['anonymous_voter_ids'] as List? ?? []);
        int count = opt['vote_count'] as int? ?? 0;

        if (optionIds.contains(id)) {
          final alreadyThisOption = anonVoters.contains(_myUid);

          if (alreadyThisOption) {
            // 이미 선택 → 토글 취소
            anonVoters.remove(_myUid);
            voters.removeWhere((v) => v['uid'] == _myUid);
            count = (count - 1).clamp(0, 999999);
          } else {
            // 새로 선택
            anonVoters.add(_myUid);
            if (!isAnonymous) {
              voters.add({
                'uid': _myUid,
                'name': myName,
                'photo_url': myPhotoUrl,  // 현재는 null, 나중에 프로필 사진 연동
              });
            }
            count += 1;
          }
        } else if (!isMultiple && alreadyVoted.contains(id)) {
          // 단일 선택: 기존 선택 취소
          anonVoters.remove(_myUid);
          voters.removeWhere((v) => v['uid'] == _myUid);
          count = (count - 1).clamp(0, 999999);
        }

        return {
          ...opt,
          'voters': voters,
          'anonymous_voter_ids': anonVoters,
          'vote_count': count,
        };
      }).toList();

      await _db
          .collection('chat_rooms')
          .doc(roomId)
          .collection('polls')
          .doc(pollId)
          .update({'options': updatedOptions});
      return true;
    } catch (e) {
      debugPrint('vote error: $e');
      return false;
    }
  }

  // ── 투표 종료 ─────────────────────────────────────────────────────────────
  Future<bool> closePoll(String roomId, String pollId) async {
    if (_myUid.isEmpty) return false;
    try {
      await _db
          .collection('chat_rooms')
          .doc(roomId)
          .collection('polls')
          .doc(pollId)
          .update({'is_closed': true});
      return true;
    } catch (e) {
      debugPrint('closePoll error: $e');
      return false;
    }
  }

  // ── 날짜 투표 종료 → 그룹 스케줄 자동 저장 ──────────────────────────────
  Future<bool> saveDatePollAsSchedule({
    required String roomId,
    required String pollId,
    required String groupId,
    required String title,
    required List<Map<String, dynamic>> options,
  }) async {
    if (_myUid.isEmpty) return false;
    try {
      // 최다 득표 옵션 찾기
      Map<String, dynamic>? winner;
      int maxVotes = -1;
      for (final opt in options) {
        final count = opt['vote_count'] as int? ?? 0;
        if (count > maxVotes) {
          maxVotes = count;
          winner = opt;
        }
      }
      if (winner == null || maxVotes == 0) return false;

      final dateStr = winner['text'] as String;
      final startTime = DateTime.parse(dateStr);
      final endTime = startTime.add(const Duration(hours: 1));

      // 그룹 스케줄에 저장
      final scheduleRef = await _db
          .collection('groups')
          .doc(groupId)
          .collection('schedules')
          .add({
        'title': title,
        'description': '투표로 결정된 일정',
        'start_time': Timestamp.fromDate(startTime),
        'end_time': Timestamp.fromDate(endTime),
        'created_by': _myUid,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'rsvp': <String, String>{},
        'from_poll': true,
        'poll_room_id': roomId,
        'poll_id': pollId,
      });

      // poll에 schedule_saved 표시
      await _db
          .collection('chat_rooms')
          .doc(roomId)
          .collection('polls')
          .doc(pollId)
          .update({
        'is_closed': true,
        'schedule_saved': true,
        'saved_schedule_id': scheduleRef.id,
      });

      return true;
    } catch (e) {
      debugPrint('saveDatePollAsSchedule error: $e');
      return false;
    }
  }

  // ── 실시간 스트림 ─────────────────────────────────────────────────────────
  Stream<DocumentSnapshot> pollStream(String roomId, String pollId) {
    return _db
        .collection('chat_rooms')
        .doc(roomId)
        .collection('polls')
        .doc(pollId)
        .snapshots();
  }
}