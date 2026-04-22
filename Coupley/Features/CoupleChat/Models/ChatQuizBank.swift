//
//  ChatQuizBank.swift
//  Coupley
//

import Foundation

struct ChatQuizTemplate {
    let questionId: String
    let topic: QuizTopic
    let question: String
    let subtitle: String
    let options: [String]
    let allowsMultiple: Bool
    /// Short insight shown when the user selects an option. Key = option string.
    let optionHints: [String: String]

    init(
        questionId: String,
        topic: QuizTopic,
        question: String,
        subtitle: String,
        options: [String],
        allowsMultiple: Bool,
        optionHints: [String: String] = [:]
    ) {
        self.questionId = questionId
        self.topic = topic
        self.question = question
        self.subtitle = subtitle
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.optionHints = optionHints
    }
}

enum ChatQuizBank {

    static let all: [ChatQuizTemplate] = [

        // MARK: - Love & Emotion

        .init(
            questionId: "ll_primary",
            topic: .loveLanguage,
            question: "Which makes you feel most loved?",
            subtitle: "This is how you receive love best — your partner needs to know this.",
            options: ["Words of affirmation", "Quality time", "Acts of service",
                      "Physical touch", "Gifts"],
            allowsMultiple: false,
            optionHints: [
                "Words of affirmation": "You thrive on being told. Compliments, 'I love you', a text saying you're appreciated — that's what fills your tank. Don't make them guess.",
                "Quality time": "Presence over presents. Undivided attention — phones away, eyes on each other — is worth more than anything. You feel loved when they show up fully.",
                "Acts of service": "When someone takes something off your plate, you feel truly seen. It says 'I was thinking about you' without saying a word.",
                "Physical touch": "Touch is your anchor. A hand on your back, a hug that lasts — it communicates care on a level words can't always reach.",
                "Gifts": "It's not about the price — it's proof that someone thought of you when you weren't there. Thoughtfulness is the whole point.",
            ]
        ),

        .init(
            questionId: "ll_reset",
            topic: .loveLanguage,
            question: "After a hard day, what helps you reset with your partner?",
            subtitle: "Knowing this helps them support you the right way — not just how they'd want to be supported.",
            options: ["A hug and silence", "A long conversation",
                      "Cooking or eating together", "Going for a walk",
                      "Space first, then reconnect"],
            allowsMultiple: false,
            optionHints: [
                "A hug and silence": "You don't need solutions — you need to feel held. Sometimes the most comforting thing is just being there without words.",
                "A long conversation": "Talking it through is how you process. Being heard and understood is what you need before anything else.",
                "Cooking or eating together": "Ritual grounds you. Doing something familiar and nourishing together is its own kind of therapy.",
                "Going for a walk": "Movement and fresh air clear your head. Being side by side, not face to face, makes it easier to open up.",
                "Space first, then reconnect": "You need to decompress alone before you can be present. This isn't distance — it's how you come back better.",
            ]
        ),

        .init(
            questionId: "ll_surprise",
            topic: .loveLanguage,
            question: "What's the most meaningful surprise someone could do for you?",
            subtitle: "The best gestures feel personal — this reveals what 'personal' means to you.",
            options: ["Plan a special date night", "Write me a heartfelt note",
                      "Cook my favourite meal", "Handle something stressful for me",
                      "Just show up when I need them"],
            allowsMultiple: false,
            optionHints: [
                "Plan a special date night": "You value effort and intentionality. Knowing they thought ahead and planned something just for you means everything.",
                "Write me a heartfelt note": "Permanent words hit differently. Knowing they took time to put feelings into writing is something you'll keep.",
                "Cook my favourite meal": "Small, personal acts of nurturing are your love language in action. The detail of knowing your favourites matters.",
                "Handle something stressful for me": "When they take on your burden without being asked, it says 'I see how much you're carrying'. That's love.",
                "Just show up when I need them": "Reliability is everything. Knowing they'll be there without needing to ask is the most grounding thing in the world.",
            ]
        ),

        .init(
            questionId: "ll_miss",
            topic: .loveLanguage,
            question: "When you miss your partner, what do you do?",
            subtitle: "",
            options: ["Text or call them right away", "Look at old photos or messages",
                      "Do something that reminds me of them",
                      "Keep busy to take my mind off it", "Tell them when I see them"],
            allowsMultiple: false,
            optionHints: [
                "Text or call them right away": "You reach out naturally — connection matters more than playing it cool. Your partner probably loves knowing you thought of them.",
                "Look at old photos or messages": "You hold onto memories. The past is something you actively cherish, not just let fade.",
                "Do something that reminds me of them": "You keep them present in your everyday life. Shared rituals and associations are meaningful to you.",
                "Keep busy to take my mind off it": "You manage your emotions through action. Missing someone is uncomfortable for you — you'd rather feel it when they're back.",
                "Tell them when I see them": "You save it. There's something intentional about holding that feeling and giving it directly.",
            ]
        ),

        // MARK: - Communication

        .init(
            questionId: "com_style",
            topic: .communication,
            question: "When something bothers you, how do you bring it up?",
            subtitle: "There's no wrong answer — understanding your style helps your partner meet you where you are.",
            options: ["Direct, right away", "After I've thought it through",
                      "I drop hints and hope they notice", "I wait until it builds up",
                      "It depends how serious it is"],
            allowsMultiple: false,
            optionHints: [
                "Direct, right away": "You value clarity and speed. Letting things sit feels worse than the awkward moment of saying it. Just make sure your tone matches your intention.",
                "After I've thought it through": "You process before you speak — which means you usually come in with clarity. Your partner might benefit from knowing you need time before talking.",
                "I drop hints and hope they notice": "You communicate indirectly, hoping they'll pick up on it. Worth asking: would you prefer they just asked you directly?",
                "I wait until it builds up": "Patience has limits, and bottling things leads to bigger blow-ups. Small, early conversations are usually gentler for everyone.",
                "It depends how serious it is": "Context-driven — you're flexible and read the room. That's a real skill, as long as the serious stuff always gets said.",
            ]
        ),

        .init(
            questionId: "com_listen",
            topic: .communication,
            question: "When your partner is upset, what do you naturally do?",
            subtitle: "How you respond by instinct — what you offer before thinking about what they need.",
            options: ["Listen without interrupting", "Try to fix the problem",
                      "Give them space to breathe", "Offer a hug first",
                      "Ask what they need from me"],
            allowsMultiple: false,
            optionHints: [
                "Listen without interrupting": "You make space. Being heard without someone jumping to solve it is often the most healing thing — and you provide that.",
                "Try to fix the problem": "Your instinct is to help practically. Just double-check they want solutions, not just someone to listen.",
                "Give them space to breathe": "You respect that some people need to settle before they can talk. That's emotionally mature — just communicate you're there when they're ready.",
                "Offer a hug first": "Physical comfort is your first language. Sometimes a hug says everything words can't — especially in the first moment.",
                "Ask what they need from me": "This is underrated. Instead of assuming, you check in first. That's a genuinely thoughtful approach to support.",
            ]
        ),

        .init(
            questionId: "com_apology",
            topic: .communication,
            question: "How do you prefer to receive an apology?",
            subtitle: "Apologies that miss the mark can feel worse than none at all — this matters.",
            options: ["Sincere words said directly to me", "A thoughtful gesture with the words",
                      "Changed behaviour over time — show me", "Quick acknowledgement and move on",
                      "A letter or message so I can process it alone"],
            allowsMultiple: false,
            optionHints: [
                "Sincere words said directly to me": "Eye contact, genuine words, no deflection — that's what lands for you. You need to feel the weight of it.",
                "A thoughtful gesture with the words": "Action alongside words proves it's real. Saying sorry while doing something kind shows they mean it.",
                "Changed behaviour over time — show me": "Talk is cheap. You believe in proof. This is fair — consistent change is the only real apology.",
                "Quick acknowledgement and move on": "You don't dwell. Acknowledge it, adjust, and move forward — dwelling makes it worse for you.",
                "A letter or message so I can process it alone": "You need to read and re-read it, take it in on your own time. Written apologies feel more considered to you.",
            ]
        ),

        .init(
            questionId: "com_check",
            topic: .communication,
            question: "How often do you like to have a real 'how are we doing?' conversation?",
            subtitle: "Relationship check-ins prevent small things from becoming big ones.",
            options: ["Regularly — monthly or more", "When something comes up",
                      "A few times a year feels right", "Rarely — I'd rather show it than say it",
                      "Whenever one of us needs it"],
            allowsMultiple: false,
            optionHints: [
                "Regularly — monthly or more": "You're proactive about the relationship. Regular check-ins keep you connected and prevent things from festering.",
                "When something comes up": "You're reactive rather than proactive — which works if you're both good at raising things when they happen.",
                "A few times a year feels right": "Structured but not overwhelming. You like intentional moments without it feeling like therapy every week.",
                "Rarely — I'd rather show it than say it": "You communicate through action more than words. Just make sure your partner feels secure — not everyone reads actions the same way.",
                "Whenever one of us needs it": "Open-door policy. This works well when both partners are comfortable raising things without a formal invitation.",
            ]
        ),

        .init(
            questionId: "com_phone",
            topic: .communication,
            question: "How do you feel about phone use when you're spending time together?",
            subtitle: "This is a surprisingly common source of friction in relationships.",
            options: ["Phones away — fully present", "Fine to use but not constantly",
                      "No rules, just use common sense", "Depends completely on the moment",
                      "I honestly don't think about it"],
            allowsMultiple: false,
            optionHints: [
                "Phones away — fully present": "Undivided attention is your standard for quality time. Scrolling while together feels dismissive to you.",
                "Fine to use but not constantly": "Balance. You don't want to police it, but you notice when someone's only half-there.",
                "No rules, just use common sense": "You're relaxed about it. You trust both of you to read when it's appropriate.",
                "Depends completely on the moment": "Contextual. A long dinner is different from watching TV together. You read the room.",
                "I honestly don't think about it": "It's not a tension point for you. Worth sharing with your partner in case it is for them.",
            ]
        ),

        // MARK: - Conflict

        .init(
            questionId: "conflict_style",
            topic: .conflict,
            question: "In a disagreement, which sounds most like you?",
            subtitle: "Most conflict issues aren't about who's right — they're about two different styles colliding.",
            options: ["I want to talk it out immediately", "I need time alone to cool down first",
                      "I look for the compromise right away", "I tend to avoid conflict where possible",
                      "I go quiet until I've figured out what I want to say"],
            allowsMultiple: false,
            optionHints: [
                "I want to talk it out immediately": "You'd rather address it head-on than let it sit. Be mindful — your partner might need space before they can engage productively.",
                "I need time alone to cool down first": "Distance helps you regulate before you respond. Let your partner know you're not shutting them out — you're coming back.",
                "I look for the compromise right away": "Resolution-focused. You see the relationship as bigger than the disagreement. That's a real strength.",
                "I tend to avoid conflict where possible": "Peace-keeping is valuable, but avoidance can allow resentment to build quietly. Some conversations are worth having.",
                "I go quiet until I've figured out what I want to say": "Thoughtful but inward. Your partner might read your silence as punishment — a quick 'I need to think' goes a long way.",
            ]
        ),

        .init(
            questionId: "conflict_makeup",
            topic: .conflict,
            question: "After a fight, how do you like to make up?",
            subtitle: "The repair matters as much as the argument itself.",
            options: ["A real conversation where we both feel heard",
                      "A hug — no words needed", "Do something fun together and reset",
                      "Give it time and let it settle naturally",
                      "A small gesture — coffee, a note, something thoughtful"],
            allowsMultiple: false,
            optionHints: [
                "A real conversation where we both feel heard": "You need closure through words. The fight isn't done until both sides have been acknowledged.",
                "A hug — no words needed": "Physical reconnection says more than a post-mortem. For you, touch closes the loop.",
                "Do something fun together and reset": "Moving forward together, doing something light — that's how you reset the energy between you.",
                "Give it time and let it settle naturally": "You don't force it. Time does the work, and you let the relationship find its own equilibrium again.",
                "A small gesture — coffee, a note, something thoughtful": "Action over words. You say 'I'm sorry' by showing it — and you receive apologies the same way.",
            ]
        ),

        .init(
            questionId: "conflict_trigger",
            topic: .conflict,
            question: "What's most likely to get under your skin in a relationship?",
            subtitle: "Knowing your triggers means they're less likely to catch you off guard.",
            options: ["Feeling unheard or dismissed", "Broken promises, even small ones",
                      "Passive aggression instead of honesty", "Not getting enough quality time",
                      "Feeling like I always have to initiate", "Criticism in front of others"],
            allowsMultiple: false,
            optionHints: [
                "Feeling unheard or dismissed": "You need to know your voice matters. When someone talks over you or brushes you off, it hits deep.",
                "Broken promises, even small ones": "Reliability is your baseline for trust. Small broken commitments add up and erode confidence.",
                "Passive aggression instead of honesty": "Say it or don't — but don't say it sideways. You'd rather hear something hard than feel tension you can't address.",
                "Not getting enough quality time": "Togetherness isn't optional for you — it's how you stay connected. Without it, you start to feel like strangers.",
                "Feeling like I always have to initiate": "Effort should go both ways. When it feels one-sided, you start questioning where you stand.",
                "Criticism in front of others": "Private matters stay private. Being called out publicly feels like a fundamental breach of respect.",
            ]
        ),

        // MARK: - Finance

        .init(
            questionId: "fin_style",
            topic: .finance,
            question: "How would you describe your natural approach to spending?",
            subtitle: "Neither extreme is wrong — but knowing where you sit helps you plan as a team.",
            options: ["Conservative — I save first, spend what's left",
                      "Balanced — I budget but allow for flexibility",
                      "Generous with experiences — money is for living",
                      "Spontaneous — I spend on what feels right in the moment"],
            allowsMultiple: false,
            optionHints: [
                "Conservative — I save first, spend what's left": "Security gives you peace of mind. You may need to loosen up around a partner who values experiences — and help them understand why savings matter to you.",
                "Balanced — I budget but allow for flexibility": "You're pragmatic and adaptable. You can work with most money personalities, which is a strength.",
                "Generous with experiences — money is for living": "You prioritise memories and moments. Just make sure there's enough runway for emergencies — which a budgeting partner can help with.",
                "Spontaneous — I spend on what feels right in the moment": "You live in the present. A shared budget might feel restrictive at first, but it can actually give you more freedom long-term.",
            ]
        ),

        .init(
            questionId: "fin_goal",
            topic: .finance,
            question: "What's a money goal you'd genuinely enjoy working toward together?",
            subtitle: "A shared financial goal is one of the strongest bonding exercises a couple can do.",
            options: ["Save for a big trip or experience",
                      "Buy a home or move somewhere better",
                      "Build an investment portfolio for the future",
                      "Create a comfortable emergency fund",
                      "Pay off debt together and start fresh",
                      "Splurge on something we've always wanted"],
            allowsMultiple: false,
            optionHints: [
                "Save for a big trip or experience": "Experiences over things — you want memories you'll both carry forever. A trip goal keeps you both motivated and excited.",
                "Buy a home or move somewhere better": "Stability and roots. This is a long-term signal — you're thinking about a shared future, not just right now.",
                "Build an investment portfolio for the future": "You're playing the long game. Future-you will thank both of you.",
                "Create a comfortable emergency fund": "Safety net first. This is one of the most loving things a couple can do for each other — removing financial anxiety.",
                "Pay off debt together and start fresh": "Starting from a clean slate. There's real intimacy in tackling someone's financial baggage together.",
                "Splurge on something we've always wanted": "Permission to enjoy now. Sometimes the goal is just the thing you've been putting off — and doing it together makes it better.",
            ]
        ),

        .init(
            questionId: "fin_split",
            topic: .finance,
            question: "How do you think couples should handle money?",
            subtitle: "There's no universally right answer — but alignment here prevents serious friction.",
            options: ["Fully combined — one pot, full transparency",
                      "Mostly combined, with some personal spending money",
                      "Mostly separate, split shared costs fairly",
                      "Fully separate — independent finances, clear shared agreements",
                      "Still figuring this out"],
            allowsMultiple: false,
            optionHints: [
                "Fully combined — one pot, full transparency": "Total partnership. This builds deep trust and makes planning easy — it also requires real vulnerability about spending.",
                "Mostly combined, with some personal spending money": "Practical balance. Shared responsibility plus personal autonomy. Most couples find this sustainable long-term.",
                "Mostly separate, split shared costs fairly": "Independence is important to you. You contribute equally but maintain autonomy — worth agreeing on what 'fair' means.",
                "Fully separate — independent finances, clear shared agreements": "You value financial independence. This works well with clear agreements on how shared expenses are handled.",
                "Still figuring this out": "Honest answer. Money conversations are uncomfortable but necessary — starting with how you each *feel* about it is a good first step.",
            ]
        ),

        .init(
            questionId: "fin_splurge",
            topic: .finance,
            question: "If you had an extra $1,000 right now, you'd…",
            subtitle: "This reveals your natural financial instinct — not what you 'should' do.",
            options: ["Put it straight into savings", "Invest it",
                      "Plan a weekend trip or experience", "Buy something I've wanted for a while",
                      "Split it — some savings, some fun", "Donate part of it"],
            allowsMultiple: false,
            optionHints: [
                "Put it straight into savings": "Future-focused by instinct. You feel safer with a bigger cushion. That's valuable — especially if your partner leans toward spending.",
                "Invest it": "You think in terms of growth. Money sitting still makes you restless. A good counterbalance to a partner who prioritises security.",
                "Plan a weekend trip or experience": "Experiences energise you and you'd rather spend on memories than things. A trip becomes a shared story.",
                "Buy something I've wanted for a while": "You have a list, and you're patient. This isn't impulse — it's rewarding yourself deliberately.",
                "Split it — some savings, some fun": "Balanced by nature. You probably navigate money conversations relatively easily with most partners.",
                "Donate part of it": "Generosity is a core value. You think beyond yourself — that's worth knowing for a partner who shares (or doesn't share) that instinct.",
            ]
        ),

        // MARK: - Lifestyle

        .init(
            questionId: "life_weekend",
            topic: .lifestyle,
            question: "Your perfect Sunday looks like…",
            subtitle: "How people recharge tells you a lot about what they need week to week.",
            options: ["Slow morning, nowhere to be", "Out exploring somewhere new",
                      "Catching up with friends or family", "Working on a project I care about",
                      "Staying in bed longer than I should", "Doing nothing together — just being"],
            allowsMultiple: false,
            optionHints: [
                "Slow morning, nowhere to be": "You need decompression time. A rushed Sunday feels like no break at all. Mornings at your own pace refuel you.",
                "Out exploring somewhere new": "Curiosity and novelty energise you. Staying still too long makes you feel restless — you need the world outside.",
                "Catching up with friends or family": "Social connection is restorative for you. People give you energy, not drain it. Sunday is for the people you love.",
                "Working on a project I care about": "Flow state is your kind of weekend. Productive rest — doing something meaningful even when you don't have to — is your thing.",
                "Staying in bed longer than I should": "Rest without guilt. You probably don't get enough of it during the week, and Sunday is where you catch up on yourself.",
                "Doing nothing together — just being": "Comfortable silence and no agenda. That kind of ease with someone is a real signal of closeness.",
            ]
        ),

        .init(
            questionId: "life_energy",
            topic: .lifestyle,
            question: "When do you feel most alive?",
            subtitle: "Knowing when you're at your best matters for planning shared time — and giving each other space.",
            options: ["Early morning — I'm at my peak", "Late night — I come alive after dark",
                      "Middle of the day — peak hours", "Depends entirely on the day",
                      "Honestly, whenever I'm with the right people"],
            allowsMultiple: false,
            optionHints: [
                "Early morning — I'm at my peak": "Morning person through and through. You probably make better decisions, have deeper conversations, and feel most creative before noon.",
                "Late night — I come alive after dark": "Your best thinking, energy, and creativity happens when everyone else is winding down. Mismatched schedules with an early bird can create real friction.",
                "Middle of the day — peak hours": "Your rhythm is conventional — which actually works well in most shared-life contexts.",
                "Depends entirely on the day": "You're adaptive and mood-driven. That flexibility is a strength as long as you can communicate when you're 'off'.",
                "Honestly, whenever I'm with the right people": "Connection is your energy source, not time of day. The quality of company matters more than the clock to you.",
            ]
        ),

        .init(
            questionId: "life_social",
            topic: .lifestyle,
            question: "How do you feel about socialising as a couple?",
            subtitle: "Couple time vs social time is one of the most negotiated parts of a relationship.",
            options: ["Love it — the more plans the better",
                      "Enjoy it, but I need couple time too",
                      "Prefer small group or one-on-one settings",
                      "Mostly just the two of us, please",
                      "It depends on my mood and energy that week"],
            allowsMultiple: false,
            optionHints: [
                "Love it — the more plans the better": "Socially energised. You probably have a full calendar and feel most alive around people. A more introverted partner might need you to protect some downtime.",
                "Enjoy it, but I need couple time too": "Balanced. You can do both — but you're also deliberate about protecting the relationship bubble.",
                "Prefer small group or one-on-one settings": "Quality over quantity. Big group dynamics can feel draining — you'd rather go deep with fewer people.",
                "Mostly just the two of us, please": "The relationship is your sanctuary. Too many external commitments can feel like they dilute the intimacy you value.",
                "It depends on my mood and energy that week": "Context-driven and honest. As long as you can communicate where you're at, this flexibility works well.",
            ]
        ),

        .init(
            questionId: "life_cleanliness",
            topic: .lifestyle,
            question: "How important is a tidy home to you?",
            subtitle: "Cleanliness expectations are quietly one of the biggest lived-in relationship flashpoints.",
            options: ["Very — mess genuinely stresses me out",
                      "I prefer tidy but I'm not obsessive",
                      "Lived-in is comfortable — I like it homely",
                      "I genuinely don't notice unless it's extreme",
                      "I care in bursts — big clean every so often is fine"],
            allowsMultiple: false,
            optionHints: [
                "Very — mess genuinely stresses me out": "Your environment directly affects your mental state. A tidy space isn't aesthetic preference — it's a genuine need. Worth communicating early.",
                "I prefer tidy but I'm not obsessive": "Middle ground. You appreciate order but you're not going to fight about a dish in the sink.",
                "Lived-in is comfortable — I like it homely": "Warmth over perfection. Home should feel comfortable and real — not a showroom. A partner who needs perfect tidiness might find this friction.",
                "I genuinely don't notice unless it's extreme": "Low sensitivity to clutter. You'll want to actively meet a tidier partner's needs — because you genuinely won't see what bothers them.",
                "I care in bursts — big clean every so often is fine": "Periodic effort over daily maintenance. As long as expectations are aligned, this works fine.",
            ]
        ),

        .init(
            questionId: "life_morning",
            topic: .lifestyle,
            question: "What does your ideal morning routine look like?",
            subtitle: "Morning compatibility is surprisingly important when you share a space.",
            options: ["Quiet and slow — no rushing", "Productive from the moment I wake",
                      "Coffee first, everything else negotiable",
                      "As short as possible — I'm not a morning person",
                      "It changes, I go with how I feel"],
            allowsMultiple: false,
            optionHints: [
                "Quiet and slow — no rushing": "Mornings set the tone for your whole day. You need a gentle start — a rushed or chaotic morning throws you off.",
                "Productive from the moment I wake": "You hit the ground running. Mornings are your window for your best work or thinking. Protect that time.",
                "Coffee first, everything else negotiable": "Relatable and honest. You need that first ritual before you're functional. Knowing this helps a partner not take the morning grumpiness personally.",
                "As short as possible — I'm not a morning person": "Mornings are something to survive, not enjoy. You probably thrive later in the day — and that's fine, just worth knowing.",
                "It changes, I go with how I feel": "Flexible and mood-driven. You don't need routine to feel grounded — or you haven't found the right one yet.",
            ]
        ),

        .init(
            questionId: "life_night",
            topic: .lifestyle,
            question: "What helps you wind down at night?",
            subtitle: "Evening routines matter a lot when you share a bed and a home.",
            options: ["Reading until I fall asleep", "Watching something together or alone",
                      "A shower or bath — ritual reset",
                      "Talking to my partner — the day in review",
                      "Scrolling my phone (not proud of it)",
                      "Exercise or a walk in the evening",
                      "I just go to sleep — no routine needed"],
            allowsMultiple: true,
            optionHints: [
                "Reading until I fall asleep": "Screens off, book open. Reading is protective — it signals to your brain that the day is over. A quiet, compatible wind-down for most partners.",
                "Watching something together or alone": "Passive relaxation works for you. This can be a great shared couple ritual — or totally individual, depending on the show.",
                "A shower or bath — ritual reset": "Physical transition from day to night. Washing the day off is literal for you. A very grounding habit.",
                "Talking to my partner — the day in review": "Connection is how you close the loop on the day. This is a beautiful couple ritual — make sure your partner knows how much it means.",
                "Scrolling my phone (not proud of it)": "Honest. Screen time before bed disrupts sleep quality — but many people do it. Worth working on together.",
                "Exercise or a walk in the evening": "Evening movement energises you before it calms you down. You sleep better having moved. Some partners find this incompatible — worth discussing.",
                "I just go to sleep — no routine needed": "Efficient. You don't need rituals to decompress — or you're usually exhausted enough not to need them.",
            ]
        ),

        // MARK: - Intimacy

        .init(
            questionId: "intimacy_checkin",
            topic: .intimacy,
            question: "What makes you feel closest to your partner?",
            subtitle: "Closeness isn't just physical — it's created in different ways for different people.",
            options: ["Eye contact and real presence", "A long, honest conversation",
                      "Comfortable silence — no need to fill it",
                      "Physical closeness without needing a reason",
                      "Being completely silly and stupid together",
                      "Doing something meaningful side by side"],
            allowsMultiple: false,
            optionHints: [
                "Eye contact and real presence": "Being truly seen — not just looked at. Full attention, no distractions, just them focused on you. That's intimacy for you.",
                "A long, honest conversation": "Depth creates closeness. The more honestly someone talks to you, the closer you feel. Surface conversations leave you distant.",
                "Comfortable silence — no need to fill it": "The ability to be quiet together without it being awkward is a real sign of ease and intimacy. You value that comfort.",
                "Physical closeness without needing a reason": "Touch as connection — not necessarily sexual. Just being near each other, body language saying 'I'm here'.",
                "Being completely silly and stupid together": "Laughter and playfulness are intimacy too. When you can be goofy with someone, the guard is down — that's vulnerability.",
                "Doing something meaningful side by side": "Shared purpose builds closeness. Cooking, building, creating — doing something that matters to you both.",
            ]
        ),

        .init(
            questionId: "intimacy_spark",
            topic: .intimacy,
            question: "What keeps the spark alive for you long-term?",
            subtitle: "The spark doesn't have to fade — but what maintains it is different for everyone.",
            options: ["Consistent date nights and intentional effort",
                      "Trying new things and breaking routine",
                      "Small daily gestures that say 'I'm thinking of you'",
                      "Honest conversations, including the uncomfortable ones",
                      "Missing each other — time apart makes the heart grow",
                      "Playfulness — not taking everything too seriously"],
            allowsMultiple: false,
            optionHints: [
                "Consistent date nights and intentional effort": "Ritual and effort. You believe the spark is maintained through consistent investment, not just left to chance.",
                "Trying new things and breaking routine": "Novelty is the fuel. New experiences together keep you from going stale. You need to keep exploring as a couple.",
                "Small daily gestures that say 'I'm thinking of you'": "The everyday moments matter most. A text, a coffee made the way you like it — these add up to a relationship that feels alive.",
                "Honest conversations, including the uncomfortable ones": "Depth over comfort. You believe real closeness comes from talking about things other couples avoid.",
                "Missing each other — time apart makes the heart grow": "Absence creates appreciation. You need space to miss your partner — and that longing keeps things fresh.",
                "Playfulness — not taking everything too seriously": "Lightness is underrated in long-term relationships. Couples who laugh together tend to last.",
            ]
        ),

        .init(
            questionId: "intimacy_affection",
            topic: .intimacy,
            question: "How do you show affection most naturally?",
            subtitle: "We often love others the way we want to be loved — not always how they receive it best.",
            options: ["Saying it out loud — 'I love you', compliments",
                      "Doing things for them without being asked",
                      "Physical closeness — touches, hugs, sitting close",
                      "Giving them my full, undivided time",
                      "Little surprise gestures that show I remembered something"],
            allowsMultiple: false,
            optionHints: [
                "Saying it out loud — 'I love you', compliments": "Words come naturally to you as expressions of love. Worth checking whether your partner receives verbal affirmation as easily as you give it.",
                "Doing things for them without being asked": "Acts of service is your natural expression. You show love by making their life easier — a beautiful but often unnoticed love language.",
                "Physical closeness — touches, hugs, sitting close": "Touch is instinctive for you. You reach out physically when you care — and you probably notice when that diminishes.",
                "Giving them my full, undivided time": "Presence is your gift. When you care about someone, you show it by actually being there — fully, not halfway.",
                "Little surprise gestures that show I remembered something": "Attentiveness is your love language. You prove you've been listening by acting on small details — that's quietly powerful.",
            ]
        ),

        // MARK: - Music

        .init(
            questionId: "music_mood",
            topic: .music,
            question: "What music matches your current mood?",
            subtitle: "Genre, artist, or even just a vibe — whatever comes to mind.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "music_shared",
            topic: .music,
            question: "Which genres could you see us listening to together?",
            subtitle: "Pick everything that resonates — shared playlists are underrated couple glue.",
            options: ["Indie / alternative", "Pop", "R&B / soul", "Hip-hop",
                      "Classical / instrumental", "Lo-fi / chill", "Rock",
                      "Electronic / EDM", "Jazz", "K-Pop", "Country",
                      "Acoustic / singer-songwriter", "Reggae / Afrobeats",
                      "Latin / salsa", "Metal / punk"],
            allowsMultiple: true
        ),

        .init(
            questionId: "music_memory",
            topic: .music,
            question: "Is there a song that takes you back to a big moment in your life?",
            subtitle: "Music is memory. Tell us what it is — or what period of life it reminds you of.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "music_car",
            topic: .music,
            question: "What's your go-to driving or commuting music?",
            subtitle: "",
            options: ["Podcasts or audiobooks", "Loud upbeat music — I sing along",
                      "Chill background music", "Whatever shuffle gives me",
                      "Silence — I like to think"],
            allowsMultiple: false,
            optionHints: [
                "Podcasts or audiobooks": "You use transit time to learn or explore stories. That's a productive, curious mindset.",
                "Loud upbeat music — I sing along": "Maximum energy, maximum volume. You probably arrive in a better mood than when you left.",
                "Chill background music": "Ambient and calming. You're not trying to perform — you just want a pleasant backdrop.",
                "Whatever shuffle gives me": "Spontaneous and unbothered. You can enjoy almost anything. Low-maintenance taste.",
                "Silence — I like to think": "You process in quiet. Commute time is thinking time. Or decompression time. Either way, silence is chosen, not default.",
            ]
        ),

        // MARK: - Sport & Fitness

        .init(
            questionId: "sport_together",
            topic: .sport,
            question: "What active things could you see us doing together?",
            subtitle: "Even if you're not very active now — what would you actually try?",
            options: ["Hiking or nature walks", "Running or jogging",
                      "Yoga or stretching together", "Swimming",
                      "Cycling", "Tennis or badminton", "Going to the gym",
                      "Dancing", "Rock climbing", "Martial arts or kickboxing",
                      "A team sport", "Skiing or snowboarding", "Surfing",
                      "Kayaking or paddleboarding"],
            allowsMultiple: true
        ),

        .init(
            questionId: "sport_habit",
            topic: .sport,
            question: "How do you honestly feel about exercise right now?",
            subtitle: "No judgment — where you are with this affects your energy, mood, and schedules.",
            options: ["It's a non-negotiable part of my day",
                      "I do it regularly but inconsistently",
                      "I prefer low-key activity — walking, stretching",
                      "I want to be more active but haven't made it stick",
                      "It's really not my thing"],
            allowsMultiple: false,
            optionHints: [
                "It's a non-negotiable part of my day": "Fitness is a core identity piece for you. A partner who doesn't value it at all might create friction — or become your motivation.",
                "I do it regularly but inconsistently": "You have the intention and the habit, life just gets in the way. A partner who makes it social can help a lot.",
                "I prefer low-key activity — walking, stretching": "Movement without intensity. You value feeling good over performance. Great for someone who can match that pace.",
                "I want to be more active but haven't made it stick": "Honest. A supportive partner who makes activity social and fun — rather than a chore — could be the missing piece.",
                "It's really not my thing": "That's valid. Just worth knowing if your partner finds it central to their identity or mental health.",
            ]
        ),

        // MARK: - Travel

        .init(
            questionId: "travel_style",
            topic: .travel,
            question: "Your ideal trip leans toward…",
            subtitle: "Travel compatibility can make or break a holiday — this is worth knowing early.",
            options: ["Relaxed beach and nature — recharge mode",
                      "City breaks — culture, food, architecture",
                      "Adventure and outdoors — challenging ourselves",
                      "Food-focused — eating our way through a place",
                      "A long roadtrip with no fixed itinerary",
                      "Cultural immersion — local experiences, off the tourist trail"],
            allowsMultiple: false,
            optionHints: [
                "Relaxed beach and nature — recharge mode": "Holiday means decompression. You want calm, warmth, and nothing scheduled. A packed itinerary is someone else's trip.",
                "City breaks — culture, food, architecture": "You absorb a place through its streets, museums, and restaurants. Cities give you stimulation and story material.",
                "Adventure and outdoors — challenging ourselves": "Travel as experience and challenge. You want to come back having done something you couldn't do at home.",
                "Food-focused — eating our way through a place": "The table is where culture actually lives. You book restaurants before flights and that is correct.",
                "A long roadtrip with no fixed itinerary": "Freedom and spontaneity — the plan is to have no plan. The best moments are the unplanned ones.",
                "Cultural immersion — local experiences, off the tourist trail": "Depth over tourism. You want to understand a place, not just photograph it.",
            ]
        ),

        .init(
            questionId: "travel_pace",
            topic: .travel,
            question: "How do you like to travel?",
            subtitle: "Travel pace is one of the most underestimated sources of couple conflict on holiday.",
            options: ["Every day planned in detail — I research everything",
                      "Loose structure — key things booked, rest flexible",
                      "Mostly spontaneous with a general direction",
                      "Let my partner lead — I'm easy",
                      "Whatever works — I adapt"],
            allowsMultiple: false,
            optionHints: [
                "Every day planned in detail — I research everything": "Planning is how you prevent disappointment and maximise the trip. A spontaneous partner might find this rigid — but you find their lack of planning stressful.",
                "Loose structure — key things booked, rest flexible": "Best of both worlds. You have a safety net but room to breathe. Most people travel happily with you.",
                "Mostly spontaneous with a general direction": "Adventure over agenda. You trust that it'll work out — and it usually does. A planner partner might need some reassurance.",
                "Let my partner lead — I'm easy": "Low-maintenance and adaptable. Just make sure you actually speak up when something matters to you — being 'easy' can leave you resentful.",
                "Whatever works — I adapt": "Genuinely flexible. You probably won't cause holiday friction — you're the one who smooths it over.",
            ]
        ),

        .init(
            questionId: "travel_dream",
            topic: .travel,
            question: "Name one place you'd love to go together",
            subtitle: "Any country, city, national park — something on your list.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "travel_budget",
            topic: .travel,
            question: "What kind of traveller are you when it comes to budget?",
            subtitle: "",
            options: ["Budget traveller — maximise days, minimise cost",
                      "Mid-range — comfortable but not extravagant",
                      "I'd rather go less often and do it properly",
                      "Full luxury when possible — it's a treat",
                      "Depends entirely on the trip"],
            allowsMultiple: false,
            optionHints: [
                "Budget traveller — maximise days, minimise cost": "More trips, less per trip. You want volume of experience. Hostels and street food don't scare you.",
                "Mid-range — comfortable but not extravagant": "Value-driven. You want a good bed and a good meal without feeling reckless. That's most people's sweet spot.",
                "I'd rather go less often and do it properly": "Quality over quantity. One exceptional trip a year beats four mediocre ones.",
                "Full luxury when possible — it's a treat": "You save for indulgence. Holiday is for doing things you can't do at home — including the nice hotel.",
                "Depends entirely on the trip": "Context matters. A weekend city break vs. a honeymoon deserve different budgets. Pragmatic.",
            ]
        ),

        // MARK: - Food

        .init(
            questionId: "food_comfort",
            topic: .food,
            question: "What's your go-to comfort food right now?",
            subtitle: "The foods that make you feel at home — no judgment.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "food_date",
            topic: .food,
            question: "Ideal food-based date night?",
            subtitle: "Food is one of the easiest ways to show care — knowing what your partner loves matters.",
            options: ["Cook something new at home together",
                      "Our tried-and-true favourite restaurant",
                      "Try somewhere brand new — surprise me",
                      "Takeaway on the couch — no effort required",
                      "Street food, markets, or something casual and fun",
                      "A fancy tasting menu or special occasion restaurant"],
            allowsMultiple: false,
            optionHints: [
                "Cook something new at home together": "Collaboration as romance. The kitchen becomes its own kind of quality time — and you get a meal at the end.",
                "Our tried-and-true favourite restaurant": "Comfort and ritual. You don't need the exciting — you need the reliable. Familiarity is its own kind of joy.",
                "Try somewhere brand new — surprise me": "Novelty is exciting to you even in dining. You enjoy the discovery — and you probably eat more adventurously too.",
                "Takeaway on the couch — no effort required": "Sometimes the best date is the one where no one has to put on shoes. Comfort and ease over ambiance.",
                "Street food, markets, or something casual and fun": "Atmosphere over formality. You want the energy of being out without the formality of a sit-down.",
                "A fancy tasting menu or special occasion restaurant": "You appreciate the craft. A great meal as an experience in itself — worth saving for.",
            ]
        ),

        .init(
            questionId: "food_diet",
            topic: .food,
            question: "How would you describe your eating habits?",
            subtitle: "This affects shared meals, grocery shopping, and dining out — worth knowing.",
            options: ["I eat everything — no restrictions",
                      "Mostly healthy with regular treats",
                      "Plant-based or vegetarian",
                      "Vegan",
                      "Following a specific diet for health or fitness goals",
                      "Pretty picky — I have a very specific list of things I like"],
            allowsMultiple: false,
            optionHints: [
                "I eat everything — no restrictions": "Maximum compatibility. You're easy to feed and easy to take out. You probably have an adventurous palate too.",
                "Mostly healthy with regular treats": "Balanced and realistic. You're not extreme — you enjoy food but you also take care of yourself.",
                "Plant-based or vegetarian": "Worth knowing early — it shapes where you eat, what you cook, and potentially what your partner is willing to adapt to.",
                "Vegan": "A more committed choice that affects many shared meals and dining decisions. Alignment here is genuinely important.",
                "Following a specific diet for health or fitness goals": "Intentional eater. Your goals drive your food choices. Helpful for a partner to understand — especially around shared cooking.",
                "Pretty picky — I have a very specific list of things I like": "Honest and self-aware. A partner who loves food variety will need to know this upfront — and that's fine.",
            ]
        ),

        .init(
            questionId: "food_cook",
            topic: .food,
            question: "What's your relationship with cooking?",
            subtitle: "In shared-life relationships, this ends up mattering a lot.",
            options: ["I love it and cook regularly",
                      "I can cook but prefer when someone else does",
                      "I'm learning and actually enjoying it",
                      "I'll do it for my partner but not for myself",
                      "I'm genuinely a disaster in the kitchen",
                      "I don't cook — delivery and restaurants are fine"],
            allowsMultiple: false,
            optionHints: [
                "I love it and cook regularly": "Cooking is a love language in its own right. A partner who appreciates a home-cooked meal is your ideal audience.",
                "I can cook but prefer when someone else does": "Capable but unmotivated alone. The right person in the kitchen might change this.",
                "I'm learning and actually enjoying it": "A growing skill you're investing in. This is a great shared activity — especially if your partner can teach you.",
                "I'll do it for my partner but not for myself": "Caring through action. You cook as an act of love, not habit. That's meaningful.",
                "I'm genuinely a disaster in the kitchen": "Honest. A cooking partner who teaches or takes over is genuinely appreciated — and you probably clean up in return.",
                "I don't cook — delivery and restaurants are fine": "Practical and unapologetic. Just worth knowing if your partner values home cooking or wants the kitchen to be a shared space.",
            ]
        ),

        // MARK: - Family

        .init(
            questionId: "family_kids",
            topic: .family,
            question: "How do you feel about having kids in the future?",
            subtitle: "This is one of the most important alignment questions in any serious relationship.",
            options: ["Yes — I want kids, it's a priority for me",
                      "Open to it — I'd consider it with the right person",
                      "Not sure yet — I'm still working through this",
                      "Probably not — leaning toward no",
                      "Definitely no — this is a firm decision for me"],
            allowsMultiple: false,
            optionHints: [
                "Yes — I want kids, it's a priority for me": "A clear yes. This isn't negotiable for you — and that's completely valid. Make sure a partner knows this early.",
                "Open to it — I'd consider it with the right person": "Flexible but not indifferent. You're not actively wanting or avoiding — you're open to what the relationship calls for.",
                "Not sure yet — I'm still working through this": "Honest uncertainty. This often changes with age, circumstances, and the right partner. Worth revisiting periodically.",
                "Probably not — leaning toward no": "You're moving toward no, even if you haven't fully committed to that position yet. Worth being transparent with a partner who feels strongly.",
                "Definitely no — this is a firm decision for me": "A clear no. Just as valid as a clear yes. Mismatch on this isn't something love usually resolves.",
            ]
        ),

        .init(
            questionId: "family_closeness",
            topic: .family,
            question: "How close are you with your own family?",
            subtitle: "Family dynamics shape expectations in relationships — more than most people realise.",
            options: ["Very close — we talk all the time and see each other often",
                      "Close, but with healthy boundaries",
                      "Mixed — some family I'm close to, others I'm not",
                      "Not very close — we have a cordial but distant relationship",
                      "It's complicated — there's history here"],
            allowsMultiple: false,
            optionHints: [
                "Very close — we talk all the time and see each other often": "Family is central to your life. A partner will need to understand and respect that — and probably show up for family things regularly.",
                "Close, but with healthy boundaries": "You value family without losing yourself in it. You've probably done some work on understanding what healthy closeness looks like.",
                "Mixed — some family I'm close to, others I'm not": "Real and nuanced. Most people's family relationships are complicated — you're just honest about it.",
                "Not very close — we have a cordial but distant relationship": "Distance by choice or circumstance. Worth understanding whether that's peaceful or painful — it affects how you approach 'family' as a couple.",
                "It's complicated — there's history here": "There's depth to this. A supportive partner needs to know what they're stepping into — and that you may need space or help navigating it.",
            ]
        ),

        .init(
            questionId: "family_inlaw",
            topic: .family,
            question: "How do you want to handle each other's families as a couple?",
            subtitle: "This becomes very real once you're living together or getting serious.",
            options: ["Fully embrace them — they're family too",
                      "Warm and present, but with clear boundaries",
                      "Respectful and polite, but we keep things mostly separate",
                      "We figure it out together as situations arise",
                      "Depends entirely on the family"],
            allowsMultiple: false,
            optionHints: [
                "Fully embrace them — they're family too": "You want full integration. In-laws are your family too — you invest in those relationships genuinely.",
                "Warm and present, but with clear boundaries": "Healthy engagement. You show up, you care, but you also protect the couple's space. That's sustainable.",
                "Respectful and polite, but we keep things mostly separate": "Friendly but separate. You can be kind without being entangled. Worth making sure that's mutual.",
                "We figure it out together as situations arise": "Adaptive and collaborative. You don't set rigid rules — you navigate it as a team. That requires trust.",
                "Depends entirely on the family": "Realistic. Different families call for different approaches. What matters is that you're both on the same page.",
            ]
        ),

        .init(
            questionId: "family_pets",
            topic: .family,
            question: "How do you feel about pets?",
            subtitle: "Pets are a lifestyle choice that affects shared living in big ways.",
            options: ["I have one / have had one and love it",
                      "I'd love to have a pet eventually",
                      "Love other people's pets, not ready to own one",
                      "Not interested in having pets",
                      "Allergic or can't have them for practical reasons",
                      "Open if it matters to my partner"],
            allowsMultiple: false,
            optionHints: [
                "I have one / have had one and love it": "Pets are part of your life and any future living situation. A partner who doesn't like animals will have a harder time.",
                "I'd love to have a pet eventually": "It's on your list. Worth aligning timing and who takes on what responsibility.",
                "Love other people's pets, not ready to own one": "You like animals without wanting the full commitment right now. That might change — or it might not.",
                "Not interested in having pets": "A clear position. Nothing wrong with it — but worth knowing if your partner is deeply attached to the idea.",
                "Allergic or can't have them for practical reasons": "A hard limitation. If your partner has or wants a pet, this is a genuine compatibility conversation.",
                "Open if it matters to my partner": "Accommodating and willing. Just make sure you genuinely mean it — pets are a long commitment.",
            ]
        ),

        // MARK: - Career

        .init(
            questionId: "career_balance",
            topic: .career,
            question: "How do you want work to fit into your life?",
            subtitle: "Career ambition shapes schedules, energy levels, and what you expect from home.",
            options: ["Work hard, play hard — I give it everything",
                      "Steady and sustainable — life exists outside of work",
                      "My work is my passion — it doesn't feel like work",
                      "Flexible and remote — location freedom matters",
                      "I'm in a phase of building — more now, less later"],
            allowsMultiple: false,
            optionHints: [
                "Work hard, play hard — I give it everything": "High effort, high reward. You probably have big goals and you're willing to sacrifice for them. A partner needs to be okay with that.",
                "Steady and sustainable — life exists outside of work": "Work is a means, not the point. You protect your evenings and weekends. That's a mature, healthy boundary.",
                "My work is my passion — it doesn't feel like work": "The lucky ones. Intrinsic motivation means you'll work hard without it feeling like sacrifice — but partners sometimes feel second-place to a passion.",
                "Flexible and remote — location freedom matters": "Lifestyle design. You want work that fits around your life, not the other way around. Alignment with a partner's location and schedule matters.",
                "I'm in a phase of building — more now, less later": "Temporary intensity with a plan. Knowing this is a phase, not a permanent identity, helps a partner understand the sacrifice.",
            ]
        ),

        .init(
            questionId: "career_ambition",
            topic: .career,
            question: "How ambitious are you about your career right now?",
            subtitle: "Ambition mismatches aren't dealbreakers, but they need to be talked about.",
            options: ["Very — it's one of my top priorities",
                      "Moderately — I care, but life is bigger than my job",
                      "Career is a means to an end — it funds the life I want",
                      "I'm still figuring out what I want to do",
                      "I'm actively making a change or transition"],
            allowsMultiple: false,
            optionHints: [
                "Very — it's one of my top priorities": "Career success is core to your identity. A partner needs to be your biggest cheerleader — and accept that it costs time.",
                "Moderately — I care, but life is bigger than my job": "Balanced. You have professional pride without losing yourself in it. You're probably easy to be in a relationship with around this.",
                "Career is a means to an end — it funds the life I want": "Pragmatic. Your real life happens outside of work. The job serves the vision.",
                "I'm still figuring out what I want to do": "Honest uncertainty. That's okay — especially if you're in a transition phase. A supportive partner can be an anchor.",
                "I'm actively making a change or transition": "A period of flux and possibility. Your partner needs to know this is coming — in terms of income, time, and emotional bandwidth.",
            ]
        ),

        .init(
            questionId: "career_stress",
            topic: .career,
            question: "When work is stressful, what do you need from your partner?",
            subtitle: "Work stress is inevitable — knowing how to support each other makes a real difference.",
            options: ["Just listen — I don't want solutions",
                      "Distract me with something fun or light",
                      "Give me space to decompress alone first",
                      "Practical help — pick up some slack at home",
                      "Encouragement and belief that I'll get through it",
                      "A reality check — tell me it'll be okay"],
            allowsMultiple: false,
            optionHints: [
                "Just listen — I don't want solutions": "You need to vent, not be fixed. Letting your partner know this prevents the frustrating 'yes but have you tried…' response.",
                "Distract me with something fun or light": "Escape is your recovery mechanism. Getting out of your head with something enjoyable is more restorative than talking it through.",
                "Give me space to decompress alone first": "You need to process alone before you can be present. Let your partner know you're not withdrawing — you're coming back better.",
                "Practical help — pick up some slack at home": "When you're overwhelmed at work, reducing the home pressure means everything. Tangible support over emotional support.",
                "Encouragement and belief that I'll get through it": "You need your partner in your corner, not just beside you. Confidence and faith from them refuels yours.",
                "A reality check — tell me it'll be okay": "You spiral a little and you know it. You need someone to gently ground you in perspective.",
            ]
        ),

        .init(
            questionId: "career_dream",
            topic: .career,
            question: "If you could do anything for work, what would it be?",
            subtitle: "The dream job, completely unconstrained. Even if it feels out of reach.",
            options: [],
            allowsMultiple: false
        ),

        // MARK: - Health & Wellness

        .init(
            questionId: "health_mental",
            topic: .lifestyle,
            question: "How do you take care of your mental health?",
            subtitle: "This is one of the most important things to know about each other.",
            options: ["Therapy or counselling", "Regular exercise",
                      "Journaling or creative outlets", "Talking to close friends",
                      "Meditation or mindfulness practice",
                      "Being outdoors or in nature", "Limiting social media",
                      "Honestly — I'm still building this", "I don't have a consistent practice"],
            allowsMultiple: true,
            optionHints: [
                "Therapy or counselling": "You invest in your mental health seriously. That takes courage and self-awareness — and it makes you a more self-aware partner.",
                "Regular exercise": "Movement as medicine. Your mood, energy, and stress are closely tied to whether you've moved your body. A partner should know this.",
                "Journaling or creative outlets": "You process through expression. Writing, drawing, making — these aren't hobbies, they're how you stay sane.",
                "Talking to close friends": "Connection is your therapy. You process best in conversation with people you trust. Your partner is probably part of that circle.",
                "Meditation or mindfulness practice": "Intentional stillness. You've built a practice that grounds you — and that probably makes you calmer in conflict too.",
                "Being outdoors or in nature": "Nature is genuinely restorative for you. Time outside shifts your whole system. A partner who understands this will suggest a walk, not just a talk.",
                "Limiting social media": "Intentional about your inputs. You know that comparison and noise affect your mental state — and you manage it.",
                "Honestly — I'm still building this": "Self-aware about what you need but still working on it. That honesty is its own kind of health.",
                "I don't have a consistent practice": "Worth thinking about together. Supporting each other's wellbeing is one of the best things couples can do.",
            ]
        ),

        .init(
            questionId: "health_stress",
            topic: .lifestyle,
            question: "When you're overwhelmed or stressed, you usually…",
            subtitle: "Your stress response reveals how your nervous system works — and how your partner can help.",
            options: ["Go quiet and need space to process",
                      "Talk it out with someone close to me",
                      "Throw myself into something productive",
                      "Distract myself — shows, games, anything",
                      "Exercise or move — burn it off",
                      "Eat or drink something comforting",
                      "Worry about it repeatedly until it passes"],
            allowsMultiple: false,
            optionHints: [
                "Go quiet and need space to process": "Inward. You need to sit with it alone before you're ready to share or connect. Let people in eventually — don't disappear.",
                "Talk it out with someone close to me": "Social processing. Saying it out loud helps you understand how you feel. Your partner is probably your first call.",
                "Throw myself into working through it": "Action-oriented. You feel better when you're doing something about it — even if there's nothing to do. Channel that well.",
                "Distract myself — shows, games, anything": "Escape before engagement. You need to lower the volume before you can face it. Just don't use distraction to avoid indefinitely.",
                "Exercise or move — burn it off": "Your body is the outlet. Stress is physical for you — and burning it off actually works. Your partner should just hand you your gym bag.",
                "Eat or drink something comforting": "Oral comfort is your soothe. Not always sustainable — but very human. Worth having something else in the toolkit too.",
                "Worry about it repeatedly until it passes": "Anxious processing. Your mind works through repetition and what-ifs. A grounding partner who doesn't dismiss the anxiety helps most.",
            ]
        ),

        .init(
            questionId: "health_sleep",
            topic: .lifestyle,
            question: "How do you feel about your sleep?",
            subtitle: "Sleep affects mood, patience, and how available you are as a partner.",
            options: ["I sleep great and protect it seriously",
                      "Decent most nights — no major issues",
                      "Inconsistent — stress or thoughts keep me up",
                      "Chronically tired — it's a known problem",
                      "Night owl who would sleep better if I went to bed earlier"],
            allowsMultiple: false,
            optionHints: [
                "I sleep great and protect it seriously": "Sleep is sacred for you. A partner who keeps you up, or has different sleep habits, will affect your functioning — and your mood.",
                "Decent most nights — no major issues": "Baseline healthy. You probably take it for granted, which is fine — until you're sharing a bed with someone with very different habits.",
                "Inconsistent — stress or thoughts keep me up": "Your mental state directly affects your sleep. High-stress periods will hit your sleep first. Worth having a wind-down routine.",
                "Chronically tired — it's a known problem": "This is affecting everything — your mood, your patience, your capacity for connection. Worth treating it as a priority.",
                "Night owl who would sleep better if I went to bed earlier": "You know the solution but you don't do it. An earlier-to-bed partner might actually help — or drive you crazy.",
            ]
        ),

        // MARK: - Entertainment & Hobbies

        .init(
            questionId: "ent_shows",
            topic: .lifestyle,
            question: "What kind of content do you actually watch?",
            subtitle: "Pick everything that describes what's on your watchlist right now.",
            options: ["Drama / thriller", "Comedy — I need to laugh",
                      "Romance", "Documentaries", "Sci-fi or fantasy",
                      "Reality TV", "True crime", "Horror",
                      "Action / adventure", "Anime",
                      "Nature / travel content", "News and current affairs"],
            allowsMultiple: true
        ),

        .init(
            questionId: "ent_books",
            topic: .lifestyle,
            question: "What's your relationship with reading?",
            subtitle: "",
            options: ["Always reading something — it's a core habit",
                      "I read occasionally when I find the right book",
                      "More of a podcast person",
                      "Audiobooks count, right?",
                      "I used to read more — I want to get back to it",
                      "Honestly not my thing"],
            allowsMultiple: false,
            optionHints: [
                "Always reading something — it's a core habit": "Books are central to how you learn and decompress. Recommending books to each other is a great couple ritual.",
                "I read occasionally when I find the right book": "You need the hook. Genre and recommendation matter — the right book at the right time changes everything.",
                "More of a podcast person": "Audio learner and story lover. You absorb ideas while doing other things. Probably has great recommendations.",
                "Audiobooks count, right?": "Absolutely. You still love stories and ideas — just in a format that fits your life better.",
                "I used to read more — I want to get back to it": "It's still in there. Life crowded it out. A book-recommending partner might be the nudge.",
                "Honestly not my thing": "That's fine. Worth knowing if your partner is a big reader — they might want to share that part of their world.",
            ]
        ),

        .init(
            questionId: "ent_hobbies",
            topic: .lifestyle,
            question: "What do you actually do in your spare time?",
            subtitle: "Pick everything that genuinely takes up your free time.",
            options: ["Gaming", "Art, drawing, or creative making",
                      "Cooking and food", "Sport or fitness",
                      "Music — playing or listening seriously",
                      "Reading", "Outdoors — hiking, nature",
                      "Photography or videography",
                      "Coding or building things",
                      "Socialising — I'm always seeing people",
                      "Nothing — I rest and I'm not sorry",
                      "Watching content", "Gardening",
                      "Fashion or personal style",
                      "Learning something new online"],
            allowsMultiple: true
        ),

        .init(
            questionId: "ent_games",
            topic: .lifestyle,
            question: "Do you game or play board games?",
            subtitle: "",
            options: ["Video games are a big part of my life",
                      "I play occasionally — casual gamer",
                      "Board games with friends — that's my thing",
                      "Both — games in general are fun",
                      "Not really my thing at all"],
            allowsMultiple: false,
            optionHints: [
                "Video games are a big part of my life": "Gaming is a real part of your social and leisure life. A partner needs to understand the time and the community that comes with it.",
                "I play occasionally — casual gamer": "Low-stakes relationship with games. You enjoy it without it being a significant time investment.",
                "Board games with friends — that's my thing": "Social and strategic. Board games are about the people as much as the game. A great shared hobby.",
                "Both — games in general are fun": "Games as a general love. You probably appreciate any kind of play — which is a good instinct in a relationship too.",
                "Not really my thing at all": "Fair. Just worth knowing if your partner would love to play with you — or if they need their gaming time respected.",
            ]
        ),

        // MARK: - Personal Growth

        .init(
            questionId: "growth_goal",
            topic: .lifestyle,
            question: "What's one thing you're actively trying to improve about yourself?",
            subtitle: "Not what you think you should say — what you're actually working on.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "growth_fear",
            topic: .lifestyle,
            question: "What's something you'd love to try but something holds you back?",
            subtitle: "Fear, logistics, self-doubt — whatever it is.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "growth_proud",
            topic: .lifestyle,
            question: "What achievement are you most proud of in your own life?",
            subtitle: "Big or small — just something that actually means something to you.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "growth_learn",
            topic: .lifestyle,
            question: "If you could get good at one new skill this year, what would it be?",
            subtitle: "",
            options: ["A new language", "Cooking something complex",
                      "An instrument or music skill",
                      "A physical skill — sport, dance, martial art",
                      "A creative skill — writing, art, photography",
                      "A professional or tech skill",
                      "Something outdoors — climbing, surfing, sailing",
                      "Something I find difficult — public speaking, confidence"],
            allowsMultiple: false,
            optionHints: [
                "A new language": "Communication unlocks worlds. There's probably somewhere you want to go — or someone you want to understand.",
                "Cooking something complex": "Food as craft. You want the skill, not just the result. Great for someone who loves feeding people.",
                "An instrument or music skill": "Music as expression. Even modest skill in an instrument changes how you experience music entirely.",
                "A physical skill — sport, dance, martial art": "Embodied learning. Getting better at something physical is uniquely satisfying — and often social.",
                "A creative skill — writing, art, photography": "Making things. You probably have ideas inside you that you haven't found a way to express yet.",
                "A professional or tech skill": "Practical investment in yourself. This one probably connects to bigger ambitions.",
                "Something outdoors — climbing, surfing, sailing": "Adventure and environment. You want skill that takes you somewhere.",
                "Something I find difficult — public speaking, confidence": "Tackling the uncomfortable. This is growth at its most valuable — and often the hardest.",
            ]
        ),

        // MARK: - Future & Life Vision

        .init(
            questionId: "future_where",
            topic: .lifestyle,
            question: "Where do you picture yourself living in 5 years?",
            subtitle: "Location expectations matter more than people discuss early in relationships.",
            options: ["Same city I'm in now — I'm rooted here",
                      "A different city in the same country",
                      "Another country entirely",
                      "Somewhere quieter — smaller city or rural",
                      "I genuinely don't know — open to anything",
                      "Wherever life and opportunity takes me"],
            allowsMultiple: false,
            optionHints: [
                "Same city I'm in now — I'm rooted here": "You have roots — community, family, career — that matter to you. Moving would be a big ask. A partner needs to know this.",
                "A different city in the same country": "Open to change but within familiar culture. You want a fresh start without full relocation uncertainty.",
                "Another country entirely": "Adventure and reinvention. This is a major life move — worth knowing if your partner shares that openness.",
                "Somewhere quieter — smaller city or rural": "Slower pace, more space. You're drawn to calm over stimulation. A city-loving partner might find this hard.",
                "I genuinely don't know — open to anything": "Maximum flexibility — or genuine uncertainty. Either way, you're not anchored to a specific place, which is a real freedom.",
                "Wherever life and opportunity takes me": "Optimistic and adaptive. You go where things are good. That requires a partner who can move with you.",
            ]
        ),

        .init(
            questionId: "future_home",
            topic: .lifestyle,
            question: "What does your dream home look like?",
            subtitle: "The space you live in affects everything — how you rest, socialise, work.",
            options: ["City apartment — in the middle of everything",
                      "House with a garden and outdoor space",
                      "Somewhere surrounded by nature",
                      "Something unique or unconventional",
                      "A home with space for a home office",
                      "It doesn't matter — it's who I'm with that counts"],
            allowsMultiple: false,
            optionHints: [
                "City apartment — in the middle of everything": "Energy and access. You want walkability, noise, convenience. The city is your natural habitat.",
                "House with a garden and outdoor space": "Space to breathe. A garden for dinner, kids, a dog — you're thinking in domestic terms and that's honest.",
                "Somewhere surrounded by nature": "Environment as lifestyle. You want to wake up to green, not concrete. That usually means committing to a location.",
                "Something unique or unconventional": "Personality in your environment. Converted warehouse, boat, off-grid cabin — you want the space to say something about you.",
                "A home with space for a home office": "Work from home is real life now. Having a proper space matters for your productivity and your sanity.",
                "It doesn't matter — it's who I'm with that counts": "Romantic and adaptable. You can be happy anywhere with the right person — and that's genuinely true for some people.",
            ]
        ),

        .init(
            questionId: "future_bucket",
            topic: .lifestyle,
            question: "What's on your bucket list that we could do together?",
            subtitle: "Something you've actually thought about — not what sounds impressive.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "future_retire",
            topic: .lifestyle,
            question: "What does retirement look like to you?",
            subtitle: "How you picture the end game reveals a lot about what you value now.",
            options: ["Travel as much as possible — see everything",
                      "Be close to family and watch them grow",
                      "Start a passion project I've been saving for",
                      "Slow, quiet life — peace is the point",
                      "Keep working on things I care about",
                      "It's too far away to meaningfully think about"],
            allowsMultiple: false,
            optionHints: [
                "Travel as much as possible — see everything": "The reward for a life of work is seeing the world. You're probably saving toward a version of freedom.",
                "Be close to family and watch them grow": "Connection and legacy. Being present for the people you love in the final chapter means everything to you.",
                "Start a passion project I've been saving for": "Deferred dreams. There's something you've always wanted to build or create — and you're playing a long game.",
                "Slow, quiet life — peace is the point": "Rest as reward. You've probably worked hard enough — or watched others not stop — to know what you want at the end.",
                "Keep working on things I care about": "Identity beyond retirement. You won't stop — you'll just redirect. Purpose keeps people young.",
                "It's too far away to meaningfully think about": "Present-focused. You're not wired for long-range planning — or you're young enough that this feels theoretical.",
            ]
        ),

        // MARK: - Deeper Values

        .init(
            questionId: "values_deal",
            topic: .communication,
            question: "What's a non-negotiable for you in a relationship?",
            subtitle: "The thing that, if it's missing, you can't make the relationship work.",
            options: ["Honesty — even when it's uncomfortable",
                      "Mutual respect, always",
                      "Emotional availability and presence",
                      "Shared values and direction in life",
                      "Laughter and lightness",
                      "Loyalty and commitment",
                      "Physical and emotional intimacy",
                      "Personal freedom within the relationship"],
            allowsMultiple: false,
            optionHints: [
                "Honesty — even when it's uncomfortable": "You'd rather hear something hard than be managed with comfortable half-truths. Radical honesty is both your standard and your offer.",
                "Mutual respect, always": "The floor, not the ceiling. Everything else can be worked on — but disrespect breaks the foundation.",
                "Emotional availability and presence": "Being truly there — not just physically. You need a partner who can sit with feelings, theirs and yours.",
                "Shared values and direction in life": "Alignment on the big things — how you want to live, what you're building. Compatibility of vision matters.",
                "Laughter and lightness": "A relationship without joy isn't sustainable. You need someone who can be funny, silly, and light even when life isn't.",
                "Loyalty and commitment": "Being chosen, consistently. Not just at the beginning — but every day after that too.",
                "Physical and emotional intimacy": "Closeness in all its forms. When physical and emotional connection is missing, everything else feels hollow.",
                "Personal freedom within the relationship": "You need to remain yourself — your friendships, your interests, your space. Love shouldn't feel like losing yourself.",
            ]
        ),

        .init(
            questionId: "values_ideal",
            topic: .communication,
            question: "What does your ideal version of 'us' look like in 3 years?",
            subtitle: "Paint a picture — the life you'd both be living if things went well.",
            options: [],
            allowsMultiple: false
        ),

        .init(
            questionId: "values_support",
            topic: .communication,
            question: "What does 'being there for someone' mean to you?",
            subtitle: "People support differently — understanding this prevents a lot of missed connection.",
            options: ["Dropping everything when they need me",
                      "Consistent small acts of care over time",
                      "Listening without jumping to advice",
                      "Doing whatever practically helps",
                      "Respecting whatever they say they need",
                      "Staying close without smothering"],
            allowsMultiple: false,
            optionHints: [
                "Dropping everything when they need me": "Emergency presence is your love language of support. You show up fully when it matters most.",
                "Consistent small acts of care over time": "Reliability over heroics. You're not there for the drama — you're there in the daily showing up.",
                "Listening without jumping to advice": "The gift of being heard. You know how to hold space — and you resist the urge to fix. That's rare.",
                "Doing whatever practically helps": "Tangible support. You show love through action when someone's struggling — not just words.",
                "Respecting whatever they say they need": "You follow their lead. You don't impose your version of support — you ask and then deliver what they actually want.",
                "Staying close without smothering": "Presence with space. You're there — but you don't crowd. That requires reading someone well.",
            ]
        ),

        .init(
            questionId: "values_growth",
            topic: .communication,
            question: "Do you believe couples should grow together or retain their independence?",
            subtitle: "How you balance 'us' and 'me' is one of the defining dynamics of any relationship.",
            options: ["Mostly together — aligned goals and direction",
                      "Strong individual identity first, then shared",
                      "Both equally — you grow together and apart",
                      "It shifts across different life seasons",
                      "Still figuring out where I land on this"],
            allowsMultiple: false,
            optionHints: [
                "Mostly together — aligned goals and direction": "You see the relationship as a joint project. Major decisions involve both of you — and that's how you want it.",
                "Strong individual identity first, then shared": "Independence keeps you healthy. You bring a full person to the relationship rather than merging completely.",
                "Both equally — you grow together and apart": "The nuanced answer — and often the healthiest one. Together where it counts, independent where it matters.",
                "It shifts across different life seasons": "Context-dependent. Different phases of life call for different balance — and you know that.",
                "Still figuring out where I land on this": "Honest. This is one of those things you often learn more about by being in the relationship than before it.",
            ]
        ),

        // MARK: - Fun & Personality

        .init(
            questionId: "fun_intro",
            topic: .lifestyle,
            question: "Where do you fall on the introvert–extrovert spectrum?",
            subtitle: "This affects how you recharge, socialise, and need space in a relationship.",
            options: ["Introvert — alone time genuinely recharges me",
                      "Extrovert — I get energy from being around people",
                      "Ambivert — I'm genuinely both depending on context",
                      "More introverted but I push myself socially",
                      "More extroverted but I value alone time"],
            allowsMultiple: false,
            optionHints: [
                "Introvert — alone time genuinely recharges me": "Solitude is not loneliness for you — it's necessary. A partner who always wants company might feel like pressure. Communicate this early.",
                "Extrovert — I get energy from being around people": "Socially fuelled. Being alone too much drains you. A partner who needs a lot of space might leave you feeling disconnected.",
                "Ambivert — I'm genuinely both depending on context": "Flexible and context-sensitive. You probably navigate most social situations well — and can meet introverted or extroverted partners.",
                "More introverted but I push myself socially": "You can do the social things but you pay a cost. Recovery time after social events is real for you.",
                "More extroverted but I value alone time": "You need people but you're not dependent on them. A healthy mix of connection and personal space suits you best.",
            ]
        ),

        .init(
            questionId: "fun_spontaneous",
            topic: .lifestyle,
            question: "How spontaneous are you?",
            subtitle: "This reveals how you handle surprise, change, and uncertainty — in life and in relationships.",
            options: ["Very spontaneous — let's do it right now",
                      "I like a rough plan but can improvise",
                      "I prefer to plan things — surprises stress me",
                      "I want to say spontaneous but I actually need notice",
                      "It depends entirely on what it is"],
            allowsMultiple: false,
            optionHints: [
                "Very spontaneous — let's do it right now": "You thrive in the unplanned. Rigid schedules feel like a cage. A partner who over-plans might slow you down — or ground you.",
                "I like a rough plan but can improvise": "Flexible within structure. You want a safety net but you don't need a script. Most people find this easy to work with.",
                "I prefer to plan things — surprises stress me": "You feel safer with a plan. That's not a character flaw — it's how you manage anxiety and perform at your best.",
                "I want to say spontaneous but I actually need notice": "Honest self-awareness. You admire spontaneity but practically function better with lead time.",
                "It depends entirely on what it is": "Contextual. A last-minute dinner? Yes. A last-minute flight? Maybe not. You're not rigid — you're reading the stakes.",
            ]
        ),

        .init(
            questionId: "fun_humor",
            topic: .lifestyle,
            question: "What kind of humour do you have?",
            subtitle: "Shared humour is one of the strongest relationship compatibility signals.",
            options: ["Dry and sarcastic", "Silly and physical — I'm a kid",
                      "Observational — I notice things others miss",
                      "Self-deprecating — I take the easy target",
                      "Dark, but always kind", "Wordplay and puns — genuinely",
                      "Storytelling — I make things funny through context",
                      "I'm a good audience but not the joke-maker"],
            allowsMultiple: true,
            optionHints: [
                "Dry and sarcastic": "Understated. Your humour rewards people who are paying attention. Not everyone gets it — but the ones who do, get you.",
                "Silly and physical — I'm a kid": "Uninhibited. You're comfortable being ridiculous — and that ease is actually quite intimate. Hard to be silly with someone you're guarded around.",
                "Observational — I notice things others miss": "You find the absurdity in everyday things. Your humour is a byproduct of how closely you pay attention.",
                "Self-deprecating — I take the easy target": "You disarm people by going first. It's a confidence thing, not a low self-esteem thing — when done right.",
                "Dark, but always kind": "You find funny in difficult places — but you punch toward the world, not toward vulnerable people. That distinction matters.",
                "Wordplay and puns — genuinely": "You love language enough to play with it. Puns are dad jokes done with commitment — and that takes guts.",
                "Storytelling — I make things funny through context": "The build-up is your thing. You're funnier in person than in a text — and your stories improve with every retelling.",
                "I'm a good audience but not the joke-maker": "You appreciate humour deeply even if you don't perform it. Being a great audience is its own underrated gift.",
            ]
        ),

        .init(
            questionId: "fun_dealbreaker",
            topic: .lifestyle,
            question: "Pineapple on pizza — where do you stand?",
            subtitle: "This tells us everything.",
            options: ["Absolutely yes — I will die on this hill",
                      "Hard no — it's a textures thing",
                      "I don't care either way — this is not important",
                      "Only under very specific conditions"],
            allowsMultiple: false,
            optionHints: [
                "Absolutely yes — I will die on this hill": "Bold. Unwavering. You know what you like and you're not ashamed of it. That's actually a personality trait.",
                "Hard no — it's a textures thing": "Principled. You have standards and you apply them to pizza. Fruit belongs elsewhere.",
                "I don't care either way — this is not important": "The most balanced take. Possibly the most well-adjusted person in this quiz.",
                "Only under very specific conditions": "A nuanced position on pizza. You probably apply this level of conditional thinking to most of life's questions.",
            ]
        ),

        // MARK: - Childhood & Background

        .init(
            questionId: "child_holiday",
            topic: .lifestyle,
            question: "What were holidays and celebrations like growing up?",
            subtitle: "How you grew up celebrating shapes what you expect — and want — now.",
            options: ["Big, loud family gatherings — the more the better",
                      "Quiet, intimate — just close family",
                      "Inconsistent — it depended on the year",
                      "Mostly normal days — we weren't big on celebration",
                      "Travelling or doing something different"],
            allowsMultiple: false,
            optionHints: [
                "Big, loud family gatherings — the more the better": "You probably replicate this or miss it. Celebration is big, communal, and festive in your imagination.",
                "Quiet, intimate — just close family": "Celebration as closeness. Big gatherings feel overwhelming — you prefer the depth of a small group.",
                "Inconsistent — it depended on the year": "Unpredictability was part of your experience. You may have complicated feelings about celebrations as a result.",
                "Mostly normal days — we weren't big on celebration": "You don't have strong emotional ties to holidays — which can be freeing or leave you feeling like something's missing.",
                "Travelling or doing something different": "Experience over tradition. Celebration meant adventure — and you probably still prefer that over a dinner table.",
            ]
        ),

        .init(
            questionId: "child_influence",
            topic: .lifestyle,
            question: "How much has your upbringing shaped who you are today?",
            subtitle: "No right answer — this is about your relationship to your own history.",
            options: ["A lot — for better and worse, it made me",
                      "Mostly positive — I had a good foundation",
                      "I've consciously worked to unlearn some of it",
                      "Not much — I've forged my own path",
                      "It's complicated and I'm still working it out"],
            allowsMultiple: false,
            optionHints: [
                "A lot — for better and worse, it made me": "Self-aware about where you come from. The good and difficult parts of your story are both visible to you.",
                "Mostly positive — I had a good foundation": "Lucky and grateful. You carry patterns worth repeating into your own relationships.",
                "I've consciously worked to unlearn some of it": "Growth in action. You've identified things you don't want to pass on — and you're doing the work. That's significant.",
                "Not much — I've forged my own path": "Independent by design or necessity. You've written your own story largely separate from where you began.",
                "It's complicated and I'm still working it out": "Honest. Most people are. The willingness to examine it is the most important part.",
            ]
        ),
    ]

    static func byId(_ id: String) -> ChatQuizTemplate? {
        all.first { $0.questionId == id }
    }

    static func byTopic(_ topic: QuizTopic) -> [ChatQuizTemplate] {
        all.filter { $0.topic == topic }
    }
}
