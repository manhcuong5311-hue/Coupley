//
//  MockAICoachService.swift
//  Coupley
//
//  Offline coach. Responses are composed from a library of psychologically
//  grounded fragments (attachment theory, Gottman repair attempts, NVC) so
//  the feature feels substantive even without a backend. Every reply is
//  personalized by attachment style + love language + issue type.
//

import Foundation

final class MockAICoachService: AICoachService {

    // MARK: - Reply (freeform)

    func reply(
        to userMessage: String,
        transcript: [CoachChatMessage],
        context: CoachContext
    ) async throws -> String {
        try await simulateThinking()
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Opening line matched to emotional tone in their message
        let opener = openerLine(for: lower, context: context)
        // Reflect back what they said
        let reflection = reflection(for: lower, partnerName: context.partnerName)
        // Attachment-informed insight
        let insight = attachmentInsight(context: context)
        // A practical next step
        let nextStep = nextStep(for: lower, context: context)

        return [opener, reflection, insight, nextStep]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    // MARK: - Guided

    func guidedResponse(
        issue: CoachIssueType,
        userInput: String,
        context: CoachContext
    ) async throws -> GuidedResponse {
        try await simulateThinking(short: false)
        let partner = context.partnerName
        let love = context.partnerLoveLanguage ?? context.loveLanguage ?? .qualityTime
        let attach = context.partnerAttachmentStyle ?? context.attachmentStyle ?? .secure

        switch issue {
        case .fight:
            return GuidedResponse(
                situationAnalysis: "A fight is almost never about the thing on the surface. Underneath, one or both of you felt unseen, dismissed, or unsafe. What looks like a disagreement about facts is usually a disagreement about feeling heard.",
                partnerPerspective: "\(partner) likely felt that their experience was being overridden, not just debated. When you disagreed, their nervous system may have read it as \"you don't get me\" rather than \"we see this differently.\" That's what made it escalate.",
                bestNextAction: "Wait until you both feel regulated — usually 20–30 minutes of space. Then come back and lead with curiosity, not defense. Say: \"I care more about us than being right. Help me understand what that felt like for you.\" Listen without preparing your counter-argument.",
                whatNotToDo: "Don't send a long text while you're still heated. Don't rehash the logic of who was right. Don't say \"I'm sorry you feel that way\" — that's not an apology, it's a dodge. Don't bring up past fights as ammunition.",
                suggestedMessage: suggestedApologyMessage(partner: partner, love: love, issue: issue),
                longTermAdvice: "If this is a recurring fight, the topic is a symptom — the pattern is the real issue. Notice the loop: who pulls away first, who pushes to resolve, how it ends. Name the pattern together when you're calm, not in the middle of it.",
                issue: issue
            )

        case .distance:
            return GuidedResponse(
                situationAnalysis: "Emotional distance is rarely about you personally. People pull away when something internal — stress, shame, overwhelm — is bigger than they can hold and share at the same time. Distance is often protective, not rejecting.",
                partnerPerspective: "\(partner) may be carrying something they haven't found the words for yet. For an \(attach.label.lowercased()) partner, the instinct under strain is \(attach == .avoidant ? "inward and quiet" : "to seek reassurance but fear being a burden"). The silence is a symptom, not a statement about the relationship.",
                bestNextAction: "Reach toward them without demanding access. Warmth without pressure. A small act of care in their love language — \(love.label.lowercased()) — signals safety. Give them a clear opening to come back to you when they're ready.",
                whatNotToDo: "Don't interrogate (\"what's wrong?\" repeated ten times). Don't take it personally out loud — it makes them manage your feelings on top of theirs. Don't pretend you haven't noticed; silence on your end mirrors the distance.",
                suggestedMessage: "Hey \(partner) — I've noticed you've felt a little far away, and I'm not asking you to explain. I just want you to know I'm here, not going anywhere, and whenever you want to talk or not talk, I'm around.",
                longTermAdvice: "Build a low-pressure check-in ritual — a weekly 10 minutes where each of you names one thing that felt good and one thing that felt heavy. Distance grows fastest when there's no regular time to say the small things.",
                issue: issue
            )

        case .apology:
            return GuidedResponse(
                situationAnalysis: "A real apology isn't a performance — it's accountability. The reason apologies often fail is they center the apologizer's guilt (\"I feel terrible\") instead of the hurt person's experience. A good apology makes them feel seen, not you feel forgiven.",
                partnerPerspective: "\(partner) doesn't need to hear that you feel bad. They need to hear that you understand, specifically, what you did and how it landed. Until that happens, any kindness can feel like an attempt to skip past the hurt.",
                bestNextAction: "Name the specific thing. Name the specific impact. Take responsibility without \"but.\" Then say what you'll do differently — concretely, not abstractly. End by asking what they need from you, and then actually do it.",
                whatNotToDo: "Don't say \"I'm sorry you felt hurt\" (that blames their reaction). Don't list your reasons (that's a defense). Don't ask to be forgiven on your timeline. Don't expect one apology to close a wound that took multiple moments to make.",
                suggestedMessage: suggestedApologyMessage(partner: partner, love: love, issue: issue),
                longTermAdvice: "The apology isn't the repair — the changed behavior is. Pay attention over the next weeks to whether the thing you apologized for stops happening. That's what actually rebuilds trust.",
                issue: issue
            )

        case .reconnect:
            return GuidedResponse(
                situationAnalysis: "Connection doesn't erode from one big thing — it erodes from a thousand tiny moments where you didn't quite turn toward each other. Reconnection works the same way, in reverse: small, frequent, intentional.",
                partnerPerspective: "\(partner) is probably feeling the same drift, even if they haven't named it. People often wait for the other person to initiate, interpreting the silence as disinterest. They're likely hoping you move first.",
                bestNextAction: "Don't try to fix everything in one big conversation. Start with a \(love.label.lowercased())-flavored moment today — small, specific, no agenda. Then another tomorrow. Connection comes back in rhythm, not in a single grand gesture.",
                whatNotToDo: "Don't schedule a \"we need to talk about us\" sit-down as the opener — it raises threat instead of warmth. Don't overwhelm them with everything you've been feeling at once. Don't test whether they care; show that you do.",
                suggestedMessage: "I've been missing us lately — not in a heavy way, just in a \"I want more of you\" way. Can we carve out a little time this week that's just ours, no phones, no plans?",
                longTermAdvice: "Put connection on the calendar. Couples who thrive don't rely on it being organic; they protect the time. One shared ritual a week — a walk, a meal, a question — becomes the floor you don't drop below.",
                issue: issue
            )

        case .stress:
            return GuidedResponse(
                situationAnalysis: "When someone is stressed, they don't need your analysis of their stress — they need to feel less alone inside it. The fastest way to help is to lower the temperature of the room around them, not the thing causing the stress.",
                partnerPerspective: "\(partner) may not know what they need, and asking \"what do you need?\" can feel like one more task. Under pressure, an \(attach.label.lowercased()) partner tends to want \(stressCueFor(attach)).",
                bestNextAction: "Offer specific support, not open-ended help. \"I'll handle dinner tonight\" beats \"let me know if I can do anything.\" Match your offer to their love language — \(love.label.lowercased()). Then let them off the hook for reciprocating right now.",
                whatNotToDo: "Don't try to solve it unless they asked. Don't minimize (\"it'll be fine\"). Don't take their short fuse personally — it's not about you. Don't pile on your own stress in the same conversation.",
                suggestedMessage: "I can see you're carrying a lot. You don't need to perform being okay with me. I've got dinner, I've got the logistics tonight — just be here.",
                longTermAdvice: "Learn each other's stress signature. What does overwhelm look like in them — short replies, missed meals, working late? Name it when you see it, early, before it becomes a wall.",
                issue: issue
            )

        case .trust:
            return GuidedResponse(
                situationAnalysis: "Trust is built in small consistent moments and broken in specific ones. Rebuilding it takes longer than breaking it — not because your partner is punishing you, but because their nervous system needs repeated evidence that the new pattern is real.",
                partnerPerspective: "\(partner) is probably oscillating between wanting to believe you and bracing for another disappointment. That's not manipulation — it's how attachment systems protect themselves. Every time you show up consistently, the bracing softens a little.",
                bestNextAction: "Over-communicate in the short term. Tell them where you are and when, before they ask. Follow through on small commitments visibly. Acknowledge the repair is on your timeline to earn, not theirs to grant.",
                whatNotToDo: "Don't get defensive when they ask questions — the questions are the work. Don't demand forgiveness on a schedule. Don't bring up things they've done to justify what you did. Don't go quiet when things get hard; that's the exact move that broke trust.",
                suggestedMessage: "I know trust doesn't come back because I want it to. I'm not asking you to feel safe yet — I'm asking to show you, over time, that this is different. Tell me when you notice it, and tell me when you don't.",
                longTermAdvice: "Trust is repaired in layers. Month 1 is \"can I believe what you say?\" Month 3 is \"can I believe you'll show up?\" Month 6+ is \"can I stop watching?\" Don't rush the layers.",
                issue: issue
            )

        case .communication:
            return GuidedResponse(
                situationAnalysis: "Most communication problems aren't about vocabulary — they're about safety. If either of you doesn't feel safe being honest without consequences, the content of your words can't land, no matter how well you phrase them.",
                partnerPerspective: "\(partner) may be filtering what they say based on how they expect you to react. That's not dishonesty — it's self-protection. If conversations usually end in them being defended against, they'll stop bringing the real thing.",
                bestNextAction: "When they share something hard, your first job is to receive, not respond. Repeat back what you heard them say — not their words, their meaning. Ask \"did I get that right?\" before you share your side. This one habit changes everything.",
                whatNotToDo: "Don't interrupt to clarify facts. Don't say \"that's not what happened.\" Don't jump to solutions. Don't use \"you always\" or \"you never.\" Don't raise your voice to be heard — volume makes your partner's brain shut your words out.",
                suggestedMessage: "I want to understand you better. Can we try something — when one of us shares something hard, the other just reflects it back first, before reacting? I think we'd hear each other more.",
                longTermAdvice: "Pick one conversation a week to practice slow listening — no phones, one topic, 15 minutes. The goal isn't to solve anything; it's to build the muscle of being heard. The hard conversations get easier when the easy ones get deeper.",
                issue: issue
            )

        case .custom:
            return GuidedResponse(
                situationAnalysis: "I read your message carefully. What stands out is that you're already doing the hardest part — you're naming that something's off and trying to understand it instead of pretending it isn't there.",
                partnerPerspective: "Without more detail I can only guess, but whatever \(partner) is experiencing, they're likely also trying to make sense of it in their own way. You're probably not as far apart in how you're feeling as the silence suggests.",
                bestNextAction: "Start by sharing the feeling, not the conclusion. Instead of \"you did X,\" say \"I noticed I felt Y when Z happened.\" Give them the emotional data first; it lets them respond to you instead of defending themselves.",
                whatNotToDo: "Don't go into the conversation with a verdict already reached. Don't ask a question you already have the answer to — that's a trap. Don't time the conversation when one of you is tired, hungry, or about to leave.",
                suggestedMessage: "Hey \(partner), I've been thinking about us and I want to check in — not because something is wrong, but because I care enough to ask. When's a good time to actually talk?",
                longTermAdvice: "Couples who stay close don't avoid hard conversations — they have smaller ones, more often. Build a habit of saying the small thing before it becomes the big thing.",
                issue: issue
            )
        }
    }

    // MARK: - Rewrite

    func rewrite(message: String, context: CoachContext) async throws -> [MessageRewrite] {
        try await simulateThinking()
        let partner = context.partnerName
        let original = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let flavor = detectFlavor(in: original.lowercased())

        let soft = softRewrite(original: original, partner: partner, flavor: flavor)
        let honest = honestRewrite(original: original, partner: partner, flavor: flavor)
        let repair = repairRewrite(original: original, partner: partner, flavor: flavor)

        return [
            MessageRewrite(original: original, rewritten: soft, tone: .soft),
            MessageRewrite(original: original, rewritten: honest, tone: .honest),
            MessageRewrite(original: original, rewritten: repair, tone: .repair)
        ]
    }

    // MARK: - Health

    func healthCheck(context: CoachContext) async throws -> RelationshipHealth {
        try await simulateThinking(short: false)

        // Deterministic but context-flavored scoring. Seeded by context hash so
        // retaking the check-in gives a stable baseline.
        let seed = (context.myName + context.partnerName + (context.recentMoodNote ?? "")).hashValue
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seed)))

        func score(_ lowerBound: Int, _ upperBound: Int) -> Int {
            Int.random(in: lowerBound...upperBound, using: &rng)
        }

        let trust = score(68, 88)
        let communication = score(62, 84)
        let emotionalIntimacy = score(64, 86)
        let support = score(72, 92)
        let consistency = score(66, 85)

        let weakest = [
            ("trust", trust),
            ("communication", communication),
            ("emotional intimacy", emotionalIntimacy),
            ("support", support),
            ("consistency", consistency)
        ].min(by: { $0.1 < $1.1 })?.0 ?? "communication"

        let summary = "Your relationship is healthier than most. You show up for each other consistently and the foundation is solid. The area with the most room to grow is \(weakest) — not because it's broken, but because small investments here will compound fast."

        var redFlags: [String] = []
        if communication < 70 {
            redFlags.append("Conversations tend to end unresolved — build a habit of naming what you need out loud.")
        }
        if trust < 75 {
            redFlags.append("Watch for avoidance after small breaches — repair them quickly before they stack up.")
        }

        return RelationshipHealth(
            trust: trust,
            communication: communication,
            emotionalIntimacy: emotionalIntimacy,
            support: support,
            consistency: consistency,
            summary: summary,
            redFlags: redFlags,
            generatedAt: Date()
        )
    }

    // MARK: - Recovery Plan

    func recoveryPlan(
        length: RecoveryPlan.Length,
        issue: CoachIssueType?,
        context: CoachContext
    ) async throws -> RecoveryPlan {
        try await simulateThinking(short: false)
        let partner = context.partnerName
        let love = context.partnerLoveLanguage ?? context.loveLanguage ?? .qualityTime

        let days = (1...length.dayCount).map { n in
            recoveryDay(n: n, total: length.dayCount, partner: partner, love: love, issue: issue)
        }

        let title: String
        let intro: String
        switch issue {
        case .some(.fight):
            title = "Repair after the argument"
            intro = "The goal this week isn't to prove you're right. It's to show \(partner) — and yourself — that you can come back from hard moments stronger than you went in."
        case .some(.distance):
            title = "Close the distance"
            intro = "Small, consistent warmth beats one grand gesture. Each day, do one thing that lowers the temperature between you."
        case .some(.trust):
            title = "Rebuild the trust"
            intro = "Trust comes back in small, boring, consistent deposits. The work isn't dramatic — it's daily."
        default:
            title = length == .threeDay ? "3-day reconnect" : "7-day reconnect"
            intro = "A gentle week to shift the pattern. One small action a day — nothing heroic — just a steady turn toward each other."
        }

        return RecoveryPlan(
            length: length,
            title: title,
            intro: intro,
            days: days
        )
    }

    // MARK: - Helpers

    private func simulateThinking(short: Bool = true) async throws {
        try await Task.sleep(nanoseconds: short ? 900_000_000 : 1_400_000_000)
    }

    private func openerLine(for lower: String, context: CoachContext) -> String {
        if lower.contains("fight") || lower.contains("argu") || lower.contains("fought") {
            return "That sounds exhausting. Fights rarely feel like they're really about what they seem to be about."
        }
        if lower.contains("distant") || lower.contains("cold") || lower.contains("quiet") {
            return "Emotional distance is one of the hardest things to sit with, because you can't point at it."
        }
        if lower.contains("sorry") || lower.contains("apolog") {
            return "How you apologize matters as much as that you do. I can help you say it in a way that actually lands."
        }
        if lower.contains("trust") {
            return "Trust is fragile, and rebuilding it is real work. Let's go slow with this."
        }
        if lower.contains("love") || lower.contains("unloved") {
            return "Feeling unloved even when someone says they love you is one of the most confusing places to be in a relationship."
        }
        if lower.contains("stress") {
            return "When someone's stressed, they often can't say what they need — even to themselves. Your instinct to help is already the right one."
        }
        return "I'm listening. Let's work through this together."
    }

    private func reflection(for lower: String, partnerName: String) -> String? {
        if lower.isEmpty { return nil }
        // Light reflective paraphrase — non-invasive, just enough to show reading.
        if lower.contains("never") || lower.contains("always") {
            return "It sounds like this isn't a one-off — it's a pattern you're tired of."
        }
        if lower.contains("alone") {
            return "What I'm hearing is loneliness inside the relationship, which is a heavier kind of lonely."
        }
        if lower.contains("don't know") || lower.contains("idk") {
            return "Not knowing is a real place to be — you don't have to have clarity to start talking about it."
        }
        return nil
    }

    private func attachmentInsight(context: CoachContext) -> String? {
        guard let partnerAttach = context.partnerAttachmentStyle ?? context.attachmentStyle else {
            return nil
        }
        switch partnerAttach {
        case .anxious:
            return "Given what you've shared about \(context.partnerName), under stress they likely need more reassurance than feels necessary to you — that's not neediness, it's their nervous system asking \"are we okay?\""
        case .avoidant:
            return "With \(context.partnerName)'s pattern of pulling inward under pressure, the move that works is less pressure, more presence. Space isn't rejection — it's how they regulate so they can come back."
        case .fearfulAvoidant:
            return "\(context.partnerName) wants closeness and fears it at the same time. The same gesture can feel like safety one day and a threat the next. Consistency matters more than intensity."
        case .secure:
            return "\(context.partnerName)'s secure instincts are an asset here — they can probably hold space for a hard conversation if you open one."
        }
    }

    private func nextStep(for lower: String, context: CoachContext) -> String {
        let love = context.partnerLoveLanguage ?? context.loveLanguage ?? .qualityTime
        return "One small move this evening: a \(love.label.lowercased())-flavored gesture — something specific, not grand. It lowers the temperature and signals you're present, without demanding a response yet."
    }

    private func suggestedApologyMessage(partner: String, love: LoveLanguage, issue: CoachIssueType) -> String {
        switch issue {
        case .fight:
            return "I've been thinking about earlier, \(partner). I don't want to be right, I want to understand you. I realize I dismissed how you were feeling, and I'm sorry. Tell me what you needed from me in that moment."
        case .apology:
            return "I realize I hurt you, and I don't want to skip past that. You weren't wrong to feel what you felt. I'm sorry — specifically for \(issuePlaceholder()). What do you need from me right now?"
        case .trust:
            return "I know I broke something that matters. I'm not asking you to be over it — I'm asking to show you, over time, that I take this seriously. Start by telling me what you need next."
        default:
            return "I care about you, \(partner), and I don't want us to be stuck. Tell me what this felt like on your side — I want to hear it."
        }
    }

    private func issuePlaceholder() -> String {
        "the way I responded when you were trying to share something that mattered"
    }

    private func stressCueFor(_ attach: AttachmentStyle) -> String {
        switch attach {
        case .anxious:         return "closeness and reassurance, not solutions"
        case .avoidant:        return "space and low-pressure presence"
        case .fearfulAvoidant: return "consistent warmth without pressure to open up"
        case .secure:          return "a mix of presence and practical help"
        }
    }

    private enum MessageFlavor {
        case apology, defensive, cold, confused, needy, generic
    }

    private func detectFlavor(in lower: String) -> MessageFlavor {
        if lower.contains("sorry if") || lower.contains("i didn't mean") { return .apology }
        if lower.contains("you always") || lower.contains("you never") || lower.contains("not my fault") { return .defensive }
        if lower.contains("fine.") || lower.contains("whatever") || lower.contains("k.") { return .cold }
        if lower.contains("i don't know") || lower.contains("confused") { return .confused }
        if lower.contains("miss you") || lower.contains("need you") { return .needy }
        return .generic
    }

    private func softRewrite(original: String, partner: String, flavor: MessageFlavor) -> String {
        switch flavor {
        case .apology:
            return "Hey \(partner) — that came out wrong. What I meant was: I see that I hurt you, and I'm sorry. I'd rather understand what that felt like for you than defend what I meant."
        case .defensive:
            return "I want to hear you out before I defend myself. Can you tell me again, and I promise to actually listen this time?"
        case .cold:
            return "I'm not actually fine, and I don't want to pretend. I need a little time to cool down, and then I want to come back to this with you — not against you."
        case .confused:
            return "I'm a little tangled up in what I'm feeling right now. I don't want to push you away while I figure it out — can we be gentle with each other for a minute?"
        case .needy:
            return "I've been missing you today — not in a heavy way. Just wanted to say you crossed my mind and I'm glad you're mine."
        case .generic:
            return "Hey \(partner) — thinking about you. I want to say this in a way that actually reaches you, so let me try: \(trimFirstSentence(original))"
        }
    }

    private func honestRewrite(original: String, partner: String, flavor: MessageFlavor) -> String {
        switch flavor {
        case .apology:
            return "\(partner), I said \"sorry if you feel hurt\" and that wasn't an apology — that was a dodge. I'm sorry for what I did, full stop. I'd like to hear what the impact actually was, if you're open to telling me."
        case .defensive:
            return "I catch myself wanting to list reasons, and I know that's not what you need. You're not asking me to be right — you're asking me to hear you. I'll try again."
        case .cold:
            return "I went quiet because I was hurt. I should have said that instead of shutting you out. Can we try this again?"
        case .confused:
            return "I don't have clean words for what I'm feeling, but I know the silence between us doesn't match how much I care. Give me a minute, and let's talk tonight."
        case .needy:
            return "I've noticed I've been leaning on you more than usual lately. I don't want to put that weight on you — I just want to be honest that I've been missing the version of us where we felt really close."
        case .generic:
            return "I want to be honest with you, \(partner): here's what's actually going on for me — \(trimFirstSentence(original)). I'm telling you not to make you fix it, but because I don't want to carry it without you knowing."
        }
    }

    private func repairRewrite(original: String, partner: String, flavor: MessageFlavor) -> String {
        switch flavor {
        case .apology:
            return "That wasn't the right way to say it. I'm truly sorry for hurting you. Your feelings matter to me and I want to make this right — tell me how."
        case .defensive:
            return "I was defending instead of listening, and that's on me. I don't want to win this — I want to understand you. I'm sorry for making it feel like a fight."
        case .cold:
            return "I shut down on you and that wasn't fair. I was overwhelmed, but that's not your problem to manage. I'm sorry — I'd like to come back and do this properly."
        case .confused:
            return "I haven't shown up the way I wanted to lately, and I know you've felt it. I'm not making excuses — I'm telling you I see it, and I'm working on it."
        case .needy:
            return "I've been clinging a little, and I think it's because I've been scared we were drifting. I own that. I don't want to pressure you — I want to find our rhythm again, together."
        case .generic:
            return "I've been sitting with this, \(partner), and I want to take responsibility for my part. \(trimFirstSentence(original)). That's on me, and I'd like to do it differently going forward."
        }
    }

    private func trimFirstSentence(_ text: String) -> String {
        let stopped = text.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? text
        return stopped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recoveryDay(n: Int, total: Int, partner: String, love: LoveLanguage, issue: CoachIssueType?) -> RecoveryPlan.Day {
        let themes3 = ["Safety", "Repair", "Forward"]
        let themes7 = ["Safety", "Listening", "Ownership", "Repair", "Warmth", "Fun", "Forward"]
        let themes = total == 3 ? themes3 : themes7
        let theme = themes[n - 1]

        let actions: [String]
        let message: String

        switch theme {
        case "Safety":
            actions = [
                "Send one low-pressure check-in — no agenda, just presence.",
                "Do one chore they usually do, without announcement.",
                "Keep the tone warm and short today; no big conversations."
            ]
            message = "Hey \(partner) — no agenda, just thinking of you today. Hope your day's okay."

        case "Listening":
            actions = [
                "Ask one open question and listen without defending.",
                "Reflect back what you heard before sharing your side.",
                "Thank them for trusting you with the honest version."
            ]
            message = "I've been wanting to really hear you lately. Got time tonight to just talk — no fixing, just listening?"

        case "Ownership":
            actions = [
                "Name one specific thing you contributed to the distance.",
                "Apologize without adding a 'but'.",
                "Say what you'll do differently — concretely, not abstractly."
            ]
            message = "I've been thinking about my part in this. I want to own it with you, not around you. Can we talk when you're up for it?"

        case "Repair":
            actions = [
                "Offer a gesture in their love language — \(love.label.lowercased()).",
                "Follow through on one small thing you'd said you'd do.",
                "Acknowledge what's been different this week — name the effort you're both making."
            ]
            message = "I know this week has been a shift. Thank you for meeting me in it. You matter to me more than the thing we were stuck on."

        case "Warmth":
            actions = [
                "Do one small \(love.label.lowercased()) gesture.",
                "Send an affectionate message with no ask attached.",
                "Sit close, phones away, for just 15 minutes."
            ]
            message = "Just wanted to say — I'm grateful for you. That's the whole message."

        case "Fun":
            actions = [
                "Do something playful together — a show, a walk, a small adventure.",
                "Laugh at something together, intentionally.",
                "No relationship talk today; just enjoy each other."
            ]
            message = "Let's do something that's just fun tonight — no agenda, no talk about us, just us being us."

        case "Forward":
            actions = [
                "Name one thing you each want more of in the next month.",
                "Put a small weekly ritual on the calendar.",
                "Thank each other out loud for making it through the week."
            ]
            message = "I feel closer to you than I did at the start of the week. Let's build on that, not just drop the thread."

        default:
            actions = ["Turn toward each other in one small way today."]
            message = "Thinking of you."
        }

        return RecoveryPlan.Day(
            dayNumber: n,
            theme: theme,
            actions: actions,
            message: message
        )
    }
}

// MARK: - Seeded RNG

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
