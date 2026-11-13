//
//  ChatQuizBank.swift
//  Coupley
//

import Foundation

/// One answerable choice.
///
/// `id` is the identity; `label` is only ever drawn. They were the same string
/// until now, which is why translating an option used to break three separate
/// things at once: the stored answer stopped matching the partner's, the
/// `Set` intersection that decides a match found nothing, and the insight
/// paragraph — looked up in a dictionary keyed by the English text — went
/// silently nil.
///
/// The id is scoped to its template, so two templates may reuse a slug.
/// Resolution always goes through `ChatQuizBank.byId(questionId)` first.
///
/// `label` is the base-language (English) text. It stays in the source after
/// localization as the catalog's base value, which is what lets
/// `option(label:)` keep decoding documents written before ids existed.
struct ChatQuizOption: Equatable {
    let id: String

    /// BASE-LANGUAGE text. Never translated, and never drawn directly.
    ///
    /// This is the string that gets written into Firestore alongside the id,
    /// and the key `option(label:)` matches when resolving a document that
    /// predates ids. Both of those have to keep working after the catalog
    /// lands, which they only do if this property stays English — so the
    /// display path goes through `displayLabel` instead, and that is the one
    /// place localization hooks in.
    ///
    /// Keeping one property for both jobs is what made the old `optionHints`
    /// dictionary fail: it was keyed by the same string the UI drew.
    let label: String

    /// Short insight shown once the user has picked this option. `nil` for the
    /// four multi-select pickers (genres, sports, content, hobbies) that
    /// deliberately carry none.
    let hint: String?

    /// What to draw. Identical to `label` until there is a string catalog;
    /// then this becomes the lookup and `label` stays put.
    var displayLabel: String { label }

    init(_ id: String, _ label: String, _ hint: String? = nil) {
        self.id = id
        self.label = label
        self.hint = hint
    }
}

struct ChatQuizTemplate {
    let questionId: String
    let topic: QuizTopic
    let question: String
    let subtitle: String
    let options: [ChatQuizOption]
    let allowsMultiple: Bool

    init(
        questionId: String,
        topic: QuizTopic,
        question: String,
        subtitle: String,
        options: [ChatQuizOption],
        allowsMultiple: Bool
    ) {
        self.questionId = questionId
        self.topic = topic
        self.question = question
        self.subtitle = subtitle
        self.options = options
        self.allowsMultiple = allowsMultiple
    }

    /// Base-language text in declaration order — what gets denormalized onto
    /// a new quiz document. Storage, not display.
    var optionLabels: [String] { options.map(\.label) }

    /// Stable ids in declaration order, parallel to `optionLabels`.
    var optionIds: [String] { options.map(\.id) }

    func option(id: String) -> ChatQuizOption? {
        options.first { $0.id == id }
    }

    /// Resolves an option from the text a document stored before ids existed.
    /// Exact match only — a near-miss must read as unknown rather than as the
    /// wrong option.
    func option(label: String) -> ChatQuizOption? {
        options.first { $0.label == label }
    }

    /// The id for a stored display string, or nil if this template has no such
    /// option (a reworded bank entry, or a document from another app version).
    func optionId(forLabel label: String) -> String? {
        option(label: label)?.id
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
            options: [
                .init("words_of_affirmation", "Words of affirmation",
                      "You thrive on being told. Compliments, 'I love you', a text saying you're appreciated — that's what fills your tank. Don't make them guess."),
                .init("quality_time", "Quality time",
                      "Presence over presents. Undivided attention — phones away, eyes on each other — is worth more than anything. You feel loved when they show up fully."),
                .init("acts_of_service", "Acts of service",
                      "When someone takes something off your plate, you feel truly seen. It says 'I was thinking about you' without saying a word."),
                .init("physical_touch", "Physical touch",
                      "Touch is your anchor. A hand on your back, a hug that lasts — it communicates care on a level words can't always reach."),
                .init("gifts", "Gifts",
                      "It's not about the price — it's proof that someone thought of you when you weren't there. Thoughtfulness is the whole point."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "ll_reset",
            topic: .loveLanguage,
            question: "After a hard day, what helps you reset with your partner?",
            subtitle: "Knowing this helps them support you the right way — not just how they'd want to be supported.",
            options: [
                .init("a_hug_and_silence", "A hug and silence",
                      "You don't need solutions — you need to feel held. Sometimes the most comforting thing is just being there without words."),
                .init("a_long_conversation", "A long conversation",
                      "Talking it through is how you process. Being heard and understood is what you need before anything else."),
                .init("cooking_or_eating_together", "Cooking or eating together",
                      "Ritual grounds you. Doing something familiar and nourishing together is its own kind of therapy."),
                .init("going_for_a_walk", "Going for a walk",
                      "Movement and fresh air clear your head. Being side by side, not face to face, makes it easier to open up."),
                .init("space_first_then_reconnect", "Space first, then reconnect",
                      "You need to decompress alone before you can be present. This isn't distance — it's how you come back better."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "ll_surprise",
            topic: .loveLanguage,
            question: "What's the most meaningful surprise someone could do for you?",
            subtitle: "The best gestures feel personal — this reveals what 'personal' means to you.",
            options: [
                .init("plan_a_special_date_night", "Plan a special date night",
                      "You value effort and intentionality. Knowing they thought ahead and planned something just for you means everything."),
                .init("write_me_a_heartfelt_note", "Write me a heartfelt note",
                      "Permanent words hit differently. Knowing they took time to put feelings into writing is something you'll keep."),
                .init("cook_my_favourite_meal", "Cook my favourite meal",
                      "Small, personal acts of nurturing are your love language in action. The detail of knowing your favourites matters."),
                .init("handle_something_stressful_for_me", "Handle something stressful for me",
                      "When they take on your burden without being asked, it says 'I see how much you're carrying'. That's love."),
                .init("just_show_up_when_i_need_them", "Just show up when I need them",
                      "Reliability is everything. Knowing they'll be there without needing to ask is the most grounding thing in the world."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "ll_miss",
            topic: .loveLanguage,
            question: "When you miss your partner, what do you do?",
            subtitle: "",
            options: [
                .init("text_or_call_them_right_away", "Text or call them right away",
                      "You reach out naturally — connection matters more than playing it cool. Your partner probably loves knowing you thought of them."),
                .init("look_at_old_photos_or_messages", "Look at old photos or messages",
                      "You hold onto memories. The past is something you actively cherish, not just let fade."),
                .init("do_something_that_reminds_me_of_them", "Do something that reminds me of them",
                      "You keep them present in your everyday life. Shared rituals and associations are meaningful to you."),
                .init("keep_busy_to_take_my_mind_off_it", "Keep busy to take my mind off it",
                      "You manage your emotions through action. Missing someone is uncomfortable for you — you'd rather feel it when they're back."),
                .init("tell_them_when_i_see_them", "Tell them when I see them",
                      "You save it. There's something intentional about holding that feeling and giving it directly."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Communication

        .init(
            questionId: "com_style",
            topic: .communication,
            question: "When something bothers you, how do you bring it up?",
            subtitle: "There's no wrong answer — understanding your style helps your partner meet you where you are.",
            options: [
                .init("direct_right_away", "Direct, right away",
                      "You value clarity and speed. Letting things sit feels worse than the awkward moment of saying it. Just make sure your tone matches your intention."),
                .init("after_i_ve_thought_it_through", "After I've thought it through",
                      "You process before you speak — which means you usually come in with clarity. Your partner might benefit from knowing you need time before talking."),
                .init("i_drop_hints_and_hope_they_notice", "I drop hints and hope they notice",
                      "You communicate indirectly, hoping they'll pick up on it. Worth asking: would you prefer they just asked you directly?"),
                .init("i_wait_until_it_builds_up", "I wait until it builds up",
                      "Patience has limits, and bottling things leads to bigger blow-ups. Small, early conversations are usually gentler for everyone."),
                .init("it_depends_how_serious_it_is", "It depends how serious it is",
                      "Context-driven — you're flexible and read the room. That's a real skill, as long as the serious stuff always gets said."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "com_listen",
            topic: .communication,
            question: "When your partner is upset, what do you naturally do?",
            subtitle: "How you respond by instinct — what you offer before thinking about what they need.",
            options: [
                .init("listen_without_interrupting", "Listen without interrupting",
                      "You make space. Being heard without someone jumping to solve it is often the most healing thing — and you provide that."),
                .init("try_to_fix_the_problem", "Try to fix the problem",
                      "Your instinct is to help practically. Just double-check they want solutions, not just someone to listen."),
                .init("give_them_space_to_breathe", "Give them space to breathe",
                      "You respect that some people need to settle before they can talk. That's emotionally mature — just communicate you're there when they're ready."),
                .init("offer_a_hug_first", "Offer a hug first",
                      "Physical comfort is your first language. Sometimes a hug says everything words can't — especially in the first moment."),
                .init("ask_what_they_need_from_me", "Ask what they need from me",
                      "This is underrated. Instead of assuming, you check in first. That's a genuinely thoughtful approach to support."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "com_apology",
            topic: .communication,
            question: "How do you prefer to receive an apology?",
            subtitle: "Apologies that miss the mark can feel worse than none at all — this matters.",
            options: [
                .init("sincere_words_said_directly_to_me", "Sincere words said directly to me",
                      "Eye contact, genuine words, no deflection — that's what lands for you. You need to feel the weight of it."),
                .init("a_thoughtful_gesture_with_the_words", "A thoughtful gesture with the words",
                      "Action alongside words proves it's real. Saying sorry while doing something kind shows they mean it."),
                .init("changed_behaviour_over_time_show_me", "Changed behaviour over time — show me",
                      "Talk is cheap. You believe in proof. This is fair — consistent change is the only real apology."),
                .init("quick_acknowledgement_and_move_on", "Quick acknowledgement and move on",
                      "You don't dwell. Acknowledge it, adjust, and move forward — dwelling makes it worse for you."),
                .init("a_letter_or_message_so_i_can_process_it", "A letter or message so I can process it alone",
                      "You need to read and re-read it, take it in on your own time. Written apologies feel more considered to you."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "com_check",
            topic: .communication,
            question: "How often do you like to have a real 'how are we doing?' conversation?",
            subtitle: "Relationship check-ins prevent small things from becoming big ones.",
            options: [
                .init("regularly_monthly_or_more", "Regularly — monthly or more",
                      "You're proactive about the relationship. Regular check-ins keep you connected and prevent things from festering."),
                .init("when_something_comes_up", "When something comes up",
                      "You're reactive rather than proactive — which works if you're both good at raising things when they happen."),
                .init("a_few_times_a_year_feels_right", "A few times a year feels right",
                      "Structured but not overwhelming. You like intentional moments without it feeling like therapy every week."),
                .init("rarely_i_d_rather_show_it_than_say_it", "Rarely — I'd rather show it than say it",
                      "You communicate through action more than words. Just make sure your partner feels secure — not everyone reads actions the same way."),
                .init("whenever_one_of_us_needs_it", "Whenever one of us needs it",
                      "Open-door policy. This works well when both partners are comfortable raising things without a formal invitation."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "com_phone",
            topic: .communication,
            question: "How do you feel about phone use when you're spending time together?",
            subtitle: "This is a surprisingly common source of friction in relationships.",
            options: [
                .init("phones_away_fully_present", "Phones away — fully present",
                      "Undivided attention is your standard for quality time. Scrolling while together feels dismissive to you."),
                .init("fine_to_use_but_not_constantly", "Fine to use but not constantly",
                      "Balance. You don't want to police it, but you notice when someone's only half-there."),
                .init("no_rules_just_use_common_sense", "No rules, just use common sense",
                      "You're relaxed about it. You trust both of you to read when it's appropriate."),
                .init("depends_completely_on_the_moment", "Depends completely on the moment",
                      "Contextual. A long dinner is different from watching TV together. You read the room."),
                .init("i_honestly_don_t_think_about_it", "I honestly don't think about it",
                      "It's not a tension point for you. Worth sharing with your partner in case it is for them."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Conflict

        .init(
            questionId: "conflict_style",
            topic: .conflict,
            question: "In a disagreement, which sounds most like you?",
            subtitle: "Most conflict issues aren't about who's right — they're about two different styles colliding.",
            options: [
                .init("i_want_to_talk_it_out_immediately", "I want to talk it out immediately",
                      "You'd rather address it head-on than let it sit. Be mindful — your partner might need space before they can engage productively."),
                .init("i_need_time_alone_to_cool_down_first", "I need time alone to cool down first",
                      "Distance helps you regulate before you respond. Let your partner know you're not shutting them out — you're coming back."),
                .init("i_look_for_the_compromise_right_away", "I look for the compromise right away",
                      "Resolution-focused. You see the relationship as bigger than the disagreement. That's a real strength."),
                .init("i_tend_to_avoid_conflict_where_possible", "I tend to avoid conflict where possible",
                      "Peace-keeping is valuable, but avoidance can allow resentment to build quietly. Some conversations are worth having."),
                .init("i_go_quiet_until_i_ve_figured_out_what_i", "I go quiet until I've figured out what I want to say",
                      "Thoughtful but inward. Your partner might read your silence as punishment — a quick 'I need to think' goes a long way."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "conflict_makeup",
            topic: .conflict,
            question: "After a fight, how do you like to make up?",
            subtitle: "The repair matters as much as the argument itself.",
            options: [
                .init("a_real_conversation_where_we_both_feel_heard", "A real conversation where we both feel heard",
                      "You need closure through words. The fight isn't done until both sides have been acknowledged."),
                .init("a_hug_no_words_needed", "A hug — no words needed",
                      "Physical reconnection says more than a post-mortem. For you, touch closes the loop."),
                .init("do_something_fun_together_and_reset", "Do something fun together and reset",
                      "Moving forward together, doing something light — that's how you reset the energy between you."),
                .init("give_it_time_and_let_it_settle_naturally", "Give it time and let it settle naturally",
                      "You don't force it. Time does the work, and you let the relationship find its own equilibrium again."),
                .init("a_small_gesture_coffee_a_note_something", "A small gesture — coffee, a note, something thoughtful",
                      "Action over words. You say 'I'm sorry' by showing it — and you receive apologies the same way."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "conflict_trigger",
            topic: .conflict,
            question: "What's most likely to get under your skin in a relationship?",
            subtitle: "Knowing your triggers means they're less likely to catch you off guard.",
            options: [
                .init("feeling_unheard_or_dismissed", "Feeling unheard or dismissed",
                      "You need to know your voice matters. When someone talks over you or brushes you off, it hits deep."),
                .init("broken_promises_even_small_ones", "Broken promises, even small ones",
                      "Reliability is your baseline for trust. Small broken commitments add up and erode confidence."),
                .init("passive_aggression_instead_of_honesty", "Passive aggression instead of honesty",
                      "Say it or don't — but don't say it sideways. You'd rather hear something hard than feel tension you can't address."),
                .init("not_getting_enough_quality_time", "Not getting enough quality time",
                      "Togetherness isn't optional for you — it's how you stay connected. Without it, you start to feel like strangers."),
                .init("feeling_like_i_always_have_to_initiate", "Feeling like I always have to initiate",
                      "Effort should go both ways. When it feels one-sided, you start questioning where you stand."),
                .init("criticism_in_front_of_others", "Criticism in front of others",
                      "Private matters stay private. Being called out publicly feels like a fundamental breach of respect."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Finance

        .init(
            questionId: "fin_style",
            topic: .finance,
            question: "How would you describe your natural approach to spending?",
            subtitle: "Neither extreme is wrong — but knowing where you sit helps you plan as a team.",
            options: [
                .init("conservative_i_save_first_spend_what_s_left", "Conservative — I save first, spend what's left",
                      "Security gives you peace of mind. You may need to loosen up around a partner who values experiences — and help them understand why savings matter to you."),
                .init("balanced_i_budget_but_allow_for_flexibility", "Balanced — I budget but allow for flexibility",
                      "You're pragmatic and adaptable. You can work with most money personalities, which is a strength."),
                .init("generous_with_experiences_money_is_for", "Generous with experiences — money is for living",
                      "You prioritise memories and moments. Just make sure there's enough runway for emergencies — which a budgeting partner can help with."),
                .init("spontaneous_i_spend_on_what_feels_right_in", "Spontaneous — I spend on what feels right in the moment",
                      "You live in the present. A shared budget might feel restrictive at first, but it can actually give you more freedom long-term."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "fin_goal",
            topic: .finance,
            question: "What's a money goal you'd genuinely enjoy working toward together?",
            subtitle: "A shared financial goal is one of the strongest bonding exercises a couple can do.",
            options: [
                .init("save_for_a_big_trip_or_experience", "Save for a big trip or experience",
                      "Experiences over things — you want memories you'll both carry forever. A trip goal keeps you both motivated and excited."),
                .init("buy_a_home_or_move_somewhere_better", "Buy a home or move somewhere better",
                      "Stability and roots. This is a long-term signal — you're thinking about a shared future, not just right now."),
                .init("build_an_investment_portfolio_for_the_future", "Build an investment portfolio for the future",
                      "You're playing the long game. Future-you will thank both of you."),
                .init("create_a_comfortable_emergency_fund", "Create a comfortable emergency fund",
                      "Safety net first. This is one of the most loving things a couple can do for each other — removing financial anxiety."),
                .init("pay_off_debt_together_and_start_fresh", "Pay off debt together and start fresh",
                      "Starting from a clean slate. There's real intimacy in tackling someone's financial baggage together."),
                .init("splurge_on_something_we_ve_always_wanted", "Splurge on something we've always wanted",
                      "Permission to enjoy now. Sometimes the goal is just the thing you've been putting off — and doing it together makes it better."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "fin_split",
            topic: .finance,
            question: "How do you think couples should handle money?",
            subtitle: "There's no universally right answer — but alignment here prevents serious friction.",
            options: [
                .init("fully_combined_one_pot_full_transparency", "Fully combined — one pot, full transparency",
                      "Total partnership. This builds deep trust and makes planning easy — it also requires real vulnerability about spending."),
                .init("mostly_combined_with_some_personal_spending", "Mostly combined, with some personal spending money",
                      "Practical balance. Shared responsibility plus personal autonomy. Most couples find this sustainable long-term."),
                .init("mostly_separate_split_shared_costs_fairly", "Mostly separate, split shared costs fairly",
                      "Independence is important to you. You contribute equally but maintain autonomy — worth agreeing on what 'fair' means."),
                .init("fully_separate_independent_finances_clear", "Fully separate — independent finances, clear shared agreements",
                      "You value financial independence. This works well with clear agreements on how shared expenses are handled."),
                .init("still_figuring_this_out", "Still figuring this out",
                      "Honest answer. Money conversations are uncomfortable but necessary — starting with how you each *feel* about it is a good first step."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "fin_splurge",
            topic: .finance,
            question: "If you had an extra $1,000 right now, you'd…",
            subtitle: "This reveals your natural financial instinct — not what you 'should' do.",
            options: [
                .init("put_it_straight_into_savings", "Put it straight into savings",
                      "Future-focused by instinct. You feel safer with a bigger cushion. That's valuable — especially if your partner leans toward spending."),
                .init("invest_it", "Invest it",
                      "You think in terms of growth. Money sitting still makes you restless. A good counterbalance to a partner who prioritises security."),
                .init("plan_a_weekend_trip_or_experience", "Plan a weekend trip or experience",
                      "Experiences energise you and you'd rather spend on memories than things. A trip becomes a shared story."),
                .init("buy_something_i_ve_wanted_for_a_while", "Buy something I've wanted for a while",
                      "You have a list, and you're patient. This isn't impulse — it's rewarding yourself deliberately."),
                .init("split_it_some_savings_some_fun", "Split it — some savings, some fun",
                      "Balanced by nature. You probably navigate money conversations relatively easily with most partners."),
                .init("donate_part_of_it", "Donate part of it",
                      "Generosity is a core value. You think beyond yourself — that's worth knowing for a partner who shares (or doesn't share) that instinct."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Lifestyle

        .init(
            questionId: "life_weekend",
            topic: .lifestyle,
            question: "Your perfect Sunday looks like…",
            subtitle: "How people recharge tells you a lot about what they need week to week.",
            options: [
                .init("slow_morning_nowhere_to_be", "Slow morning, nowhere to be",
                      "You need decompression time. A rushed Sunday feels like no break at all. Mornings at your own pace refuel you."),
                .init("out_exploring_somewhere_new", "Out exploring somewhere new",
                      "Curiosity and novelty energise you. Staying still too long makes you feel restless — you need the world outside."),
                .init("catching_up_with_friends_or_family", "Catching up with friends or family",
                      "Social connection is restorative for you. People give you energy, not drain it. Sunday is for the people you love."),
                .init("working_on_a_project_i_care_about", "Working on a project I care about",
                      "Flow state is your kind of weekend. Productive rest — doing something meaningful even when you don't have to — is your thing."),
                .init("staying_in_bed_longer_than_i_should", "Staying in bed longer than I should",
                      "Rest without guilt. You probably don't get enough of it during the week, and Sunday is where you catch up on yourself."),
                .init("doing_nothing_together_just_being", "Doing nothing together — just being",
                      "Comfortable silence and no agenda. That kind of ease with someone is a real signal of closeness."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "life_energy",
            topic: .lifestyle,
            question: "When do you feel most alive?",
            subtitle: "Knowing when you're at your best matters for planning shared time — and giving each other space.",
            options: [
                .init("early_morning_i_m_at_my_peak", "Early morning — I'm at my peak",
                      "Morning person through and through. You probably make better decisions, have deeper conversations, and feel most creative before noon."),
                .init("late_night_i_come_alive_after_dark", "Late night — I come alive after dark",
                      "Your best thinking, energy, and creativity happens when everyone else is winding down. Mismatched schedules with an early bird can create real friction."),
                .init("middle_of_the_day_peak_hours", "Middle of the day — peak hours",
                      "Your rhythm is conventional — which actually works well in most shared-life contexts."),
                .init("depends_entirely_on_the_day", "Depends entirely on the day",
                      "You're adaptive and mood-driven. That flexibility is a strength as long as you can communicate when you're 'off'."),
                .init("honestly_whenever_i_m_with_the_right_people", "Honestly, whenever I'm with the right people",
                      "Connection is your energy source, not time of day. The quality of company matters more than the clock to you."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "life_social",
            topic: .lifestyle,
            question: "How do you feel about socialising as a couple?",
            subtitle: "Couple time vs social time is one of the most negotiated parts of a relationship.",
            options: [
                .init("love_it_the_more_plans_the_better", "Love it — the more plans the better",
                      "Socially energised. You probably have a full calendar and feel most alive around people. A more introverted partner might need you to protect some downtime."),
                .init("enjoy_it_but_i_need_couple_time_too", "Enjoy it, but I need couple time too",
                      "Balanced. You can do both — but you're also deliberate about protecting the relationship bubble."),
                .init("prefer_small_group_or_one_on_one_settings", "Prefer small group or one-on-one settings",
                      "Quality over quantity. Big group dynamics can feel draining — you'd rather go deep with fewer people."),
                .init("mostly_just_the_two_of_us_please", "Mostly just the two of us, please",
                      "The relationship is your sanctuary. Too many external commitments can feel like they dilute the intimacy you value."),
                .init("it_depends_on_my_mood_and_energy_that_week", "It depends on my mood and energy that week",
                      "Context-driven and honest. As long as you can communicate where you're at, this flexibility works well."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "life_cleanliness",
            topic: .lifestyle,
            question: "How important is a tidy home to you?",
            subtitle: "Cleanliness expectations are quietly one of the biggest lived-in relationship flashpoints.",
            options: [
                .init("very_mess_genuinely_stresses_me_out", "Very — mess genuinely stresses me out",
                      "Your environment directly affects your mental state. A tidy space isn't aesthetic preference — it's a genuine need. Worth communicating early."),
                .init("i_prefer_tidy_but_i_m_not_obsessive", "I prefer tidy but I'm not obsessive",
                      "Middle ground. You appreciate order but you're not going to fight about a dish in the sink."),
                .init("lived_in_is_comfortable_i_like_it_homely", "Lived-in is comfortable — I like it homely",
                      "Warmth over perfection. Home should feel comfortable and real — not a showroom. A partner who needs perfect tidiness might find this friction."),
                .init("i_genuinely_don_t_notice_unless_it_s_extreme", "I genuinely don't notice unless it's extreme",
                      "Low sensitivity to clutter. You'll want to actively meet a tidier partner's needs — because you genuinely won't see what bothers them."),
                .init("i_care_in_bursts_big_clean_every_so_often", "I care in bursts — big clean every so often is fine",
                      "Periodic effort over daily maintenance. As long as expectations are aligned, this works fine."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "life_morning",
            topic: .lifestyle,
            question: "What does your ideal morning routine look like?",
            subtitle: "Morning compatibility is surprisingly important when you share a space.",
            options: [
                .init("quiet_and_slow_no_rushing", "Quiet and slow — no rushing",
                      "Mornings set the tone for your whole day. You need a gentle start — a rushed or chaotic morning throws you off."),
                .init("productive_from_the_moment_i_wake", "Productive from the moment I wake",
                      "You hit the ground running. Mornings are your window for your best work or thinking. Protect that time."),
                .init("coffee_first_everything_else_negotiable", "Coffee first, everything else negotiable",
                      "Relatable and honest. You need that first ritual before you're functional. Knowing this helps a partner not take the morning grumpiness personally."),
                .init("as_short_as_possible_i_m_not_a_morning", "As short as possible — I'm not a morning person",
                      "Mornings are something to survive, not enjoy. You probably thrive later in the day — and that's fine, just worth knowing."),
                .init("it_changes_i_go_with_how_i_feel", "It changes, I go with how I feel",
                      "Flexible and mood-driven. You don't need routine to feel grounded — or you haven't found the right one yet."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "life_night",
            topic: .lifestyle,
            question: "What helps you wind down at night?",
            subtitle: "Evening routines matter a lot when you share a bed and a home.",
            options: [
                .init("reading_until_i_fall_asleep", "Reading until I fall asleep",
                      "Screens off, book open. Reading is protective — it signals to your brain that the day is over. A quiet, compatible wind-down for most partners."),
                .init("watching_something_together_or_alone", "Watching something together or alone",
                      "Passive relaxation works for you. This can be a great shared couple ritual — or totally individual, depending on the show."),
                .init("a_shower_or_bath_ritual_reset", "A shower or bath — ritual reset",
                      "Physical transition from day to night. Washing the day off is literal for you. A very grounding habit."),
                .init("talking_to_my_partner_the_day_in_review", "Talking to my partner — the day in review",
                      "Connection is how you close the loop on the day. This is a beautiful couple ritual — make sure your partner knows how much it means."),
                .init("scrolling_my_phone_not_proud_of_it", "Scrolling my phone (not proud of it)",
                      "Honest. Screen time before bed disrupts sleep quality — but many people do it. Worth working on together."),
                .init("exercise_or_a_walk_in_the_evening", "Exercise or a walk in the evening",
                      "Evening movement energises you before it calms you down. You sleep better having moved. Some partners find this incompatible — worth discussing."),
                .init("i_just_go_to_sleep_no_routine_needed", "I just go to sleep — no routine needed",
                      "Efficient. You don't need rituals to decompress — or you're usually exhausted enough not to need them."),
            ],
            allowsMultiple: true
        ),

        // MARK: - Intimacy

        .init(
            questionId: "intimacy_checkin",
            topic: .intimacy,
            question: "What makes you feel closest to your partner?",
            subtitle: "Closeness isn't just physical — it's created in different ways for different people.",
            options: [
                .init("eye_contact_and_real_presence", "Eye contact and real presence",
                      "Being truly seen — not just looked at. Full attention, no distractions, just them focused on you. That's intimacy for you."),
                .init("a_long_honest_conversation", "A long, honest conversation",
                      "Depth creates closeness. The more honestly someone talks to you, the closer you feel. Surface conversations leave you distant."),
                .init("comfortable_silence_no_need_to_fill_it", "Comfortable silence — no need to fill it",
                      "The ability to be quiet together without it being awkward is a real sign of ease and intimacy. You value that comfort."),
                .init("physical_closeness_without_needing_a_reason", "Physical closeness without needing a reason",
                      "Touch as connection — not necessarily sexual. Just being near each other, body language saying 'I'm here'."),
                .init("being_completely_silly_and_stupid_together", "Being completely silly and stupid together",
                      "Laughter and playfulness are intimacy too. When you can be goofy with someone, the guard is down — that's vulnerability."),
                .init("doing_something_meaningful_side_by_side", "Doing something meaningful side by side",
                      "Shared purpose builds closeness. Cooking, building, creating — doing something that matters to you both."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "intimacy_spark",
            topic: .intimacy,
            question: "What keeps the spark alive for you long-term?",
            subtitle: "The spark doesn't have to fade — but what maintains it is different for everyone.",
            options: [
                .init("consistent_date_nights_and_intentional", "Consistent date nights and intentional effort",
                      "Ritual and effort. You believe the spark is maintained through consistent investment, not just left to chance."),
                .init("trying_new_things_and_breaking_routine", "Trying new things and breaking routine",
                      "Novelty is the fuel. New experiences together keep you from going stale. You need to keep exploring as a couple."),
                .init("small_daily_gestures_that_say_i_m_thinking", "Small daily gestures that say 'I'm thinking of you'",
                      "The everyday moments matter most. A text, a coffee made the way you like it — these add up to a relationship that feels alive."),
                .init("honest_conversations_including_the", "Honest conversations, including the uncomfortable ones",
                      "Depth over comfort. You believe real closeness comes from talking about things other couples avoid."),
                .init("missing_each_other_time_apart_makes_the", "Missing each other — time apart makes the heart grow",
                      "Absence creates appreciation. You need space to miss your partner — and that longing keeps things fresh."),
                .init("playfulness_not_taking_everything_too", "Playfulness — not taking everything too seriously",
                      "Lightness is underrated in long-term relationships. Couples who laugh together tend to last."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "intimacy_affection",
            topic: .intimacy,
            question: "How do you show affection most naturally?",
            subtitle: "We often love others the way we want to be loved — not always how they receive it best.",
            options: [
                .init("saying_it_out_loud_i_love_you_compliments", "Saying it out loud — 'I love you', compliments",
                      "Words come naturally to you as expressions of love. Worth checking whether your partner receives verbal affirmation as easily as you give it."),
                .init("doing_things_for_them_without_being_asked", "Doing things for them without being asked",
                      "Acts of service is your natural expression. You show love by making their life easier — a beautiful but often unnoticed love language."),
                .init("physical_closeness_touches_hugs_sitting", "Physical closeness — touches, hugs, sitting close",
                      "Touch is instinctive for you. You reach out physically when you care — and you probably notice when that diminishes."),
                .init("giving_them_my_full_undivided_time", "Giving them my full, undivided time",
                      "Presence is your gift. When you care about someone, you show it by actually being there — fully, not halfway."),
                .init("little_surprise_gestures_that_show_i", "Little surprise gestures that show I remembered something",
                      "Attentiveness is your love language. You prove you've been listening by acting on small details — that's quietly powerful."),
            ],
            allowsMultiple: false
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
            options: [
                .init("indie_alternative", "Indie / alternative"),
                .init("pop", "Pop"),
                .init("r_b_soul", "R&B / soul"),
                .init("hip_hop", "Hip-hop"),
                .init("classical_instrumental", "Classical / instrumental"),
                .init("lo_fi_chill", "Lo-fi / chill"),
                .init("rock", "Rock"),
                .init("electronic_edm", "Electronic / EDM"),
                .init("jazz", "Jazz"),
                .init("k_pop", "K-Pop"),
                .init("country", "Country"),
                .init("acoustic_singer_songwriter", "Acoustic / singer-songwriter"),
                .init("reggae_afrobeats", "Reggae / Afrobeats"),
                .init("latin_salsa", "Latin / salsa"),
                .init("metal_punk", "Metal / punk"),
            ],
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
            options: [
                .init("podcasts_or_audiobooks", "Podcasts or audiobooks",
                      "You use transit time to learn or explore stories. That's a productive, curious mindset."),
                .init("loud_upbeat_music_i_sing_along", "Loud upbeat music — I sing along",
                      "Maximum energy, maximum volume. You probably arrive in a better mood than when you left."),
                .init("chill_background_music", "Chill background music",
                      "Ambient and calming. You're not trying to perform — you just want a pleasant backdrop."),
                .init("whatever_shuffle_gives_me", "Whatever shuffle gives me",
                      "Spontaneous and unbothered. You can enjoy almost anything. Low-maintenance taste."),
                .init("silence_i_like_to_think", "Silence — I like to think",
                      "You process in quiet. Commute time is thinking time. Or decompression time. Either way, silence is chosen, not default."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Sport & Fitness

        .init(
            questionId: "sport_together",
            topic: .sport,
            question: "What active things could you see us doing together?",
            subtitle: "Even if you're not very active now — what would you actually try?",
            options: [
                .init("hiking_or_nature_walks", "Hiking or nature walks"),
                .init("running_or_jogging", "Running or jogging"),
                .init("yoga_or_stretching_together", "Yoga or stretching together"),
                .init("swimming", "Swimming"),
                .init("cycling", "Cycling"),
                .init("tennis_or_badminton", "Tennis or badminton"),
                .init("going_to_the_gym", "Going to the gym"),
                .init("dancing", "Dancing"),
                .init("rock_climbing", "Rock climbing"),
                .init("martial_arts_or_kickboxing", "Martial arts or kickboxing"),
                .init("a_team_sport", "A team sport"),
                .init("skiing_or_snowboarding", "Skiing or snowboarding"),
                .init("surfing", "Surfing"),
                .init("kayaking_or_paddleboarding", "Kayaking or paddleboarding"),
            ],
            allowsMultiple: true
        ),

        .init(
            questionId: "sport_habit",
            topic: .sport,
            question: "How do you honestly feel about exercise right now?",
            subtitle: "No judgment — where you are with this affects your energy, mood, and schedules.",
            options: [
                .init("it_s_a_non_negotiable_part_of_my_day", "It's a non-negotiable part of my day",
                      "Fitness is a core identity piece for you. A partner who doesn't value it at all might create friction — or become your motivation."),
                .init("i_do_it_regularly_but_inconsistently", "I do it regularly but inconsistently",
                      "You have the intention and the habit, life just gets in the way. A partner who makes it social can help a lot."),
                .init("i_prefer_low_key_activity_walking_stretching", "I prefer low-key activity — walking, stretching",
                      "Movement without intensity. You value feeling good over performance. Great for someone who can match that pace."),
                .init("i_want_to_be_more_active_but_haven_t_made", "I want to be more active but haven't made it stick",
                      "Honest. A supportive partner who makes activity social and fun — rather than a chore — could be the missing piece."),
                .init("it_s_really_not_my_thing", "It's really not my thing",
                      "That's valid. Just worth knowing if your partner finds it central to their identity or mental health."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Travel

        .init(
            questionId: "travel_style",
            topic: .travel,
            question: "Your ideal trip leans toward…",
            subtitle: "Travel compatibility can make or break a holiday — this is worth knowing early.",
            options: [
                .init("relaxed_beach_and_nature_recharge_mode", "Relaxed beach and nature — recharge mode",
                      "Holiday means decompression. You want calm, warmth, and nothing scheduled. A packed itinerary is someone else's trip."),
                .init("city_breaks_culture_food_architecture", "City breaks — culture, food, architecture",
                      "You absorb a place through its streets, museums, and restaurants. Cities give you stimulation and story material."),
                .init("adventure_and_outdoors_challenging_ourselves", "Adventure and outdoors — challenging ourselves",
                      "Travel as experience and challenge. You want to come back having done something you couldn't do at home."),
                .init("food_focused_eating_our_way_through_a_place", "Food-focused — eating our way through a place",
                      "The table is where culture actually lives. You book restaurants before flights and that is correct."),
                .init("a_long_roadtrip_with_no_fixed_itinerary", "A long roadtrip with no fixed itinerary",
                      "Freedom and spontaneity — the plan is to have no plan. The best moments are the unplanned ones."),
                .init("cultural_immersion_local_experiences_off", "Cultural immersion — local experiences, off the tourist trail",
                      "Depth over tourism. You want to understand a place, not just photograph it."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "travel_pace",
            topic: .travel,
            question: "How do you like to travel?",
            subtitle: "Travel pace is one of the most underestimated sources of couple conflict on holiday.",
            options: [
                .init("every_day_planned_in_detail_i_research", "Every day planned in detail — I research everything",
                      "Planning is how you prevent disappointment and maximise the trip. A spontaneous partner might find this rigid — but you find their lack of planning stressful."),
                .init("loose_structure_key_things_booked_rest", "Loose structure — key things booked, rest flexible",
                      "Best of both worlds. You have a safety net but room to breathe. Most people travel happily with you."),
                .init("mostly_spontaneous_with_a_general_direction", "Mostly spontaneous with a general direction",
                      "Adventure over agenda. You trust that it'll work out — and it usually does. A planner partner might need some reassurance."),
                .init("let_my_partner_lead_i_m_easy", "Let my partner lead — I'm easy",
                      "Low-maintenance and adaptable. Just make sure you actually speak up when something matters to you — being 'easy' can leave you resentful."),
                .init("whatever_works_i_adapt", "Whatever works — I adapt",
                      "Genuinely flexible. You probably won't cause holiday friction — you're the one who smooths it over."),
            ],
            allowsMultiple: false
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
            options: [
                .init("budget_traveller_maximise_days_minimise_cost", "Budget traveller — maximise days, minimise cost",
                      "More trips, less per trip. You want volume of experience. Hostels and street food don't scare you."),
                .init("mid_range_comfortable_but_not_extravagant", "Mid-range — comfortable but not extravagant",
                      "Value-driven. You want a good bed and a good meal without feeling reckless. That's most people's sweet spot."),
                .init("i_d_rather_go_less_often_and_do_it_properly", "I'd rather go less often and do it properly",
                      "Quality over quantity. One exceptional trip a year beats four mediocre ones."),
                .init("full_luxury_when_possible_it_s_a_treat", "Full luxury when possible — it's a treat",
                      "You save for indulgence. Holiday is for doing things you can't do at home — including the nice hotel."),
                .init("depends_entirely_on_the_trip", "Depends entirely on the trip",
                      "Context matters. A weekend city break vs. a honeymoon deserve different budgets. Pragmatic."),
            ],
            allowsMultiple: false
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
            options: [
                .init("cook_something_new_at_home_together", "Cook something new at home together",
                      "Collaboration as romance. The kitchen becomes its own kind of quality time — and you get a meal at the end."),
                .init("our_tried_and_true_favourite_restaurant", "Our tried-and-true favourite restaurant",
                      "Comfort and ritual. You don't need the exciting — you need the reliable. Familiarity is its own kind of joy."),
                .init("try_somewhere_brand_new_surprise_me", "Try somewhere brand new — surprise me",
                      "Novelty is exciting to you even in dining. You enjoy the discovery — and you probably eat more adventurously too."),
                .init("takeaway_on_the_couch_no_effort_required", "Takeaway on the couch — no effort required",
                      "Sometimes the best date is the one where no one has to put on shoes. Comfort and ease over ambiance."),
                .init("street_food_markets_or_something_casual_and", "Street food, markets, or something casual and fun",
                      "Atmosphere over formality. You want the energy of being out without the formality of a sit-down."),
                .init("a_fancy_tasting_menu_or_special_occasion", "A fancy tasting menu or special occasion restaurant",
                      "You appreciate the craft. A great meal as an experience in itself — worth saving for."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "food_diet",
            topic: .food,
            question: "How would you describe your eating habits?",
            subtitle: "This affects shared meals, grocery shopping, and dining out — worth knowing.",
            options: [
                .init("i_eat_everything_no_restrictions", "I eat everything — no restrictions",
                      "Maximum compatibility. You're easy to feed and easy to take out. You probably have an adventurous palate too."),
                .init("mostly_healthy_with_regular_treats", "Mostly healthy with regular treats",
                      "Balanced and realistic. You're not extreme — you enjoy food but you also take care of yourself."),
                .init("plant_based_or_vegetarian", "Plant-based or vegetarian",
                      "Worth knowing early — it shapes where you eat, what you cook, and potentially what your partner is willing to adapt to."),
                .init("vegan", "Vegan",
                      "A more committed choice that affects many shared meals and dining decisions. Alignment here is genuinely important."),
                .init("following_a_specific_diet_for_health_or", "Following a specific diet for health or fitness goals",
                      "Intentional eater. Your goals drive your food choices. Helpful for a partner to understand — especially around shared cooking."),
                .init("pretty_picky_i_have_a_very_specific_list_of", "Pretty picky — I have a very specific list of things I like",
                      "Honest and self-aware. A partner who loves food variety will need to know this upfront — and that's fine."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "food_cook",
            topic: .food,
            question: "What's your relationship with cooking?",
            subtitle: "In shared-life relationships, this ends up mattering a lot.",
            options: [
                .init("i_love_it_and_cook_regularly", "I love it and cook regularly",
                      "Cooking is a love language in its own right. A partner who appreciates a home-cooked meal is your ideal audience."),
                .init("i_can_cook_but_prefer_when_someone_else_does", "I can cook but prefer when someone else does",
                      "Capable but unmotivated alone. The right person in the kitchen might change this."),
                .init("i_m_learning_and_actually_enjoying_it", "I'm learning and actually enjoying it",
                      "A growing skill you're investing in. This is a great shared activity — especially if your partner can teach you."),
                .init("i_ll_do_it_for_my_partner_but_not_for_myself", "I'll do it for my partner but not for myself",
                      "Caring through action. You cook as an act of love, not habit. That's meaningful."),
                .init("i_m_genuinely_a_disaster_in_the_kitchen", "I'm genuinely a disaster in the kitchen",
                      "Honest. A cooking partner who teaches or takes over is genuinely appreciated — and you probably clean up in return."),
                .init("i_don_t_cook_delivery_and_restaurants_are", "I don't cook — delivery and restaurants are fine",
                      "Practical and unapologetic. Just worth knowing if your partner values home cooking or wants the kitchen to be a shared space."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Family

        .init(
            questionId: "family_kids",
            topic: .family,
            question: "How do you feel about having kids in the future?",
            subtitle: "This is one of the most important alignment questions in any serious relationship.",
            options: [
                .init("yes_i_want_kids_it_s_a_priority_for_me", "Yes — I want kids, it's a priority for me",
                      "A clear yes. This isn't negotiable for you — and that's completely valid. Make sure a partner knows this early."),
                .init("open_to_it_i_d_consider_it_with_the_right", "Open to it — I'd consider it with the right person",
                      "Flexible but not indifferent. You're not actively wanting or avoiding — you're open to what the relationship calls for."),
                .init("not_sure_yet_i_m_still_working_through_this", "Not sure yet — I'm still working through this",
                      "Honest uncertainty. This often changes with age, circumstances, and the right partner. Worth revisiting periodically."),
                .init("probably_not_leaning_toward_no", "Probably not — leaning toward no",
                      "You're moving toward no, even if you haven't fully committed to that position yet. Worth being transparent with a partner who feels strongly."),
                .init("definitely_no_this_is_a_firm_decision_for_me", "Definitely no — this is a firm decision for me",
                      "A clear no. Just as valid as a clear yes. Mismatch on this isn't something love usually resolves."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "family_closeness",
            topic: .family,
            question: "How close are you with your own family?",
            subtitle: "Family dynamics shape expectations in relationships — more than most people realise.",
            options: [
                .init("very_close_we_talk_all_the_time_and_see", "Very close — we talk all the time and see each other often",
                      "Family is central to your life. A partner will need to understand and respect that — and probably show up for family things regularly."),
                .init("close_but_with_healthy_boundaries", "Close, but with healthy boundaries",
                      "You value family without losing yourself in it. You've probably done some work on understanding what healthy closeness looks like."),
                .init("mixed_some_family_i_m_close_to_others_i_m", "Mixed — some family I'm close to, others I'm not",
                      "Real and nuanced. Most people's family relationships are complicated — you're just honest about it."),
                .init("not_very_close_we_have_a_cordial_but", "Not very close — we have a cordial but distant relationship",
                      "Distance by choice or circumstance. Worth understanding whether that's peaceful or painful — it affects how you approach 'family' as a couple."),
                .init("it_s_complicated_there_s_history_here", "It's complicated — there's history here",
                      "There's depth to this. A supportive partner needs to know what they're stepping into — and that you may need space or help navigating it."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "family_inlaw",
            topic: .family,
            question: "How do you want to handle each other's families as a couple?",
            subtitle: "This becomes very real once you're living together or getting serious.",
            options: [
                .init("fully_embrace_them_they_re_family_too", "Fully embrace them — they're family too",
                      "You want full integration. In-laws are your family too — you invest in those relationships genuinely."),
                .init("warm_and_present_but_with_clear_boundaries", "Warm and present, but with clear boundaries",
                      "Healthy engagement. You show up, you care, but you also protect the couple's space. That's sustainable."),
                .init("respectful_and_polite_but_we_keep_things", "Respectful and polite, but we keep things mostly separate",
                      "Friendly but separate. You can be kind without being entangled. Worth making sure that's mutual."),
                .init("we_figure_it_out_together_as_situations", "We figure it out together as situations arise",
                      "Adaptive and collaborative. You don't set rigid rules — you navigate it as a team. That requires trust."),
                .init("depends_entirely_on_the_family", "Depends entirely on the family",
                      "Realistic. Different families call for different approaches. What matters is that you're both on the same page."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "family_pets",
            topic: .family,
            question: "How do you feel about pets?",
            subtitle: "Pets are a lifestyle choice that affects shared living in big ways.",
            options: [
                .init("i_have_one_have_had_one_and_love_it", "I have one / have had one and love it",
                      "Pets are part of your life and any future living situation. A partner who doesn't like animals will have a harder time."),
                .init("i_d_love_to_have_a_pet_eventually", "I'd love to have a pet eventually",
                      "It's on your list. Worth aligning timing and who takes on what responsibility."),
                .init("love_other_people_s_pets_not_ready_to_own", "Love other people's pets, not ready to own one",
                      "You like animals without wanting the full commitment right now. That might change — or it might not."),
                .init("not_interested_in_having_pets", "Not interested in having pets",
                      "A clear position. Nothing wrong with it — but worth knowing if your partner is deeply attached to the idea."),
                .init("allergic_or_can_t_have_them_for_practical", "Allergic or can't have them for practical reasons",
                      "A hard limitation. If your partner has or wants a pet, this is a genuine compatibility conversation."),
                .init("open_if_it_matters_to_my_partner", "Open if it matters to my partner",
                      "Accommodating and willing. Just make sure you genuinely mean it — pets are a long commitment."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Career

        .init(
            questionId: "career_balance",
            topic: .career,
            question: "How do you want work to fit into your life?",
            subtitle: "Career ambition shapes schedules, energy levels, and what you expect from home.",
            options: [
                .init("work_hard_play_hard_i_give_it_everything", "Work hard, play hard — I give it everything",
                      "High effort, high reward. You probably have big goals and you're willing to sacrifice for them. A partner needs to be okay with that."),
                .init("steady_and_sustainable_life_exists_outside", "Steady and sustainable — life exists outside of work",
                      "Work is a means, not the point. You protect your evenings and weekends. That's a mature, healthy boundary."),
                .init("my_work_is_my_passion_it_doesn_t_feel_like", "My work is my passion — it doesn't feel like work",
                      "The lucky ones. Intrinsic motivation means you'll work hard without it feeling like sacrifice — but partners sometimes feel second-place to a passion."),
                .init("flexible_and_remote_location_freedom_matters", "Flexible and remote — location freedom matters",
                      "Lifestyle design. You want work that fits around your life, not the other way around. Alignment with a partner's location and schedule matters."),
                .init("i_m_in_a_phase_of_building_more_now_less", "I'm in a phase of building — more now, less later",
                      "Temporary intensity with a plan. Knowing this is a phase, not a permanent identity, helps a partner understand the sacrifice."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "career_ambition",
            topic: .career,
            question: "How ambitious are you about your career right now?",
            subtitle: "Ambition mismatches aren't dealbreakers, but they need to be talked about.",
            options: [
                .init("very_it_s_one_of_my_top_priorities", "Very — it's one of my top priorities",
                      "Career success is core to your identity. A partner needs to be your biggest cheerleader — and accept that it costs time."),
                .init("moderately_i_care_but_life_is_bigger_than", "Moderately — I care, but life is bigger than my job",
                      "Balanced. You have professional pride without losing yourself in it. You're probably easy to be in a relationship with around this."),
                .init("career_is_a_means_to_an_end_it_funds_the", "Career is a means to an end — it funds the life I want",
                      "Pragmatic. Your real life happens outside of work. The job serves the vision."),
                .init("i_m_still_figuring_out_what_i_want_to_do", "I'm still figuring out what I want to do",
                      "Honest uncertainty. That's okay — especially if you're in a transition phase. A supportive partner can be an anchor."),
                .init("i_m_actively_making_a_change_or_transition", "I'm actively making a change or transition",
                      "A period of flux and possibility. Your partner needs to know this is coming — in terms of income, time, and emotional bandwidth."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "career_stress",
            topic: .career,
            question: "When work is stressful, what do you need from your partner?",
            subtitle: "Work stress is inevitable — knowing how to support each other makes a real difference.",
            options: [
                .init("just_listen_i_don_t_want_solutions", "Just listen — I don't want solutions",
                      "You need to vent, not be fixed. Letting your partner know this prevents the frustrating 'yes but have you tried…' response."),
                .init("distract_me_with_something_fun_or_light", "Distract me with something fun or light",
                      "Escape is your recovery mechanism. Getting out of your head with something enjoyable is more restorative than talking it through."),
                .init("give_me_space_to_decompress_alone_first", "Give me space to decompress alone first",
                      "You need to process alone before you can be present. Let your partner know you're not withdrawing — you're coming back better."),
                .init("practical_help_pick_up_some_slack_at_home", "Practical help — pick up some slack at home",
                      "When you're overwhelmed at work, reducing the home pressure means everything. Tangible support over emotional support."),
                .init("encouragement_and_belief_that_i_ll_get", "Encouragement and belief that I'll get through it",
                      "You need your partner in your corner, not just beside you. Confidence and faith from them refuels yours."),
                .init("a_reality_check_tell_me_it_ll_be_okay", "A reality check — tell me it'll be okay",
                      "You spiral a little and you know it. You need someone to gently ground you in perspective."),
            ],
            allowsMultiple: false
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
            options: [
                .init("therapy_or_counselling", "Therapy or counselling",
                      "You invest in your mental health seriously. That takes courage and self-awareness — and it makes you a more self-aware partner."),
                .init("regular_exercise", "Regular exercise",
                      "Movement as medicine. Your mood, energy, and stress are closely tied to whether you've moved your body. A partner should know this."),
                .init("journaling_or_creative_outlets", "Journaling or creative outlets",
                      "You process through expression. Writing, drawing, making — these aren't hobbies, they're how you stay sane."),
                .init("talking_to_close_friends", "Talking to close friends",
                      "Connection is your therapy. You process best in conversation with people you trust. Your partner is probably part of that circle."),
                .init("meditation_or_mindfulness_practice", "Meditation or mindfulness practice",
                      "Intentional stillness. You've built a practice that grounds you — and that probably makes you calmer in conflict too."),
                .init("being_outdoors_or_in_nature", "Being outdoors or in nature",
                      "Nature is genuinely restorative for you. Time outside shifts your whole system. A partner who understands this will suggest a walk, not just a talk."),
                .init("limiting_social_media", "Limiting social media",
                      "Intentional about your inputs. You know that comparison and noise affect your mental state — and you manage it."),
                .init("honestly_i_m_still_building_this", "Honestly — I'm still building this",
                      "Self-aware about what you need but still working on it. That honesty is its own kind of health."),
                .init("i_don_t_have_a_consistent_practice", "I don't have a consistent practice",
                      "Worth thinking about together. Supporting each other's wellbeing is one of the best things couples can do."),
            ],
            allowsMultiple: true
        ),

        .init(
            questionId: "health_stress",
            topic: .lifestyle,
            question: "When you're overwhelmed or stressed, you usually…",
            subtitle: "Your stress response reveals how your nervous system works — and how your partner can help.",
            options: [
                .init("go_quiet_and_need_space_to_process", "Go quiet and need space to process",
                      "Inward. You need to sit with it alone before you're ready to share or connect. Let people in eventually — don't disappear."),
                .init("talk_it_out_with_someone_close_to_me", "Talk it out with someone close to me",
                      "Social processing. Saying it out loud helps you understand how you feel. Your partner is probably your first call."),
                .init("throw_myself_into_something_productive", "Throw myself into something productive",
                      "Action-oriented. You feel better when you're doing something about it — even if there's nothing to do. Channel that well."),
                .init("distract_myself_shows_games_anything", "Distract myself — shows, games, anything",
                      "Escape before engagement. You need to lower the volume before you can face it. Just don't use distraction to avoid indefinitely."),
                .init("exercise_or_move_burn_it_off", "Exercise or move — burn it off",
                      "Your body is the outlet. Stress is physical for you — and burning it off actually works. Your partner should just hand you your gym bag."),
                .init("eat_or_drink_something_comforting", "Eat or drink something comforting",
                      "Oral comfort is your soothe. Not always sustainable — but very human. Worth having something else in the toolkit too."),
                .init("worry_about_it_repeatedly_until_it_passes", "Worry about it repeatedly until it passes",
                      "Anxious processing. Your mind works through repetition and what-ifs. A grounding partner who doesn't dismiss the anxiety helps most."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "health_sleep",
            topic: .lifestyle,
            question: "How do you feel about your sleep?",
            subtitle: "Sleep affects mood, patience, and how available you are as a partner.",
            options: [
                .init("i_sleep_great_and_protect_it_seriously", "I sleep great and protect it seriously",
                      "Sleep is sacred for you. A partner who keeps you up, or has different sleep habits, will affect your functioning — and your mood."),
                .init("decent_most_nights_no_major_issues", "Decent most nights — no major issues",
                      "Baseline healthy. You probably take it for granted, which is fine — until you're sharing a bed with someone with very different habits."),
                .init("inconsistent_stress_or_thoughts_keep_me_up", "Inconsistent — stress or thoughts keep me up",
                      "Your mental state directly affects your sleep. High-stress periods will hit your sleep first. Worth having a wind-down routine."),
                .init("chronically_tired_it_s_a_known_problem", "Chronically tired — it's a known problem",
                      "This is affecting everything — your mood, your patience, your capacity for connection. Worth treating it as a priority."),
                .init("night_owl_who_would_sleep_better_if_i_went", "Night owl who would sleep better if I went to bed earlier",
                      "You know the solution but you don't do it. An earlier-to-bed partner might actually help — or drive you crazy."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Entertainment & Hobbies

        .init(
            questionId: "ent_shows",
            topic: .lifestyle,
            question: "What kind of content do you actually watch?",
            subtitle: "Pick everything that describes what's on your watchlist right now.",
            options: [
                .init("drama_thriller", "Drama / thriller"),
                .init("comedy_i_need_to_laugh", "Comedy — I need to laugh"),
                .init("romance", "Romance"),
                .init("documentaries", "Documentaries"),
                .init("sci_fi_or_fantasy", "Sci-fi or fantasy"),
                .init("reality_tv", "Reality TV"),
                .init("true_crime", "True crime"),
                .init("horror", "Horror"),
                .init("action_adventure", "Action / adventure"),
                .init("anime", "Anime"),
                .init("nature_travel_content", "Nature / travel content"),
                .init("news_and_current_affairs", "News and current affairs"),
            ],
            allowsMultiple: true
        ),

        .init(
            questionId: "ent_books",
            topic: .lifestyle,
            question: "What's your relationship with reading?",
            subtitle: "",
            options: [
                .init("always_reading_something_it_s_a_core_habit", "Always reading something — it's a core habit",
                      "Books are central to how you learn and decompress. Recommending books to each other is a great couple ritual."),
                .init("i_read_occasionally_when_i_find_the_right", "I read occasionally when I find the right book",
                      "You need the hook. Genre and recommendation matter — the right book at the right time changes everything."),
                .init("more_of_a_podcast_person", "More of a podcast person",
                      "Audio learner and story lover. You absorb ideas while doing other things. Probably has great recommendations."),
                .init("audiobooks_count_right", "Audiobooks count, right?",
                      "Absolutely. You still love stories and ideas — just in a format that fits your life better."),
                .init("i_used_to_read_more_i_want_to_get_back_to_it", "I used to read more — I want to get back to it",
                      "It's still in there. Life crowded it out. A book-recommending partner might be the nudge."),
                .init("honestly_not_my_thing", "Honestly not my thing",
                      "That's fine. Worth knowing if your partner is a big reader — they might want to share that part of their world."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "ent_hobbies",
            topic: .lifestyle,
            question: "What do you actually do in your spare time?",
            subtitle: "Pick everything that genuinely takes up your free time.",
            options: [
                .init("gaming", "Gaming"),
                .init("art_drawing_or_creative_making", "Art, drawing, or creative making"),
                .init("cooking_and_food", "Cooking and food"),
                .init("sport_or_fitness", "Sport or fitness"),
                .init("music_playing_or_listening_seriously", "Music — playing or listening seriously"),
                .init("reading", "Reading"),
                .init("outdoors_hiking_nature", "Outdoors — hiking, nature"),
                .init("photography_or_videography", "Photography or videography"),
                .init("coding_or_building_things", "Coding or building things"),
                .init("socialising_i_m_always_seeing_people", "Socialising — I'm always seeing people"),
                .init("nothing_i_rest_and_i_m_not_sorry", "Nothing — I rest and I'm not sorry"),
                .init("watching_content", "Watching content"),
                .init("gardening", "Gardening"),
                .init("fashion_or_personal_style", "Fashion or personal style"),
                .init("learning_something_new_online", "Learning something new online"),
            ],
            allowsMultiple: true
        ),

        .init(
            questionId: "ent_games",
            topic: .lifestyle,
            question: "Do you game or play board games?",
            subtitle: "",
            options: [
                .init("video_games_are_a_big_part_of_my_life", "Video games are a big part of my life",
                      "Gaming is a real part of your social and leisure life. A partner needs to understand the time and the community that comes with it."),
                .init("i_play_occasionally_casual_gamer", "I play occasionally — casual gamer",
                      "Low-stakes relationship with games. You enjoy it without it being a significant time investment."),
                .init("board_games_with_friends_that_s_my_thing", "Board games with friends — that's my thing",
                      "Social and strategic. Board games are about the people as much as the game. A great shared hobby."),
                .init("both_games_in_general_are_fun", "Both — games in general are fun",
                      "Games as a general love. You probably appreciate any kind of play — which is a good instinct in a relationship too."),
                .init("not_really_my_thing_at_all", "Not really my thing at all",
                      "Fair. Just worth knowing if your partner would love to play with you — or if they need their gaming time respected."),
            ],
            allowsMultiple: false
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
            options: [
                .init("a_new_language", "A new language",
                      "Communication unlocks worlds. There's probably somewhere you want to go — or someone you want to understand."),
                .init("cooking_something_complex", "Cooking something complex",
                      "Food as craft. You want the skill, not just the result. Great for someone who loves feeding people."),
                .init("an_instrument_or_music_skill", "An instrument or music skill",
                      "Music as expression. Even modest skill in an instrument changes how you experience music entirely."),
                .init("a_physical_skill_sport_dance_martial_art", "A physical skill — sport, dance, martial art",
                      "Embodied learning. Getting better at something physical is uniquely satisfying — and often social."),
                .init("a_creative_skill_writing_art_photography", "A creative skill — writing, art, photography",
                      "Making things. You probably have ideas inside you that you haven't found a way to express yet."),
                .init("a_professional_or_tech_skill", "A professional or tech skill",
                      "Practical investment in yourself. This one probably connects to bigger ambitions."),
                .init("something_outdoors_climbing_surfing_sailing", "Something outdoors — climbing, surfing, sailing",
                      "Adventure and environment. You want skill that takes you somewhere."),
                .init("something_i_find_difficult_public_speaking", "Something I find difficult — public speaking, confidence",
                      "Tackling the uncomfortable. This is growth at its most valuable — and often the hardest."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Future & Life Vision

        .init(
            questionId: "future_where",
            topic: .lifestyle,
            question: "Where do you picture yourself living in 5 years?",
            subtitle: "Location expectations matter more than people discuss early in relationships.",
            options: [
                .init("same_city_i_m_in_now_i_m_rooted_here", "Same city I'm in now — I'm rooted here",
                      "You have roots — community, family, career — that matter to you. Moving would be a big ask. A partner needs to know this."),
                .init("a_different_city_in_the_same_country", "A different city in the same country",
                      "Open to change but within familiar culture. You want a fresh start without full relocation uncertainty."),
                .init("another_country_entirely", "Another country entirely",
                      "Adventure and reinvention. This is a major life move — worth knowing if your partner shares that openness."),
                .init("somewhere_quieter_smaller_city_or_rural", "Somewhere quieter — smaller city or rural",
                      "Slower pace, more space. You're drawn to calm over stimulation. A city-loving partner might find this hard."),
                .init("i_genuinely_don_t_know_open_to_anything", "I genuinely don't know — open to anything",
                      "Maximum flexibility — or genuine uncertainty. Either way, you're not anchored to a specific place, which is a real freedom."),
                .init("wherever_life_and_opportunity_takes_me", "Wherever life and opportunity takes me",
                      "Optimistic and adaptive. You go where things are good. That requires a partner who can move with you."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "future_home",
            topic: .lifestyle,
            question: "What does your dream home look like?",
            subtitle: "The space you live in affects everything — how you rest, socialise, work.",
            options: [
                .init("city_apartment_in_the_middle_of_everything", "City apartment — in the middle of everything",
                      "Energy and access. You want walkability, noise, convenience. The city is your natural habitat."),
                .init("house_with_a_garden_and_outdoor_space", "House with a garden and outdoor space",
                      "Space to breathe. A garden for dinner, kids, a dog — you're thinking in domestic terms and that's honest."),
                .init("somewhere_surrounded_by_nature", "Somewhere surrounded by nature",
                      "Environment as lifestyle. You want to wake up to green, not concrete. That usually means committing to a location."),
                .init("something_unique_or_unconventional", "Something unique or unconventional",
                      "Personality in your environment. Converted warehouse, boat, off-grid cabin — you want the space to say something about you."),
                .init("a_home_with_space_for_a_home_office", "A home with space for a home office",
                      "Work from home is real life now. Having a proper space matters for your productivity and your sanity."),
                .init("it_doesn_t_matter_it_s_who_i_m_with_that", "It doesn't matter — it's who I'm with that counts",
                      "Romantic and adaptable. You can be happy anywhere with the right person — and that's genuinely true for some people."),
            ],
            allowsMultiple: false
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
            options: [
                .init("travel_as_much_as_possible_see_everything", "Travel as much as possible — see everything",
                      "The reward for a life of work is seeing the world. You're probably saving toward a version of freedom."),
                .init("be_close_to_family_and_watch_them_grow", "Be close to family and watch them grow",
                      "Connection and legacy. Being present for the people you love in the final chapter means everything to you."),
                .init("start_a_passion_project_i_ve_been_saving_for", "Start a passion project I've been saving for",
                      "Deferred dreams. There's something you've always wanted to build or create — and you're playing a long game."),
                .init("slow_quiet_life_peace_is_the_point", "Slow, quiet life — peace is the point",
                      "Rest as reward. You've probably worked hard enough — or watched others not stop — to know what you want at the end."),
                .init("keep_working_on_things_i_care_about", "Keep working on things I care about",
                      "Identity beyond retirement. You won't stop — you'll just redirect. Purpose keeps people young."),
                .init("it_s_too_far_away_to_meaningfully_think", "It's too far away to meaningfully think about",
                      "Present-focused. You're not wired for long-range planning — or you're young enough that this feels theoretical."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Deeper Values

        .init(
            questionId: "values_deal",
            topic: .communication,
            question: "What's a non-negotiable for you in a relationship?",
            subtitle: "The thing that, if it's missing, you can't make the relationship work.",
            options: [
                .init("honesty_even_when_it_s_uncomfortable", "Honesty — even when it's uncomfortable",
                      "You'd rather hear something hard than be managed with comfortable half-truths. Radical honesty is both your standard and your offer."),
                .init("mutual_respect_always", "Mutual respect, always",
                      "The floor, not the ceiling. Everything else can be worked on — but disrespect breaks the foundation."),
                .init("emotional_availability_and_presence", "Emotional availability and presence",
                      "Being truly there — not just physically. You need a partner who can sit with feelings, theirs and yours."),
                .init("shared_values_and_direction_in_life", "Shared values and direction in life",
                      "Alignment on the big things — how you want to live, what you're building. Compatibility of vision matters."),
                .init("laughter_and_lightness", "Laughter and lightness",
                      "A relationship without joy isn't sustainable. You need someone who can be funny, silly, and light even when life isn't."),
                .init("loyalty_and_commitment", "Loyalty and commitment",
                      "Being chosen, consistently. Not just at the beginning — but every day after that too."),
                .init("physical_and_emotional_intimacy", "Physical and emotional intimacy",
                      "Closeness in all its forms. When physical and emotional connection is missing, everything else feels hollow."),
                .init("personal_freedom_within_the_relationship", "Personal freedom within the relationship",
                      "You need to remain yourself — your friendships, your interests, your space. Love shouldn't feel like losing yourself."),
            ],
            allowsMultiple: false
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
            options: [
                .init("dropping_everything_when_they_need_me", "Dropping everything when they need me",
                      "Emergency presence is your love language of support. You show up fully when it matters most."),
                .init("consistent_small_acts_of_care_over_time", "Consistent small acts of care over time",
                      "Reliability over heroics. You're not there for the drama — you're there in the daily showing up."),
                .init("listening_without_jumping_to_advice", "Listening without jumping to advice",
                      "The gift of being heard. You know how to hold space — and you resist the urge to fix. That's rare."),
                .init("doing_whatever_practically_helps", "Doing whatever practically helps",
                      "Tangible support. You show love through action when someone's struggling — not just words."),
                .init("respecting_whatever_they_say_they_need", "Respecting whatever they say they need",
                      "You follow their lead. You don't impose your version of support — you ask and then deliver what they actually want."),
                .init("staying_close_without_smothering", "Staying close without smothering",
                      "Presence with space. You're there — but you don't crowd. That requires reading someone well."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "values_growth",
            topic: .communication,
            question: "Do you believe couples should grow together or retain their independence?",
            subtitle: "How you balance 'us' and 'me' is one of the defining dynamics of any relationship.",
            options: [
                .init("mostly_together_aligned_goals_and_direction", "Mostly together — aligned goals and direction",
                      "You see the relationship as a joint project. Major decisions involve both of you — and that's how you want it."),
                .init("strong_individual_identity_first_then_shared", "Strong individual identity first, then shared",
                      "Independence keeps you healthy. You bring a full person to the relationship rather than merging completely."),
                .init("both_equally_you_grow_together_and_apart", "Both equally — you grow together and apart",
                      "The nuanced answer — and often the healthiest one. Together where it counts, independent where it matters."),
                .init("it_shifts_across_different_life_seasons", "It shifts across different life seasons",
                      "Context-dependent. Different phases of life call for different balance — and you know that."),
                .init("still_figuring_out_where_i_land_on_this", "Still figuring out where I land on this",
                      "Honest. This is one of those things you often learn more about by being in the relationship than before it."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Fun & Personality

        .init(
            questionId: "fun_intro",
            topic: .lifestyle,
            question: "Where do you fall on the introvert–extrovert spectrum?",
            subtitle: "This affects how you recharge, socialise, and need space in a relationship.",
            options: [
                .init("introvert_alone_time_genuinely_recharges_me", "Introvert — alone time genuinely recharges me",
                      "Solitude is not loneliness for you — it's necessary. A partner who always wants company might feel like pressure. Communicate this early."),
                .init("extrovert_i_get_energy_from_being_around", "Extrovert — I get energy from being around people",
                      "Socially fuelled. Being alone too much drains you. A partner who needs a lot of space might leave you feeling disconnected."),
                .init("ambivert_i_m_genuinely_both_depending_on", "Ambivert — I'm genuinely both depending on context",
                      "Flexible and context-sensitive. You probably navigate most social situations well — and can meet introverted or extroverted partners."),
                .init("more_introverted_but_i_push_myself_socially", "More introverted but I push myself socially",
                      "You can do the social things but you pay a cost. Recovery time after social events is real for you."),
                .init("more_extroverted_but_i_value_alone_time", "More extroverted but I value alone time",
                      "You need people but you're not dependent on them. A healthy mix of connection and personal space suits you best."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "fun_spontaneous",
            topic: .lifestyle,
            question: "How spontaneous are you?",
            subtitle: "This reveals how you handle surprise, change, and uncertainty — in life and in relationships.",
            options: [
                .init("very_spontaneous_let_s_do_it_right_now", "Very spontaneous — let's do it right now",
                      "You thrive in the unplanned. Rigid schedules feel like a cage. A partner who over-plans might slow you down — or ground you."),
                .init("i_like_a_rough_plan_but_can_improvise", "I like a rough plan but can improvise",
                      "Flexible within structure. You want a safety net but you don't need a script. Most people find this easy to work with."),
                .init("i_prefer_to_plan_things_surprises_stress_me", "I prefer to plan things — surprises stress me",
                      "You feel safer with a plan. That's not a character flaw — it's how you manage anxiety and perform at your best."),
                .init("i_want_to_say_spontaneous_but_i_actually", "I want to say spontaneous but I actually need notice",
                      "Honest self-awareness. You admire spontaneity but practically function better with lead time."),
                .init("it_depends_entirely_on_what_it_is", "It depends entirely on what it is",
                      "Contextual. A last-minute dinner? Yes. A last-minute flight? Maybe not. You're not rigid — you're reading the stakes."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "fun_humor",
            topic: .lifestyle,
            question: "What kind of humour do you have?",
            subtitle: "Shared humour is one of the strongest relationship compatibility signals.",
            options: [
                .init("dry_and_sarcastic", "Dry and sarcastic",
                      "Understated. Your humour rewards people who are paying attention. Not everyone gets it — but the ones who do, get you."),
                .init("silly_and_physical_i_m_a_kid", "Silly and physical — I'm a kid",
                      "Uninhibited. You're comfortable being ridiculous — and that ease is actually quite intimate. Hard to be silly with someone you're guarded around."),
                .init("observational_i_notice_things_others_miss", "Observational — I notice things others miss",
                      "You find the absurdity in everyday things. Your humour is a byproduct of how closely you pay attention."),
                .init("self_deprecating_i_take_the_easy_target", "Self-deprecating — I take the easy target",
                      "You disarm people by going first. It's a confidence thing, not a low self-esteem thing — when done right."),
                .init("dark_but_always_kind", "Dark, but always kind",
                      "You find funny in difficult places — but you punch toward the world, not toward vulnerable people. That distinction matters."),
                .init("wordplay_and_puns_genuinely", "Wordplay and puns — genuinely",
                      "You love language enough to play with it. Puns are dad jokes done with commitment — and that takes guts."),
                .init("storytelling_i_make_things_funny_through", "Storytelling — I make things funny through context",
                      "The build-up is your thing. You're funnier in person than in a text — and your stories improve with every retelling."),
                .init("i_m_a_good_audience_but_not_the_joke_maker", "I'm a good audience but not the joke-maker",
                      "You appreciate humour deeply even if you don't perform it. Being a great audience is its own underrated gift."),
            ],
            allowsMultiple: true
        ),

        .init(
            questionId: "fun_dealbreaker",
            topic: .lifestyle,
            question: "Pineapple on pizza — where do you stand?",
            subtitle: "This tells us everything.",
            options: [
                .init("absolutely_yes_i_will_die_on_this_hill", "Absolutely yes — I will die on this hill",
                      "Bold. Unwavering. You know what you like and you're not ashamed of it. That's actually a personality trait."),
                .init("hard_no_it_s_a_textures_thing", "Hard no — it's a textures thing",
                      "Principled. You have standards and you apply them to pizza. Fruit belongs elsewhere."),
                .init("i_don_t_care_either_way_this_is_not", "I don't care either way — this is not important",
                      "The most balanced take. Possibly the most well-adjusted person in this quiz."),
                .init("only_under_very_specific_conditions", "Only under very specific conditions",
                      "A nuanced position on pizza. You probably apply this level of conditional thinking to most of life's questions."),
            ],
            allowsMultiple: false
        ),

        // MARK: - Childhood & Background

        .init(
            questionId: "child_holiday",
            topic: .lifestyle,
            question: "What were holidays and celebrations like growing up?",
            subtitle: "How you grew up celebrating shapes what you expect — and want — now.",
            options: [
                .init("big_loud_family_gatherings_the_more_the", "Big, loud family gatherings — the more the better",
                      "You probably replicate this or miss it. Celebration is big, communal, and festive in your imagination."),
                .init("quiet_intimate_just_close_family", "Quiet, intimate — just close family",
                      "Celebration as closeness. Big gatherings feel overwhelming — you prefer the depth of a small group."),
                .init("inconsistent_it_depended_on_the_year", "Inconsistent — it depended on the year",
                      "Unpredictability was part of your experience. You may have complicated feelings about celebrations as a result."),
                .init("mostly_normal_days_we_weren_t_big_on", "Mostly normal days — we weren't big on celebration",
                      "You don't have strong emotional ties to holidays — which can be freeing or leave you feeling like something's missing."),
                .init("travelling_or_doing_something_different", "Travelling or doing something different",
                      "Experience over tradition. Celebration meant adventure — and you probably still prefer that over a dinner table."),
            ],
            allowsMultiple: false
        ),

        .init(
            questionId: "child_influence",
            topic: .lifestyle,
            question: "How much has your upbringing shaped who you are today?",
            subtitle: "No right answer — this is about your relationship to your own history.",
            options: [
                .init("a_lot_for_better_and_worse_it_made_me", "A lot — for better and worse, it made me",
                      "Self-aware about where you come from. The good and difficult parts of your story are both visible to you."),
                .init("mostly_positive_i_had_a_good_foundation", "Mostly positive — I had a good foundation",
                      "Lucky and grateful. You carry patterns worth repeating into your own relationships."),
                .init("i_ve_consciously_worked_to_unlearn_some_of", "I've consciously worked to unlearn some of it",
                      "Growth in action. You've identified things you don't want to pass on — and you're doing the work. That's significant."),
                .init("not_much_i_ve_forged_my_own_path", "Not much — I've forged my own path",
                      "Independent by design or necessity. You've written your own story largely separate from where you began."),
                .init("it_s_complicated_and_i_m_still_working_it", "It's complicated and I'm still working it out",
                      "Honest. Most people are. The willingness to examine it is the most important part."),
            ],
            allowsMultiple: false
        ),
    ]

    /// Indexed rather than scanned: every stored answer now resolves through
    /// this lookup, including once per option while a sheet is on screen, so
    /// a linear pass over 72 templates per call is no longer the right shape.
    private static let byIdIndex: [String: ChatQuizTemplate] = Dictionary(
        all.map { ($0.questionId, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static func byId(_ id: String) -> ChatQuizTemplate? {
        byIdIndex[id]
    }

    static func byTopic(_ topic: QuizTopic) -> [ChatQuizTemplate] {
        all.filter { $0.topic == topic }
    }
}
