# Coupley — Phân tích chiều sâu & retention

> Đọc từ branch `feature/free-ads` (commit `1825885`), 207 file Swift + `functions/index.js`.
> Ngày phân tích: 2026-11-12

---

## 1. Vòng lặp hàng ngày hiện tại

App có **rất nhiều** feature (20 module), nhưng vòng lặp hàng ngày thực tế chỉ có một nhánh:

```
Push 20h "Check in together"
   → mở app → tab Mood → chọn 1 trong 4 mood + energy + note
   → về Home: Sync Score, Streak, MicroAction card
   → (hết)
```

Mọi thứ còn lại — Together (goals/challenges/dreams), TimeTree, Quiz Hub, AI Coach —
đều là **feature người dùng phải tự nhớ ra và chủ động đi tìm**. Không có cái nào
tự xuất hiện mỗi ngày.

### Những gì đang làm tốt

| Cơ chế | File | Nhận xét |
|---|---|---|
| Quiz 2 chiều (trả lời mù, lộ đáp án khi cả 2 xong) | `functions/index.js:1134` `onQuizAnswered` | **Đây là cơ chế mạnh nhất trong app** — nhưng đang bị chôn |
| MicroAction theo mood bucket × love language × stress response | `ActionGeneratorService.swift` | Copy rất tốt, tinh tế, không sến |
| Crown milestones (100 ngày, 1 năm, 1000 ngày…) | `CrownMilestone.swift` | Tạo "điểm hẹn" dài hạn |
| Push timezone-aware theo `reminderHour` của từng user | `functions/index.js:943` | Làm đúng chuẩn |
| Chống prompt-injection cho AI | `functions/index.js:55` | Hiếm app indie nào làm |

---

## 2. Ba vấn đề cấu trúc đang chặn thói quen hàng ngày

### 2.1. Không có analytics — không đo được gì cả

```bash
grep -rn "Analytics\|logEvent" --include="*.swift" .
# → 0 kết quả
```

Không có Firebase Analytics, không có event nào được log. Nghĩa là hiện tại **không
biết**:

- D1 / D7 / D30 retention là bao nhiêu
- Bao nhiêu % user pair thành công sau khi cài
- Feature nào kéo user quay lại, feature nào không ai dùng
- User bỏ ở bước nào trong onboarding
- Streak gãy ở ngày thứ mấy

Mọi đề xuất bên dưới (kể cả của tôi) đều là **giả thuyết** cho đến khi có số.
Đây là việc nên làm **trước tiên**, tốn ~1 ngày.

### 2.2. Streak phụ thuộc vào người kia — và gãy là mất sạch

`StreakService.swift:72`:

```swift
let bothCheckedIn = userIds.contains(session.userId) && userIds.contains(session.partnerId)
```

Streak chỉ tăng khi **cả hai** check-in cùng ngày. Nếu người kia quên một hôm:

```swift
} else {
    // Gap — restart
    streak.currentStreak = 1
}
```

→ Streak 47 ngày về 1, vì lỗi của người khác.

Đây là thiết kế punishing nhất có thể. User chăm chỉ bị phạt vì bạn đời bận. Và một
khi streak về 0, động lực quay lại gần như biến mất — không còn gì để mất nữa.

Cùng vấn đề với **Sync Score**: cần cả hai check-in mới có điểm, nếu không chỉ hiện
dòng chữ *"Both partners need to check in to see today's sync score"* — màn hình trống rỗng.

### 2.3. MicroAction là private — không tạo vòng lặp xã hội

`MicroAction.swift:30`:

```swift
/// A single private suggestion shown to the current user. Never synced to the
/// partner. Stored locally only.
```

Card đẹp nhất ở Home lại **không sinh ra tương tác nào**. User bấm "Done" → không ai
biết. Không có notification, không có phản hồi, không có dấu vết. Một hành động tốt
trong app mà người kia không bao giờ thấy thì không tạo được vòng lặp.

---

## 3. Đề xuất — xếp theo ROI

### Tier 1 — làm ngay

#### A. Gắn Firebase Analytics (~1 ngày)

Tối thiểu những event này:

```swift
// Core loop
Analytics.logEvent("mood_checkin", parameters: ["mood": mood.rawValue, "has_note": note != nil])
Analytics.logEvent("streak_continued", parameters: ["length": streak.currentStreak])
Analytics.logEvent("streak_broken", parameters: ["lost_length": previousStreak])

// Funnel
Analytics.logEvent("pairing_started", ...)      // mở sheet
Analytics.logEvent("pairing_completed", ...)    // thành công
Analytics.logEvent("onboarding_step", parameters: ["step": n])

// Feature discovery — câu hỏi lớn nhất: có ai dùng không?
Analytics.logEvent("feature_opened", parameters: ["name": "quiz_hub" / "together" / "timetree" / "ai_coach"])
Analytics.logEvent("microaction_done", ...)
```

Bật luôn **Firebase Crashlytics** cùng lúc. Và link AdMob ↔ Firebase (màn hình
AdMob đang báo *"Bạn cần liên kết với Firebase"* ở ô Doanh thu) để thấy được
revenue per user.

#### B. Question of the Day — câu hỏi mỗi ngày (ROI cao nhất)

Đây là cơ chế retention số một của mọi app couple (Paired, Gottman, Lasting đều xây
cả business lên nó). **Và hạ tầng của bạn đã có sẵn 90%** — chỉ là đang bị chôn 3
tầng trong `Chat → Quiz Hub → Daily Quiz`.

Cần làm:

1. Cloud Function scheduled: mỗi ngày tự tạo 1 quiz doc cho mọi couple, lấy từ
   `ChatQuizBank` (1415 dòng, thừa sức xoay vòng ~1 năm không lặp)
2. Đưa card "Câu hỏi hôm nay" lên **đầu tab Home**, trên cả MicroAction
3. Giữ nguyên cơ chế trả lời mù đã có — `onQuizAnswered` đã xử lý đúng 2 trường hợp
   (*"đến lượt bạn"* / *"có kết quả rồi"*)

Tại sao hiệu quả:

- Mỗi ngày có **nội dung mới** → lý do mở app thật, không phải nghĩa vụ
- Trả lời xong → người kia nhận push → họ mở app → **vòng lặp tự chạy**
- Tích lũy theo thời gian: sau 6 tháng là một kho 180 câu trả lời về nhau — đây
  chính là "chiều sâu" bạn đang tìm, và là cái khiến user không dám xoá app
- Không cần AI, không tốn tiền OpenAI

#### C. Sửa streak cho nhân đạo hơn (~nửa ngày)

Ba thay đổi trong `StreakService.swift`:

1. **Grace day**: bỏ lỡ 1 ngày thì streak đóng băng, không reset. Ngày thứ 2 mới mất.
2. **Tách streak cá nhân và streak cặp**: "Bạn: 12 ngày · Cả hai: 5 ngày". User
   chăm chỉ vẫn thấy công sức của mình được ghi nhận.
3. **Streak freeze**: cho 1 lần/tháng miễn phí. (Và xem mục 4 — đây là chỗ đặt
   rewarded ad hoàn hảo.)

Nếu không sửa, mọi nỗ lực tăng retention khác đều bị cơ chế này phá.

#### D. Lock screen + interactive widget (~1-2 ngày)

Hiện tại `CoupleyHomeWidget.swift:28` chỉ có:

```swift
.supportedFamilies([.systemSmall, .systemMedium])
```

Thiếu:

- **`.accessoryCircular` / `.accessoryRectangular` / `.accessoryInline`** —
  widget màn hình khoá. User nhìn màn hình khoá 80-150 lần/ngày. Một widget hiện
  mood của người kia hôm nay là lượng "chạm" lớn nhất mà không tốn gì.
- **Interactive widget (iOS 17+, `AppIntent`)** — check-in mood ngay trên home
  screen, không cần mở app. Nghe có vẻ phản tác dụng với ads, nhưng thực tế nó
  tăng tỉ lệ check-in rất mạnh, mà check-in mới là thứ kích hoạt push cho người
  kia → người kia mới là người mở app.

---

### Tier 2 — chiều sâu thật sự

#### E. Tag "vì sao" cho mood → mở khoá insight có giá trị

Mood hiện tại chỉ có 4 giá trị (`Mood.swift`), không có ngữ cảnh. Nên
`MonthlyMoodInsightView.swift` (572 dòng) không thể nói được điều gì thú vị — chỉ
đếm được số lần.

Thêm tag tuỳ chọn khi check-in: `công việc · sức khoẻ · gia đình · tiền bạc · chúng mình · bạn bè`

Mở ra được những insight thật sự có chiều sâu:

> *"Tháng này cả hai đều stress nhất vào thứ Hai — 7/8 lần."*
> *"Những ngày hai bạn nhắn tin trước 21h, mood hôm sau cao hơn 40%."*
> *"Từ khi bắt đầu challenge 'Biết ơn', số ngày mood 😢 giảm một nửa."*

Đây là loại nội dung user **chụp màn hình gửi cho nhau** — vừa là depth, vừa là
kênh lan truyền miễn phí.

#### F. Nghi thức buổi tối

Hiện mọi thứ đều dồn vào `reminderHour` (mặc định 20h), và chỉ có một hành động duy
nhất. Thêm một nhịp thứ hai, nhẹ:

> **Tối nay** — Một điều hôm nay bạn biết ơn ở người ấy.
> *(1 dòng, gửi đi, hiện trên Home của người kia sáng hôm sau)*

Cho app **hai điểm chạm/ngày** thay vì một, và tạo ra thứ người kia thức dậy để đọc.
Về mặt ads: gấp đôi session cũng là gấp đôi impression.

#### G. "Tháng này của chúng mình" — bản tổng kết tự động

Dữ liệu đã có sẵn hết (mood history, streak, memories trong TimeTree, goals đã xong).
Mỗi đầu tháng tự sinh một trang tổng kết đẹp:

- Biểu đồ mood 2 người chồng lên nhau
- Streak dài nhất, số ngày sync
- 3 memory nổi bật từ TimeTree
- Câu trả lời quiz "bất ngờ nhất"
- Nút **Chia sẻ** → ảnh dọc, có logo Coupley

Vừa là lý do quay lại mỗi tháng, vừa là growth loop duy nhất gần như miễn phí.

#### H. Cho MicroAction một mặt xã hội

Giữ nguyên gợi ý riêng tư, nhưng khi bấm "Done" thì cho **tuỳ chọn** gửi một tín hiệu
mờ cho người kia: *"Người ấy vừa làm một điều nhỏ cho bạn hôm nay 💛"* — không nói là
gì. Biến một hành động chết thành một vòng lặp.

---

## 4. Về quảng cáo

### Nói thẳng về con số hiện tại

Từ dashboard: **278 request / 198 impression trong 7 ngày** ≈ 28 impression/ngày.
Với banner ở 4 tab, con số này gợi ý DAU đang ở khoảng **10-20 người**.

Nghĩa là: **tối ưu quảng cáo lúc này gần như không đáng.** $0.29/ngày. Dù tăng eCPM
gấp đôi cũng chỉ thành $0.6. Đòn bẩy thật nằm ở retention và tăng user — đúng như
bạn đang nghĩ. Tuy nhiên có 3 việc đáng làm vì chúng **miễn phí hoặc có lợi cho user**:

### 4.1. Đổi sang adaptive banner (~15 phút, +20-40% eCPM)

`AdBannerView.swift:20` đang dùng banner cố định 320×50:

```swift
let size = AdSizeBanner.size                    // 320×50
BannerView(adSize: AdSizeBanner)
```

Trên iPhone hiện đại (rộng 390-430pt), banner 320pt để trống hai bên và được Google
trả giá thấp hơn. Adaptive anchored banner rộng hết màn hình, cao hơn, và Google
khuyến nghị dùng mặc định:

```swift
let width = UIScreen.main.bounds.width          // hoặc lấy từ GeometryReader
let adSize = currentOrientationAnchoredAdaptiveBanner(width: width)
BannerView(adSize: adSize)
```

`AdsManager.bannerDidLoad(height:)` đã đọc chiều cao động rồi nên phần layout
không cần sửa gì.

### 4.2. Bật auto-refresh banner trong AdMob console

Không nằm trong code — trong AdMob, ad unit "Coupley Banner" → Refresh rate → **60
giây**. Với session dài (đọc quiz, xem TimeTree) thì 1 session có thể thành 3-4
impression thay vì 1. Đây là nguồn tăng impression lớn nhất mà không đụng tới trải nghiệm.

### 4.3. Thêm rewarded ad — loại quảng cáo user **muốn** xem

Hiện chưa có rewarded ad nào (chỉ banner + interstitial). Đây là loại duy nhất
vừa tăng doanh thu vừa tăng retention, vì nó **cho** chứ không **lấy**:

| Xem 1 quảng cáo để... | Vì sao hợp lý |
|---|---|
| **Cứu streak** ("Streak Freeze") | Khoảnh khắc user có động lực cao nhất đời — họ sắp mất 40 ngày |
| Thêm 5 lượt AI Coach hôm nay | Cap hiện tại là 10/ngày (`PremiumModels.swift:80`), AI tốn tiền thật của bạn |
| Mở gói quiz đặc biệt | Có sẵn 1415 dòng quiz bank để đóng gói |

eCPM của rewarded thường **cao gấp 5-10 lần banner** ($10-20 so với $2.15). Và quan
trọng hơn: "cứu streak bằng 1 quảng cáo" giữ được user mà lẽ ra đã mất — giá trị
của nó lớn hơn nhiều so với tiền quảng cáo.

### 4.4. Giữ nguyên interstitial

Cấu hình hiện tại (`AdsConfig.swift`) — mỗi 3 hành động, cách nhau tối thiểu 180s,
không bao giờ ở lần mở app đầu tiên, delay 1s sau hành động để user kịp thấy phản
hồi — là **đúng chuẩn**. Đừng làm hung hãn hơn; với user base nhỏ, một review 1 sao
vì quảng cáo gây hại nhiều hơn vài cent.

---

## 5. Thứ tự đề xuất

| # | Việc | Công sức | Tác động |
|---|---|---|---|
| 1 | Firebase Analytics + Crashlytics + link AdMob | 1 ngày | Mở khoá mọi quyết định sau |
| 2 | Sửa streak (grace day, tách streak, freeze) | 0.5 ngày | Chặn rò rỉ user đang diễn ra |
| 3 | Question of the Day lên Home | 2-3 ngày | **Lớn nhất** — vòng lặp 2 chiều mỗi ngày |
| 4 | Adaptive banner + auto-refresh | 0.5 ngày | +30-50% doanh thu ads |
| 5 | Lock screen widget | 1-2 ngày | Tăng số lần chạm mạnh |
| 6 | Rewarded ad cho Streak Freeze | 1 ngày | Doanh thu + retention cùng lúc |
| 7 | Tag "vì sao" cho mood | 2 ngày | Chiều sâu insight |
| 8 | Nghi thức buổi tối | 2 ngày | Điểm chạm thứ hai/ngày |
| 9 | Tổng kết tháng + chia sẻ | 3 ngày | Growth loop |

**Nếu chỉ làm được một việc:** số 3 (Question of the Day). Nó là thứ duy nhất tạo
ra lý do mở app mỗi ngày mà *người kia* cũng phải mở app — và hạ tầng đã có sẵn.

---

## 6. Một ghi chú về định hướng

App đang có 20 module. Vấn đề không phải thiếu feature — mà là **không feature nào
tự tìm đến user mỗi ngày**. Together, TimeTree, Quiz Hub, AI Coach đều đang chờ user
nhớ ra chúng tồn tại.

Chiều sâu không đến từ thêm module thứ 21. Nó đến từ việc một hành động nhỏ, lặp lại
mỗi ngày, **tích lại thành thứ gì đó không thể thay thế** sau 6 tháng. Quiz bank +
TimeTree + mood history của bạn đã là nguyên liệu cho đúng thứ đó — chỉ cần nối
chúng vào một nhịp hàng ngày.
