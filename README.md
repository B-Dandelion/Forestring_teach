# 포레스트링 선생님

포레스트링 학원의 선생님 / 지점장 / 마스터용 Flutter 일정 관리 앱입니다.

## 브랜치

- `release/3.0.0-review`: 2026-08-23 심사 제출 시점 스냅샷
- `v3`: 현재 제출 버전 기준 브랜치
- `v3-complete`: v3 완성형 기능 개발 브랜치
- `ver2`: 과거 Firebase 기반 구현 참고용

## 현재 v3 기능

- 선생님 월간 수업 조회
- 선생님 주간 시간표 조회
- 역할별 수업 조회 범위
- 지점장 / 마스터의 수업 1회 변경 및 취소
- 마스터 / 지점장의 정규 수강생 등록
- 지점 조회 및 마스터의 지점 생성
- 심사용 읽기 전용 데모 모드

## v3-complete 목표

현재 v3의 Supabase 기반 구조와 권한 모델을 유지하면서 ver2의 운영 기능을 다시 구현합니다. ver2의 Firestore 직접 수정 코드는 이식하지 않고 기능 요구사항만 참고합니다.

우선순위:

1. 수강생 관리: 목록, 상세, 수정, 담당 선생님 변경, 정규 일정 변경, 퇴원
2. 선생님 관리: 목록, 생성, 근무시간, PIN 재설정, 비활성화
3. 지점장 관리: 생성, 지점 배정, PIN 재설정, 비활성화
4. 레슨 관리 확장: 학생/학기 필터, 수업 목록, 관리자용 수업 생성
5. 학기/휴원 및 예약 불가 시간 관리
6. 지점 상세 관리와 전체 관리 UX 정리

세부 작업 계획은 `docs/V3_COMPLETION_PLAN.md`를 참고합니다.

## 개발

```bash
flutter pub get
flutter analyze
flutter run --dart-define-from-file=env/dev.json
```

Android 릴리즈:

```bash
flutter build appbundle --release \
  --dart-define-from-file=env/dev.json
```

iOS 릴리즈 전에는 릴리즈 정리 스크립트를 실행합니다.

```bash
dart run tool/prepare_teacher_release.dart
flutter build ipa --release \
  --dart-define-from-file=env/dev.json
```

## 개발 원칙

- Flutter / Dart 고정
- Supabase를 단일 운영 백엔드로 사용
- 권한 검증과 중요한 일정 변경은 서버 RPC / Edge Function에서 처리
- `teacher`: 조회 전용
- `manager`: 자기 지점 관리
- `master`: 전체 지점 관리
- 마스터/지점장용 화면을 복제하지 않고 동일 화면에 scope만 적용
- 기존 `*_smoke_page.dart`는 정식 관리 화면으로 대체된 뒤 제거
