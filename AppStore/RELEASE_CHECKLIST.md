# App Store 배포 체크리스트 — 세트 카운터

## 보안·개인정보 점검 결과 (2026-10-25)

| 항목 | 상태 | 비고 |
|---|---|---|
| 네트워크 통신 | ✅ 없음 | 외부 서버·SDK·분석 도구 없음. ATS 예외 없음 |
| 개인정보 저장 위치 | ✅ 기기 안 | SwiftData(앱 컨테이너), UserDefaults, 위젯용 App Group |
| 로그 출력 | ✅ 없음 | print/NSLog 없음 |
| Privacy Manifest | ✅ 추가 | 앱·위젯 각각 `PrivacyInfo.xcprivacy` (UserDefaults: CA92.1, 1C8F.1) |
| 수출 규정(암호화) | ✅ 추가 | `ITSAppUsesNonExemptEncryption = NO` |
| 권한 설명 문구 | ✅ 한/영 | 알람, 블루투스, 건강 읽기·쓰기 |
| 권한 요청 시점 | ✅ 수정 | 알람 권한을 앱 실행 시 → 운동 시작 시로 변경 |
| CSV 내보내기 | ✅ 수정 | 심박수 포함 파일을 잠금 시 암호화(completeFileProtection), 화면을 나가면 삭제 |
| 실행 시 강제 종료 | ✅ 수정 | DB 열기 실패 시 fatalError 대신 임시 저장소로 실행 |
| 기존 기록 유실 | ✅ 수정 | App Group 추가로 DB 위치가 바뀌던 문제 → 원래 위치로 고정 |
| 디버그 전용 코드 | ✅ 확인 | `-demoHeartRate`는 `#if DEBUG`라 Release에 포함 안 됨 |
| 앱 아이콘 | ✅ 추가 | 1024×1024, 알파 없음 + 다크·틴트 버전 |
| 백그라운드 모드 | ⚠️ 설명 필요 | `bluetooth-central` — 심사 메모에 사용 이유 적기 (아래) |

## 배포 전에 직접 해야 하는 것

1. **Apple Developer Program 가입** (연 129,000원 / US$99). 무료 계정으로는 App Store·TestFlight 업로드가 안 됩니다.
2. 가입한 계정을 Xcode → Settings → Accounts에 추가하고, 프로젝트 Signing의 Team을 그 팀으로 바꾸기.
3. [developer.apple.com](https://developer.apple.com/account/resources/identifiers)에서 확인:
   - App ID `com.andykim.SetCounter` — HealthKit, App Groups 켜기
   - App ID `com.andykim.SetCounter.Widget` — App Groups 켜기
   - App Group `group.com.andykim.SetCounter`
   (Xcode 자동 서명이면 대부분 자동으로 만들어집니다.)
4. **개인정보 처리방침 URL**: https://claude.ai/artifact/VDeB6HUQK9HHy9namQKzAQ
   - 처음엔 비공개라서, 페이지의 공유(Share) 메뉴에서 **링크가 있는 모든 사람이 볼 수 있게** 바꿔야 해요.
   - 로그아웃한 브라우저(시크릿 창)에서 열려야 심사를 통과해요. 안 열리면 노션 "웹에 게시" 등으로 옮기고 `AppSettings.swift`의 `privacyPolicyURL`도 바꿔주세요.
   - 앱의 설정 → 정보 화면에도 이 링크가 들어 있어요.
5. App Store Connect에서 앱 생성 → 나오는 숫자 App ID를 `SetCounter/AppSettings.swift`의 `appStoreID`에 넣기 (리뷰 버튼이 App Store 리뷰 페이지로 연결됨).
6. Xcode → Product → Archive → Distribute App → App Store Connect.

## App Store Connect 입력값

**App Privacy (앱 개인정보 보호)**: "데이터를 수집하지 않음(Data Not Collected)"
- 모든 데이터가 기기 안에만 있고 개발자에게 전송되지 않으므로 해당.

**연령 등급**: 4+ (모든 항목 "없음")

**카테고리**: 건강 및 피트니스

**심사 메모 (App Review Notes)** — 그대로 붙여넣기:
> This app counts workout sets and runs a rest timer. No account or login is needed.
> - HealthKit: reads heart rate (Apple Watch / AirPods Pro 3) to estimate calories during a workout, and saves finished workouts to Health. Data never leaves the device.
> - Background mode "bluetooth-central": keeps receiving heart rate from a paired Bluetooth heart rate strap while the screen is locked during a workout.
> - AlarmKit: rings a system alarm when the rest timer ends while the phone is locked.
> To test: Workout tab → 운동 준비 → 시작 → 세트 완료 starts the rest timer.

## 스토어 문구 (한국어)

- **이름**: 세트 카운터
- **부제**: 세트·휴식 타이머와 운동 기록
- **키워드**: 헬스,운동기록,세트,휴식타이머,분할,루틴,운동일지,심박수,칼로리,웨이트
- **설명**:
> 세트를 마칠 때마다 한 번만 누르세요. 카운트가 올라가고 휴식 타이머가 바로 시작돼요.
>
> • 휴식이 끝나면 알람이 울리는 동안만 음악을 잠깐 멈추고 다시 재생해요
> • 화면이 잠겨 있어도 시스템 알람으로 알려줘요
> • 분할 루틴: 오늘 할 부위를 자동으로 알려주고 아침 알림을 보내요
> • 운동 기록과 캘린더, 주간·월간 통계, 운동별 무게 변화
> • Apple Watch·AirPods·블루투스 심박 센서로 심박수와 칼로리 계산
> • 홈 화면·잠금 화면 위젯, 다크 모드, kg/lb, 한국어·English
>
> 모든 기록은 내 iPhone에만 저장돼요. 계정도, 광고도 없어요.

## 스크린샷

`AppStore/screenshots/` — 6.9" (1320×2868) JPEG 7장. App Store Connect의 6.9" 칸에 올리면 작은 기기용은 자동으로 줄여서 쓰입니다.

1. 오늘의 루틴과 운동 설정
2. 운동 중 (심박수·칼로리)
3. 휴식 타이머
4. 월간 통계
5. 부위별 세트·무게 변화
6. 캘린더 기록
7. 설정
