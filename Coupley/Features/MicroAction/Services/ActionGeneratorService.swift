//
//  ActionGeneratorService.swift
//  Coupley
//

import Foundation

// MARK: - Protocol

protocol ActionGeneratorService {
    /// Produce 1–3 micro actions for the current context. First action is the
    /// "focus"; the rest are secondary.
    func generate(context: MicroActionContext) -> [MicroAction]
}

// MARK: - Rule-based Generator

/// Curated templates keyed by a fine-grained *mood bucket* (mood × energy ×
/// freshness). Deliberately low-drama copy — no "your love", no exclamation
/// points. The goal is a gentle nudge, not a push notification from a
/// wellness app. Templates are further personalized by the partner's
/// communication style, stress response, and love language when known.
final class RuleBasedActionGenerator: ActionGeneratorService {

    // MARK: - Template

    private struct Template {
        let text: String
        let rationale: String
        /// Optional love-language affinity. When the partner's love language
        /// matches one of these, the template is ranked higher in the pool.
        var loveLanguage: [LoveLanguage] = []
        /// Optional stress-response affinity. Same idea, for crisis pools.
        var stressResponse: [StressResponse] = []
    }

    // MARK: - Mood Buckets
    //
    // Finer-grained than Mood × EnergyLevel alone so copy can land on the
    // actual state — "stressed + high energy" (venting) is a different room
    // from "stressed + low energy" (burnt out).
    private enum Bucket {
        case burnout            // stressed + low energy
        case venting            // stressed + medium/high energy
        case lowSpirits         // sad + medium/high energy
        case heavyHeart         // sad + low energy
        case flatTired          // neutral + low energy
        case neutralSteady      // neutral + medium energy
        case neutralReady       // neutral + high energy
        case contentChill       // happy + low energy
        case contentBright      // happy + medium energy
        case upbeatSpark        // happy + high energy
        case staleOrUnknown     // no data or >24h old
    }

    // MARK: - Pools

    private lazy var pools: [Bucket: [Template]] = [

        // ---------- CRISIS / STRESS ----------

        .burnout: [
            Template(
                text: "Don't ask what's wrong. Just bring something — water, food, a blanket.",
                rationale: "They're running on empty. Care without questions lands soft.",
                loveLanguage: [.actsOfService, .physicalTouch],
                stressResponse: [.seeksComfort, .needsSpace]
            ),
            Template(
                text: "Take one small thing off their plate today, silently.",
                rationale: "When energy is gone, relief > reassurance.",
                loveLanguage: [.actsOfService],
                stressResponse: [.needsSpace, .wantsDistraction]
            ),
            Template(
                text: "Sit beside them without talking. Let the silence do the work.",
                rationale: "Quiet company is its own comfort.",
                loveLanguage: [.qualityTime, .physicalTouch],
                stressResponse: [.needsSpace, .seeksComfort]
            ),
            Template(
                text: "Send one line: 'no reply needed — thinking of you.'",
                rationale: "Low-demand signals don't tax a drained battery.",
                loveLanguage: [.wordsOfAffirmation],
                stressResponse: [.needsSpace]
            ),
            Template(
                text: "Offer a warm drink and a 10-minute 'do nothing' window.",
                rationale: "A pause is medicine when burnout hits.",
                loveLanguage: [.actsOfService, .qualityTime],
                stressResponse: [.seeksComfort]
            )
        ],

        .venting: [
            Template(
                text: "Listen like a friend, not a fixer. Echo back what they feel.",
                rationale: "When someone's agitated, being understood beats being solved.",
                loveLanguage: [.wordsOfAffirmation, .qualityTime],
                stressResponse: [.talksItOut]
            ),
            Template(
                text: "Ask: 'do you want to vent, problem-solve, or be distracted?'",
                rationale: "Matching the mode they need avoids friction.",
                stressResponse: [.talksItOut, .wantsDistraction]
            ),
            Template(
                text: "Suggest a short walk together — movement takes the edge off.",
                rationale: "Walking lowers cortisol and side-by-side beats face-to-face.",
                loveLanguage: [.qualityTime, .physicalTouch],
                stressResponse: [.wantsDistraction, .talksItOut]
            ),
            Template(
                text: "Skip the advice. Try 'that sounds really hard.'",
                rationale: "Validation first, solutions (maybe) later.",
                loveLanguage: [.wordsOfAffirmation],
                stressResponse: [.talksItOut, .seeksComfort]
            ),
            Template(
                text: "Offer a 20-minute distraction — a show, a meme, anything light.",
                rationale: "Sometimes the nervous system just needs off-duty time.",
                loveLanguage: [.qualityTime],
                stressResponse: [.wantsDistraction]
            )
        ],

        // ---------- SAD ----------

        .heavyHeart: [
            Template(
                text: "Sit close. Say less. Let them lean if they want to.",
                rationale: "Low + sad is a presence-only moment.",
                loveLanguage: [.physicalTouch, .qualityTime],
                stressResponse: [.seeksComfort, .needsSpace]
            ),
            Template(
                text: "Make tea or food they love. Leave it within reach.",
                rationale: "Tiny rituals say 'you're not alone' without words.",
                loveLanguage: [.actsOfService, .physicalTouch],
                stressResponse: [.seeksComfort]
            ),
            Template(
                text: "Send one thing specific you love about them — not 'you're great.'",
                rationale: "Vague praise rebounds. Concrete lands.",
                loveLanguage: [.wordsOfAffirmation],
                stressResponse: [.talksItOut, .seeksComfort]
            ),
            Template(
                text: "Give them space but leave a door open: 'here when you want me.'",
                rationale: "Respect their need to retreat; name the return path.",
                stressResponse: [.needsSpace]
            ),
            Template(
                text: "Put on something comforting — a familiar show, a playlist they love.",
                rationale: "Sensory familiarity is a gentle anchor.",
                loveLanguage: [.qualityTime]
            )
        ],

        .lowSpirits: [
            Template(
                text: "Ask what they *need* — listen, don't fix.",
                rationale: "Sad + not drained often wants to be heard, not managed.",
                loveLanguage: [.wordsOfAffirmation, .qualityTime],
                stressResponse: [.talksItOut]
            ),
            Template(
                text: "Invite them for a slow walk — no agenda, no phones.",
                rationale: "Side-by-side talks are easier than face-to-face ones.",
                loveLanguage: [.qualityTime, .physicalTouch]
            ),
            Template(
                text: "Name what you see: 'looks like today's been heavy.'",
                rationale: "Naming the weather makes it easier to share.",
                loveLanguage: [.wordsOfAffirmation],
                stressResponse: [.talksItOut, .seeksComfort]
            ),
            Template(
                text: "Do something together that asks nothing — cook, fold laundry, draw.",
                rationale: "Hands-busy activities unlock quiet conversation.",
                loveLanguage: [.qualityTime, .actsOfService]
            ),
            Template(
                text: "Text a memory of a good day you had together.",
                rationale: "Gentle rewind — reminds them the feeling isn't permanent.",
                loveLanguage: [.wordsOfAffirmation]
            )
        ],

        // ---------- NEUTRAL ----------

        .flatTired: [
            Template(
                text: "Keep expectations small. Don't plan — just share the couch.",
                rationale: "Tired + flat needs permission to do nothing.",
                loveLanguage: [.qualityTime, .physicalTouch]
            ),
            Template(
                text: "Offer a no-pressure wind-down: 'no need to chat, just here.'",
                rationale: "Low energy doesn't want performance.",
                stressResponse: [.needsSpace, .seeksComfort]
            ),
            Template(
                text: "Handle dinner or a chore they'd usually do. No announcement.",
                rationale: "Silent acts of service refill the tank.",
                loveLanguage: [.actsOfService]
            ),
            Template(
                text: "Put on a comfort show and hand them the remote.",
                rationale: "Low-effort choice, high-effort care.",
                loveLanguage: [.qualityTime]
            )
        ],

        .neutralSteady: [
            Template(
                text: "Send a short check-in — 'how's your afternoon going?'",
                rationale: "A gentle ping beats a long silence.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Ask about something they're working on — specific, not 'how's work.'",
                rationale: "Curiosity > routine. Specifics invite a real answer.",
                loveLanguage: [.wordsOfAffirmation, .qualityTime]
            ),
            Template(
                text: "Share one thing on your mind today. Nothing big.",
                rationale: "Low-stakes openness invites the same back.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Name one small thing you appreciated about them this week.",
                rationale: "Specific praise is harder to deflect and easier to believe.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Plan a tiny thing for this week — a coffee, a walk, a show.",
                rationale: "A neutral mood is fertile ground for small plans.",
                loveLanguage: [.qualityTime]
            )
        ],

        .neutralReady: [
            Template(
                text: "Suggest trying something small and new together this week.",
                rationale: "Steady energy + curiosity = low-cost adventure window.",
                loveLanguage: [.qualityTime]
            ),
            Template(
                text: "Send a song, photo, or clip that reminded you of them today.",
                rationale: "Tiny 'I saw this and thought of you' signals compound.",
                loveLanguage: [.receivingGifts, .wordsOfAffirmation]
            ),
            Template(
                text: "Ask what they're looking forward to this month.",
                rationale: "Forward-looking questions deepen connection.",
                loveLanguage: [.qualityTime, .wordsOfAffirmation]
            ),
            Template(
                text: "Offer to cover one of their chores so their evening is free.",
                rationale: "Steady energy + freed-up time often becomes couple time.",
                loveLanguage: [.actsOfService]
            )
        ],

        // ---------- HAPPY ----------

        .contentChill: [
            Template(
                text: "Join them wherever they are. Don't fill the air — just be there.",
                rationale: "Contentment at low energy just wants company, not stimulation.",
                loveLanguage: [.qualityTime, .physicalTouch]
            ),
            Template(
                text: "Put a hand on their back or shoulder, no words needed.",
                rationale: "Touch speaks when energy is low but the mood is warm.",
                loveLanguage: [.physicalTouch]
            ),
            Template(
                text: "Bring a small treat — tea, a snack, a favorite thing.",
                rationale: "Quiet delight for a quiet-good moment.",
                loveLanguage: [.receivingGifts, .actsOfService]
            )
        ],

        .contentBright: [
            Template(
                text: "Ask about the best part of their day — get specific.",
                rationale: "They're up. Keep the momentum with curiosity.",
                loveLanguage: [.qualityTime, .wordsOfAffirmation]
            ),
            Template(
                text: "Name one specific thing you've appreciated about them lately.",
                rationale: "Specific > generic. 'You're amazing' lands flat.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Bring up an inside joke at an unexpected moment.",
                rationale: "Shared humor is a quiet form of intimacy.",
                loveLanguage: [.qualityTime]
            ),
            Template(
                text: "Suggest a small plan for this week while the mood is good.",
                rationale: "Good moods are great for making plans stick.",
                loveLanguage: [.qualityTime]
            )
        ],

        .upbeatSpark: [
            Template(
                text: "Match their energy. Send something playful — a voice note, a silly pic.",
                rationale: "Joy is contagious; reflect it back and it doubles.",
                loveLanguage: [.wordsOfAffirmation, .qualityTime]
            ),
            Template(
                text: "Suggest something spontaneous tonight — a drive, a walk, a dessert run.",
                rationale: "High-energy + happy is when spontaneity actually happens.",
                loveLanguage: [.qualityTime]
            ),
            Template(
                text: "Tell them, out loud, what you're proud of them for recently.",
                rationale: "Ride the bright mood with a concrete, earned compliment.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Pick up a small favorite — their go-to snack, drink, flower.",
                rationale: "Amplify a good day with a tiny, tangible surprise.",
                loveLanguage: [.receivingGifts, .actsOfService]
            )
        ],

        // ---------- FALLBACK ----------

        .staleOrUnknown: [
            Template(
                text: "Send a short check-in — 'thinking of you, no reply needed.'",
                rationale: "A gentle ping beats a long silence when you're not sure.",
                loveLanguage: [.wordsOfAffirmation]
            ),
            Template(
                text: "Notice one small thing about them today and mention it.",
                rationale: "Attention is the quiet form of affection.",
                loveLanguage: [.wordsOfAffirmation, .qualityTime]
            ),
            Template(
                text: "Ask something you don't already know the answer to.",
                rationale: "Curiosity > routine. Bypass the 'how was work.'"
            ),
            Template(
                text: "Tell them one thing you're grateful for today.",
                rationale: "Gratitude said out loud reshapes the room.",
                loveLanguage: [.wordsOfAffirmation]
            )
        ]
    ]

    // MARK: - Entry point

    func generate(context: MicroActionContext) -> [MicroAction] {
        let bucket = classify(context)
        let tone   = tone(for: bucket)

        let focusPool     = pool(for: bucket)
        let secondaryPool = secondaryPool(for: bucket)

        // Dedup: strip anything that appears in recent history.
        let recent = Set(context.recentActionTexts)

        let rankedFocus     = rank(focusPool,     context: context).filter { !recent.contains($0.text) }
        let rankedSecondary = rank(secondaryPool, context: context).filter { !recent.contains($0.text) }

        let focusSeeds     = rankedFocus.isEmpty     ? focusPool     : rankedFocus
        let secondarySeeds = rankedSecondary.isEmpty ? secondaryPool : rankedSecondary

        guard let focus = pick(from: focusSeeds, seed: context.key) else { return [] }

        var results: [MicroAction] = [
            MicroAction(
                text: personalize(focus.text, context: context, tone: tone),
                tone: tone,
                rationale: focus.rationale,
                contextKey: context.key
            )
        ]

        if let secondary = pick(
            from: secondarySeeds.filter { $0.text != focus.text },
            seed: context.key + ".s1"
        ) {
            // Secondary stays lighter so the card doesn't feel one-note.
            let secondaryTone: MicroActionTone = tone == .support ? .support : .light
            results.append(
                MicroAction(
                    text: personalize(secondary.text, context: context, tone: secondaryTone),
                    tone: secondaryTone,
                    rationale: secondary.rationale,
                    contextKey: context.key
                )
            )
        }

        return results
    }

    // MARK: - Classification

    private func classify(_ ctx: MicroActionContext) -> Bucket {
        guard let mood = ctx.partnerMood else { return .staleOrUnknown }

        let stale = Date().timeIntervalSince(mood.loggedAt) > 24 * 60 * 60
        if stale { return .staleOrUnknown }

        switch (mood.mood, mood.energy) {
        case (.stressed, .low):                 return .burnout
        case (.stressed, .medium), (.stressed, .high): return .venting
        case (.sad, .low):                      return .heavyHeart
        case (.sad, .medium), (.sad, .high):    return .lowSpirits
        case (.neutral, .low):                  return .flatTired
        case (.neutral, .medium):               return .neutralSteady
        case (.neutral, .high):                 return .neutralReady
        case (.happy, .low):                    return .contentChill
        case (.happy, .medium):                 return .contentBright
        case (.happy, .high):                   return .upbeatSpark
        }
    }

    private func tone(for bucket: Bucket) -> MicroActionTone {
        switch bucket {
        case .burnout, .venting, .heavyHeart, .lowSpirits:
            return .support
        case .contentBright, .upbeatSpark, .neutralReady:
            return .bonding
        case .contentChill, .flatTired, .neutralSteady, .staleOrUnknown:
            return .light
        }
    }

    private func pool(for bucket: Bucket) -> [Template] {
        pools[bucket] ?? pools[.staleOrUnknown] ?? []
    }

    /// Secondary pool keeps the copy from being monotone: in crisis moods
    /// reinforce with another support line; in bright moods pair with a
    /// low-stakes light idea so the user has an easy out.
    private func secondaryPool(for bucket: Bucket) -> [Template] {
        switch bucket {
        case .burnout, .heavyHeart:                  return pool(for: bucket)
        case .venting, .lowSpirits:                  return pool(for: .heavyHeart)
        case .contentBright, .upbeatSpark:           return pool(for: .neutralSteady)
        case .neutralReady:                          return pool(for: .contentBright)
        case .flatTired, .contentChill:              return pool(for: .neutralSteady)
        case .neutralSteady, .staleOrUnknown:        return pool(for: .staleOrUnknown)
        }
    }

    // MARK: - Ranking (love language / stress response match)

    /// Rank templates whose affinities match the partner's personality first.
    /// Non-matching templates are preserved as tail so the pool never empties.
    private func rank(_ templates: [Template], context: MicroActionContext) -> [Template] {
        guard let personality = context.profile?.personality else { return templates }

        return templates.sorted { lhs, rhs in
            score(lhs, personality: personality) > score(rhs, personality: personality)
        }
    }

    private func score(_ template: Template, personality: PartnerPersonality) -> Int {
        var s = 0
        if template.loveLanguage.contains(personality.loveLanguage) { s += 2 }
        if template.stressResponse.contains(personality.stressResponse) { s += 1 }
        return s
    }

    // MARK: - Personalize

    /// Soften imperatives for avoidant partners, lean into warmth for
    /// expressive ones, keep introvert copy unembellished.
    private func personalize(_ text: String,
                             context: MicroActionContext,
                             tone: MicroActionTone) -> String {
        guard let profile = context.profile else { return text }

        switch profile.communicationStyle {
        case .avoidant:
            return text
                .replacingOccurrences(of: "Ask ",       with: "Maybe ask ")
                .replacingOccurrences(of: "Tell ",      with: "You could tell ")
                .replacingOccurrences(of: "Suggest ",   with: "Maybe suggest ")
                .replacingOccurrences(of: "Invite ",    with: "You could invite ")
                .replacingOccurrences(of: "Send ",      with: "Maybe send ")

        case .introvert:
            // Soft trim of any high-energy verbs so it reads as optional.
            return text
                .replacingOccurrences(of: "Match their energy. ", with: "")

        case .expressive:
            return text
        }
    }

    // MARK: - Deterministic pick

    private func pick(from templates: [Template], seed: String) -> Template? {
        guard !templates.isEmpty else { return nil }
        var hasher = Hasher()
        hasher.combine(seed)
        let value = abs(hasher.finalize())
        return templates[value % templates.count]
    }
}
