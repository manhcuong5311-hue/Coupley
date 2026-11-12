# Coupley 1.2 (build 2)

## What's New — English (App Store, ≤4000 chars)

```
Something new to answer together, every day.

QUESTION OF THE DAY
A new question appears on Home each day. You both answer without seeing the
other's choice — then it opens, and you find out what they said and what that
choice says about them.

GUESS THEIR ANSWER
Answer for yourself, then predict what they'll pick. Over time you get a
simple score for how well you actually know each other.

PHOTO OF THE DAY
A small prompt — "what's directly in front of you right now?" Send yours and
theirs unlocks. Neither photo appears until you've both sent one.

TOUCH TOGETHER
Press and hold the circle. When they're holding it too, you'll both feel it.

WHEN YOU'RE BOTH HERE
If you both have Coupley open at the same time, Home says so — and whatever
you send lands on their screen right away.

ALSO
• See when they're typing in chat
• React to a quiz result instead of just reading it
• The quiz list now marks what you've answered and hides it
• Better suggestions for what to ask next
• The AI Coach now runs on a real model, with a fair-use limit of 5 a day

FIXED
• Couple challenge check-ins now count for each partner separately. Before,
  whoever tapped first used up the day for both.
• Your partner no longer shows as "online" for a couple of minutes after
  they've closed the app.
```

## Bản tiếng Việt (nếu listing có vi-VN)

```
Mỗi ngày có một điều mới để cùng trả lời.

CÂU HỎI HÔM NAY
Mỗi ngày một câu hỏi mới ở trang chủ. Hai người trả lời mà không thấy lựa
chọn của nhau — rồi nó mở ra, bạn biết người kia chọn gì và điều đó nói lên
điều gì về họ.

ĐOÁN ĐÁP ÁN CỦA NGƯỜI KIA
Trả lời cho mình, rồi đoán xem người kia sẽ chọn gì. Theo thời gian bạn có
một điểm số đơn giản: thực sự hiểu nhau tới đâu.

ẢNH CỦA NGÀY
Một đề bài nhỏ — "thứ đang ở ngay trước mặt bạn?". Gửi ảnh của bạn thì ảnh
của người kia mới mở. Chưa đủ hai thì không ai thấy gì.

CHẠM CÙNG LÚC
Giữ ngón tay lên vòng tròn. Khi người kia cũng đang giữ, cả hai máy cùng rung.

KHI CẢ HAI CÙNG Ở ĐÂY
Nếu hai người cùng mở Coupley một lúc, trang chủ sẽ báo — và thứ bạn gửi hiện
lên màn hình họ ngay lập tức.

NGOÀI RA
• Thấy khi người kia đang gõ tin nhắn
• Thả cảm xúc lên kết quả quiz
• Danh sách quiz đánh dấu và ẩn câu đã trả lời
• Gợi ý câu hỏi tiếp theo thông minh hơn
• AI Coach chạy trên mô hình thật, giới hạn 5 lượt mỗi ngày

ĐÃ SỬA
• Check-in thử thách đôi giờ tính riêng cho từng người. Trước đây ai bấm
  trước là tiêu luôn ngày đó của cả hai.
• Người kia không còn hiện "đang online" thêm vài phút sau khi đã đóng app.
```

---

## Pre-submission checklist

### Done
- [x] Version 1.2, build 2 (verified in the built Info.plist)
- [x] Release configuration compiles clean
- [x] Firestore rules deployed (`liveState`, `photoOfDay`)
- [x] Cloud Functions deployed (`onQotDCreated`, `onQuizAnswered`, `coach`)
- [x] Legal page updated: discloses OpenAI as a processor, AI limits corrected 10 → 5

### Needs you — I could not do these
- [ ] **Publish the updated legal page.** `index.html` is served from GitHub Pages
      at `manhcuong5311-hue.github.io/Coupley/`, which the app links to as its
      Privacy Policy. The OpenAI disclosure must be live *before* the build is
      reviewed, not after.
- [ ] **Archive and upload.** No iOS signing certificate for team `553U32259K`
      exists in this machine's keychain, so `xcodebuild` cannot produce a signed
      device build. Do it in Xcode: Product → Archive → Distribute App.
- [ ] **App Privacy answers in App Store Connect.** The "Data Used to Track You"
      / third-party sharing answers were written when AI ran on-device. AI
      requests now leave the device.
- [ ] **Submit for review.**

### Worth deciding before you submit
- `generateSuggestion` still enforces the old server-side limit of 10 (its deploy
  is blocked until the stale `asia-southeast1` copy is deleted). The client caps
  at 5, so users see 5 either way.
- Seven stale Cloud Functions are still running in `asia-southeast1`, including a
  daily scheduled job whose source no longer exists in any repo.
- This release is the first time the app spends real OpenAI money.
