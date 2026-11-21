//
//  DemoContent.swift
//  Coupley
//
//  DEBUG only. Launched with `-coupleyDemoData`, the app draws a believable,
//  localized couple in place of the signed-in test couple's own data: their
//  two first names, the typed chat messages, and goal and challenge titles.
//  For screenshots and mockups. Display only: nothing here is ever written to
//  Firestore or to the local caches.
//

#if DEBUG
import Foundation

struct DemoContent {

    struct Message {
        let fromMe: Bool
        let text: String
    }

    /// The signed-in user (the man in the default avatars).
    let me: String
    /// The partner (the woman in the default avatars).
    let partner: String
    /// Me, partner, me.
    let chat: [Message]
    let goals: [String]
    let challenges: [String]

    static let launchArgument = "-coupleyDemoData"

    /// The demo couple for the language the app resolved for this launch, or
    /// nil when the launch argument is absent.
    static let current: DemoContent? = {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return nil }
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return byLanguage[code] ?? byLanguage["en"]
    }()

    func profile(_ profile: CouplePersonProfile, isMe: Bool) -> CouplePersonProfile {
        var shown = profile
        shown.displayName = isMe ? me : partner
        return shown
    }

    func goals(_ items: [TogetherGoal]) -> [TogetherGoal] {
        items.enumerated().map { index, goal in
            var shown = goal
            shown.title = goals[index % goals.count]
            return shown
        }
    }

    func challenges(_ items: [CoupleChallenge]) -> [CoupleChallenge] {
        items.enumerated().map { index, challenge in
            var shown = challenge
            shown.title = challenges[index % challenges.count]
            return shown
        }
    }

    /// Memories titled with their kind in the app's language ("First kiss"
    /// becomes "Nụ hôn đầu"), so a test couple's English titles never show.
    func memories(_ items: [TimeMemory]) -> [TimeMemory] {
        items.map { memory in
            var shown = memory
            shown.title = memory.kind.displayName
            return shown
        }
    }

    /// The thread with the couple's typed messages and photos replaced by the
    /// demo conversation, placed after the last quiz or system card.
    func chat(replacingTextIn messages: [ChatMessage], me: String, partner: String) -> [ChatMessage] {
        let kept = messages.filter { $0.kind != .text && $0.kind != .photo }
        let afterCards = (kept.last?.createdAt ?? .distantPast).addingTimeInterval(60)
        let start = max(afterCards, Date().addingTimeInterval(-12 * 60))
        let demo = chat.enumerated().map { index, message in
            ChatMessage(id: "demo-\(index)", kind: .text,
                        senderId: message.fromMe ? me : partner,
                        createdAt: start.addingTimeInterval(Double(index) * 90),
                        readBy: [me, partner],
                        text: message.text, quizId: nil,
                        resultSummary: nil, resultEmoji: nil, resultMatch: nil,
                        imageURL: nil)
        }
        return kept + demo
    }

    static let byLanguage: [String: DemoContent] = [
        "ar": DemoContent(
            me: "عمر", partner: "ليلى",
            chat: [
                .init(fromMe: true, text: "ما رأيك نتعشى مشاوي الليلة؟ 🍢"),
                .init(fromMe: false, text: "أكيد! الساعة ٨، سأحجز أنا ❤️"),
                .init(fromMe: true, text: "رائع 😊")
            ],
            goals: ["رحلة إلى باريس", "صندوق بيت العمر"],
            challenges: ["30 يومًا بلا خلاف", "موعد غرامي كل أسبوع"]
        ),
        "cs": DemoContent(
            me: "Jakub", partner: "Tereza",
            chat: [
                .init(fromMe: true, text: "Dáme si dneska večer sushi? 🍣"),
                .init(fromMe: false, text: "Jo! V 7, zarezervuju ❤️"),
                .init(fromMe: true, text: "Super, už se těším 😍")
            ],
            goals: ["Dovolená v Chorvatsku", "Na naši svatbu"],
            challenges: ["30 dní bez hádek", "Rande každý týden"]
        ),
        "da": DemoContent(
            me: "Mads", partner: "Freja",
            chat: [
                .init(fromMe: true, text: "Sushi i aften? 🍣"),
                .init(fromMe: false, text: "Ja! Kl. 19? Jeg booker ❤️"),
                .init(fromMe: true, text: "Glæder mig 😍")
            ],
            goals: ["Rejse til Thailand", "Vores bryllup"],
            challenges: ["30 dage uden skænderier", "Date night hver uge"]
        ),
        "de": DemoContent(
            me: "Jonas", partner: "Lena",
            chat: [
                .init(fromMe: true, text: "Heute Abend Sushi? 🍣"),
                .init(fromMe: false, text: "Ja! Um 8? Ich reserviere ❤️"),
                .init(fromMe: true, text: "Freu mich 😍")
            ],
            goals: ["Reise nach Bali", "Unsere Hochzeit"],
            challenges: ["30 Tage ohne Streit", "Wöchentliches Date"]
        ),
        "el": DemoContent(
            me: "Γιώργος", partner: "Ελένη",
            chat: [
                .init(fromMe: true, text: "Πάμε για σουβλάκια απόψε; 🥙"),
                .init(fromMe: false, text: "Ναι! Στις 9, κλείνω εγώ τραπέζι ❤️"),
                .init(fromMe: true, text: "Τέλεια, ανυπομονώ 😍")
            ],
            goals: ["Ταξίδι στο Παρίσι", "Για τον γάμο μας"],
            challenges: ["30 μέρες χωρίς καβγά", "Ραντεβού κάθε εβδομάδα"]
        ),
        "en": DemoContent(
            me: "Jake", partner: "Emma",
            chat: [
                .init(fromMe: true, text: "Sushi tonight? 🍣"),
                .init(fromMe: false, text: "Yes! 7pm? I'll book it ❤️"),
                .init(fromMe: true, text: "Perfect 😍")
            ],
            goals: ["Italy Trip", "Our First Home"],
            challenges: ["30 Days Without Fighting", "Weekly Date Night"]
        ),
        "es": DemoContent(
            me: "Mateo", partner: "Sofía",
            chat: [
                .init(fromMe: true, text: "¿Tacos esta noche? 🌮"),
                .init(fromMe: false, text: "¡Sí! ¿A las 8? Yo reservo ❤️"),
                .init(fromMe: true, text: "Te amo 😍")
            ],
            goals: ["Viaje a París", "Nuestra casa"],
            challenges: ["30 días sin pelear", "Una cita cada semana"]
        ),
        "fi": DemoContent(
            me: "Eetu", partner: "Aino",
            chat: [
                .init(fromMe: true, text: "Mennäänkö illalla sushille? 🍣"),
                .init(fromMe: false, text: "Joo! Klo 19, mä varaan pöydän ❤️"),
                .init(fromMe: true, text: "Jee, odotan innolla 😍")
            ],
            goals: ["Reissu Japaniin", "Häärahasto"],
            challenges: ["30 päivää ilman riitoja", "Viikoittainen treffi-ilta"]
        ),
        "fil": DemoContent(
            me: "Miguel", partner: "Bea",
            chat: [
                .init(fromMe: true, text: "Samgyup tayo mamaya? 🥓"),
                .init(fromMe: false, text: "G! 7pm ha, ako na magbu-book ❤️"),
                .init(fromMe: true, text: "Yay 😊")
            ],
            goals: ["Japan Trip Fund", "Pang-kasal na Ipon"],
            challenges: ["30 Araw na Walang Away", "Weekly Date Night"]
        ),
        "fr": DemoContent(
            me: "Hugo", partner: "Léa",
            chat: [
                .init(fromMe: true, text: "Resto japonais ce soir ? 🍣"),
                .init(fromMe: false, text: "Oui ! 20h ? Je réserve ❤️"),
                .init(fromMe: true, text: "Trop bien 😍")
            ],
            goals: ["Voyage au Japon", "Notre mariage"],
            challenges: ["30 jours sans dispute", "Un date par semaine"]
        ),
        "he": DemoContent(
            me: "איתי", partner: "נועה",
            chat: [
                .init(fromMe: true, text: "בא לך סושי הערב? 🍣"),
                .init(fromMe: false, text: "כן! ב-8, אני אזמין מקום ❤️"),
                .init(fromMe: true, text: "יש! מחכה כבר 😍")
            ],
            goals: ["טיול לתאילנד", "חיסכון לחתונה"],
            challenges: ["30 יום בלי ריבים", "דייט פעם בשבוע"]
        ),
        "hi": DemoContent(
            me: "आरव", partner: "अनन्या",
            chat: [
                .init(fromMe: true, text: "आज रात पिज़्ज़ा खाने चलें? 🍕"),
                .init(fromMe: false, text: "हाँ! 8 बजे, मैं बुक कर दूँगी ❤️"),
                .init(fromMe: true, text: "वाह 😊")
            ],
            goals: ["गोवा ट्रिप फंड", "शादी का फंड"],
            challenges: ["30 दिन बिना झगड़े", "हर हफ़्ते डेट नाइट"]
        ),
        "hu": DemoContent(
            me: "Bence", partner: "Réka",
            chat: [
                .init(fromMe: true, text: "Együnk ma este sushit? 🍣"),
                .init(fromMe: false, text: "Benne vagyok! 7-re foglalok ❤️"),
                .init(fromMe: true, text: "Szuper, már várom 😍")
            ],
            goals: ["Utazás Olaszországba", "Lakáskassza"],
            challenges: ["30 nap veszekedés nélkül", "Heti randiest"]
        ),
        "id": DemoContent(
            me: "Rizky", partner: "Putri",
            chat: [
                .init(fromMe: true, text: "Malam ini makan sate yuk? 🍢"),
                .init(fromMe: false, text: "Yuk! Jam 7 ya, aku yang pesen ❤️"),
                .init(fromMe: true, text: "Asyik 😊")
            ],
            goals: ["Liburan ke Korea", "Dana Pernikahan"],
            challenges: ["30 hari tanpa bertengkar", "Kencan setiap minggu"]
        ),
        "it": DemoContent(
            me: "Marco", partner: "Giulia",
            chat: [
                .init(fromMe: true, text: "Stasera pizza? 🍕"),
                .init(fromMe: false, text: "Sì! Alle 8? Prenoto io ❤️"),
                .init(fromMe: true, text: "Ti amo 😍")
            ],
            goals: ["Viaggio a New York", "La nostra casa"],
            challenges: ["30 giorni senza litigare", "Cena a due ogni settimana"]
        ),
        "ja": DemoContent(
            me: "翔太", partner: "美咲",
            chat: [
                .init(fromMe: true, text: "今夜ラーメン行かない？🍜"),
                .init(fromMe: false, text: "いいね！7時にしよ、予約しとく❤️"),
                .init(fromMe: true, text: "やった〜😊")
            ],
            goals: ["ハワイ旅行の貯金", "結婚式資金"],
            challenges: ["30日ケンカしない", "毎週デートの日"]
        ),
        "ko": DemoContent(
            me: "민준", partner: "서연",
            chat: [
                .init(fromMe: true, text: "오늘 저녁 삼겹살 먹을래? 🥓"),
                .init(fromMe: false, text: "좋아! 7시 어때? 내가 예약할게 ❤️"),
                .init(fromMe: true, text: "최고야 😊")
            ],
            goals: ["제주도 여행 자금", "신혼집 마련"],
            challenges: ["30일 동안 싸우지 않기", "매주 데이트하기"]
        ),
        "ms": DemoContent(
            me: "Aiman", partner: "Nurul",
            chat: [
                .init(fromMe: true, text: "Malam ni jom makan satay? 🍢"),
                .init(fromMe: false, text: "Jom! Pukul 8, saya tempah ❤️"),
                .init(fromMe: true, text: "Yeay 😊")
            ],
            goals: ["Bercuti ke Korea", "Tabung Kahwin"],
            challenges: ["30 hari tanpa bergaduh", "Dating setiap minggu"]
        ),
        "nb": DemoContent(
            me: "Henrik", partner: "Nora",
            chat: [
                .init(fromMe: true, text: "Sushi i kveld? 🍣"),
                .init(fromMe: false, text: "Ja! Kl. 19? Jeg bestiller bord ❤️"),
                .init(fromMe: true, text: "Gleder meg 😍")
            ],
            goals: ["Tur til Thailand", "Vårt bryllup"],
            challenges: ["30 dager uten krangling", "Datekveld hver uke"]
        ),
        "nl": DemoContent(
            me: "Daan", partner: "Sanne",
            chat: [
                .init(fromMe: true, text: "Vanavond sushi? 🍣"),
                .init(fromMe: false, text: "Ja! Om 7 uur? Ik reserveer ❤️"),
                .init(fromMe: true, text: "Top 😍")
            ],
            goals: ["Reis naar Bali", "Ons eigen huis"],
            challenges: ["30 dagen geen ruzie", "Wekelijkse date"]
        ),
        "pl": DemoContent(
            me: "Kuba", partner: "Zuzia",
            chat: [
                .init(fromMe: true, text: "Może pizza dziś wieczorem? 🍕"),
                .init(fromMe: false, text: "Jasne! O 19, zarezerwuję ❤️"),
                .init(fromMe: true, text: "Super, już nie mogę się doczekać 😍")
            ],
            goals: ["Wakacje w Grecji", "Wkład na mieszkanie"],
            challenges: ["30 dni bez kłótni", "Randka co tydzień"]
        ),
        "pt-BR": DemoContent(
            me: "Lucas", partner: "Julia",
            chat: [
                .init(fromMe: true, text: "Bora comer pizza hoje? 🍕"),
                .init(fromMe: false, text: "Bora! Às 20h? Eu reservo ❤️"),
                .init(fromMe: true, text: "Amei 😍")
            ],
            goals: ["Viagem pra Europa", "Nosso apê"],
            challenges: ["30 dias sem brigar", "Encontro toda semana"]
        ),
        "ro": DemoContent(
            me: "Andrei", partner: "Ioana",
            chat: [
                .init(fromMe: true, text: "Mergem diseară la o pizza? 🍕"),
                .init(fromMe: false, text: "Da! La 8, fac eu rezervare ❤️"),
                .init(fromMe: true, text: "Super, abia aștept 😍")
            ],
            goals: ["Vacanță în Grecia", "Avans pentru casă"],
            challenges: ["30 de zile fără certuri", "Întâlnire săptămânală"]
        ),
        "ru": DemoContent(
            me: "Артём", partner: "Алина",
            chat: [
                .init(fromMe: true, text: "Может, суши сегодня вечером? 🍣"),
                .init(fromMe: false, text: "Давай! В 8, я забронирую ❤️"),
                .init(fromMe: true, text: "Ура, жду не дождусь 😍")
            ],
            goals: ["Поездка в Италию", "На нашу свадьбу"],
            challenges: ["30 дней без ссор", "Свидание каждую неделю"]
        ),
        "sv": DemoContent(
            me: "Oscar", partner: "Elin",
            chat: [
                .init(fromMe: true, text: "Sushi ikväll? 🍣"),
                .init(fromMe: false, text: "Ja! Kl 19? Jag bokar ❤️"),
                .init(fromMe: true, text: "Älskar dig 😍")
            ],
            goals: ["Resa till Thailand", "Vårt bröllop"],
            challenges: ["30 dagar utan bråk", "Dejtkväll varje vecka"]
        ),
        "th": DemoContent(
            me: "ภูมิ", partner: "มายด์",
            chat: [
                .init(fromMe: true, text: "คืนนี้ไปกินหมูกระทะกันมั้ย 🔥"),
                .init(fromMe: false, text: "ไปสิ! ทุ่มนึงนะ เดี๋ยวจองให้ ❤️"),
                .init(fromMe: true, text: "เย้ 😊")
            ],
            goals: ["ทริปญี่ปุ่น", "เงินแต่งงาน"],
            challenges: ["30 วันไม่ทะเลาะกัน", "เดตทุกสัปดาห์"]
        ),
        "tr": DemoContent(
            me: "Emre", partner: "Elif",
            chat: [
                .init(fromMe: true, text: "Bu akşam lahmacun yiyelim mi? 🌯"),
                .init(fromMe: false, text: "Olur! 8'de, ben rezervasyon yaparım ❤️"),
                .init(fromMe: true, text: "Harika, sabırsızlanıyorum 😍")
            ],
            goals: ["Paris tatili", "Düğün birikimi"],
            challenges: ["30 gün kavgasız", "Haftalık randevu gecesi"]
        ),
        "uk": DemoContent(
            me: "Максим", partner: "Софія",
            chat: [
                .init(fromMe: true, text: "Може, суші сьогодні ввечері? 🍣"),
                .init(fromMe: false, text: "Так! О 8, я забронюю ❤️"),
                .init(fromMe: true, text: "Супер, вже чекаю 😍")
            ],
            goals: ["Подорож до Італії", "На наше весілля"],
            challenges: ["30 днів без сварок", "Побачення щотижня"]
        ),
        "vi": DemoContent(
            me: "Minh", partner: "Linh",
            chat: [
                .init(fromMe: true, text: "Tối nay đi ăn lẩu nha em 🍲"),
                .init(fromMe: false, text: "Ok anh, 7h nha, em đặt bàn ❤️"),
                .init(fromMe: true, text: "Yêu em 🥰")
            ],
            goals: ["Du lịch Hàn Quốc", "Quỹ cưới"],
            challenges: ["30 ngày không cãi nhau", "Hẹn hò mỗi tuần"]
        ),
        "zh-Hans": DemoContent(
            me: "浩然", partner: "欣怡",
            chat: [
                .init(fromMe: true, text: "今晚去吃火锅吧？🍲"),
                .init(fromMe: false, text: "好呀！七点吧，我来订位❤️"),
                .init(fromMe: true, text: "太好了😊")
            ],
            goals: ["三亚旅行基金", "婚礼基金"],
            challenges: ["30天不吵架", "每周约会之夜"]
        ),
        "zh-Hant": DemoContent(
            me: "冠宇", partner: "詠晴",
            chat: [
                .init(fromMe: true, text: "今晚去吃火鍋好不好？🍲"),
                .init(fromMe: false, text: "好啊！七點，我來訂位❤️"),
                .init(fromMe: true, text: "耶～😊")
            ],
            goals: ["日本旅遊基金", "買房頭期款"],
            challenges: ["30天不吵架", "每週約會之夜"]
        ),
    ]
}
#endif
