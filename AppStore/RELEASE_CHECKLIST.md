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
> - In-app purchases: Set Counter Pro (yearly with a 7-day free trial, monthly, lifetime) unlocks detailed stats, past reports, the Apple Watch app, routine editing, some widgets, and themes. Locked items show a "PRO" tag or a lock. Settings → 세트 카운터 Pro has the paywall, Restore Purchases, the terms, and the privacy policy.

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
>
> [세트 카운터 Pro — 유료]
> 운동 기록, 휴식 타이머, 백업, 배지는 무료예요. 아래 기능은 세트 카운터 Pro가 필요해요.
> • 자세한 통계(운동별 1RM·볼륨 추이, 부위 밸런스, 운동 잔디, 개인 기록), 지난 리포트와 지난주 대비 증감
> • Apple Watch 앱, 루틴 편집과 다음 무게·횟수 추천
> • 지난 날짜 식단, 내 음식 저장, 체중 1년 추세, CSV, 운동 이름 관리
> • 칼로리 위젯, 잠금 화면 위젯, 화면 모드·강조 색
> 연간 ₩22,000(처음 7일 무료), 월간 ₩2,900, 평생 ₩49,000. 구독은 끝나기 24시간 전까지 해지하지 않으면 자동 갱신되고, iPhone 설정 → Apple 계정 → 구독에서 해지할 수 있어요.
> 이용약관(EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

## 스크린샷

Pro 기능이 나오는 스크린샷(통계, 운동별 무게 변화 등)에는 "Pro" 표시를 넣거나 설명 문구에 Pro라고 적어 주세요. 유료 기능을 무료처럼 보이게 하면 심사에서 거절돼요(가이드라인 2.3.2).

`AppStore/screenshots/` — 6.9" (1320×2868) JPEG 7장. App Store Connect의 6.9" 칸에 올리면 작은 기기용은 자동으로 줄여서 쓰입니다.

1. 오늘의 루틴과 운동 설정
2. 운동 중 (심박수·칼로리)
3. 휴식 타이머
4. 월간 통계
5. 부위별 세트·무게 변화
6. 캘린더 기록
7. 설정

## 법·정책 점검 (2026-10-30)

| 항목 | 상태 | 비고 |
|---|---|---|
| 개인정보 처리방침 | ✅ 앱 안 + 웹 | 설정 → 정보 → 약관 및 정책, 결제 화면 |
| 이용약관 | ✅ 앱 안 | Apple 표준 EULA를 함께 적용, 건강 정보 면책, 자동 갱신 안내 |
| 환불 정책 | ✅ 앱 안 | 환불은 Apple이 처리, 앱 안 "환불 요청" 버튼(StoreKit) |
| 쿠키 정책·쿠키 동의 배너 | 해당 없음 | 웹뷰·쿠키·추적 없음 (방침에 명시) |
| 입력 양식 동의 | ✅ | 건강 데이터는 시스템 권한 창으로 동의, 신체 정보는 기기 안에만 저장한다고 화면에 안내 |
| 불필요한 개인정보 | ✅ | 개발자에게 전송되는 정보 없음. 읽는 건강 데이터는 모두 화면에서 사용 |
| 외부 SDK | ✅ 없음 | 앱·위젯 Privacy Manifest 있음 |
| 다크 패턴·숨은 요금 | ✅ | 닫기 버튼 항상 보임, 체험 후 금액을 버튼 아래 표시, "할인" 대신 "월간보다 37% 저렴" |
| 가짜 후기·근거 없는 주장 | ✅ 없음 | 앱·스토어 문구에 후기·순위·효과 보장 없음, 칼로리는 추정치라고 명시 |
| 대체 텍스트·색 대비 | ✅ | 아이콘 버튼 VoiceOver 이름, 작은 색 글자를 라이트 모드에서 4.5:1 이상으로 |
| 사업자 정보 | ⚠️ 입력 필요 | `AppSettings.swift`의 `sellerName` 등. 사업자등록·통신판매업 신고 여부는 직접 확인 |
| 아동 | ✅ | 나이 입력 14세부터, 방침에 만 14세 이상 명시 |
| 이메일 수신거부 | 해당 없음 | 홍보 메일을 보내지 않음 |
| 이미지·글꼴 이용권 | ✅ | 앱 아이콘은 코드로 직접 그림, 앱 안 아이콘은 SF Symbols(Apple 플랫폼 앱에서 사용 허용, 앱 아이콘·로고에는 쓰지 않음), 글꼴은 시스템 글꼴, 웹 방침 페이지 글꼴은 IBM Plex Sans KR(OFL) |
| 개인정보 삭제 | ✅ | 데이터 관리 → 모든 데이터 삭제 (건강 앱에 저장한 기록 포함 선택) |

EU에도 배포하면 App Store Connect에서 "거래자(Trader)" 여부를 신고해야 하고, 유료 판매자는 주소·전화번호·이메일이 스토어에 공개돼요.
