const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const OpenAI = require("openai");

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Secret stored via: firebase functions:secrets:set OPENAI_API_KEY
const openaiApiKey = defineSecret("OPENAI_API_KEY");

// =============================================================================
// MARK: - Constants
// =============================================================================

const MAX_NOTIFICATIONS_PER_DAY = 2;
const INACTIVITY_THRESHOLD_HOURS = 24;

const PRIORITY_LOW_MOOD = 1;
const PRIORITY_DAILY_SYNC = 2;
const PRIORITY_INACTIVITY = 3;

// =============================================================================
// MARK: - Notification Messages (Human, Caring Tone)
// =============================================================================

const LOW_MOOD_MESSAGES = [
  {
    title: "Your partner might need you",
    body: "They seem to be having a tough time today. A small gesture can mean everything.",
  },
  {
    title: "A little love goes a long way",
    body: "Your partner could use some extra care right now.",
  },
  {
    title: "Time to show you care",
    body: "Your partner is going through a rough patch. Even a short message helps.",
  },
];

const DAILY_SYNC_MESSAGES = [
  {
    title: "Stay in sync today",
    body: "Your partner already checked in — join them and share how you're feeling.",
  },
  {
    title: "Don't miss today's check-in",
    body: "Your partner shared their mood. Take a moment to share yours too.",
  },
  {
    title: "Check in together",
    body: "Couples who check in daily feel more connected. Your turn!",
  },
];

const REACTION_LABELS = {
  heart: { emoji: "❤️", phrase: "sent you love" },
  hug: { emoji: "🫂", phrase: "sent you a virtual hug" },
  callMe: { emoji: "📞", phrase: "wants you to call them" },
  coffee: { emoji: "☕", phrase: "is thinking of you over coffee" },
};

const PING_MESSAGES = [
  { title: "Thinking of you", body: "Your partner just sent a little love your way." },
  { title: "A quiet ping", body: "Your partner is thinking about you right now." },
  { title: "You're on their mind", body: "Your partner wanted you to know they care." },
];

const INACTIVITY_MESSAGES = [
  {
    title: "It's been a while",
    body: "You haven't checked in recently. Your partner might be wondering how you are.",
  },
  {
    title: "Missing you",
    body: "A quick mood check-in keeps you two connected, even on busy days.",
  },
  {
    title: "Stay connected",
    body: "Life gets busy, but a moment to share how you feel keeps your bond strong.",
  },
];

// =============================================================================
// MARK: - Future AI Hook
// =============================================================================

/**
 * Generate a personalized notification using OpenAI.
 * Falls back to null (uses template messages) if AI is unavailable.
 *
 * @param {Object} userProfile - Partner preferences, communication style
 * @param {Object} context - Mood data, interaction history, time of day
 * @returns {Object|null} { title, body } or null for fallback
 */
async function generatePersonalizedNotification(userProfile, context) {
  // Only attempt AI generation if we have a profile and API key
  if (!userProfile || !openaiApiKey.value()) return null;

  try {
    const openai = new OpenAI({ apiKey: openaiApiKey.value() });

    const typeDescriptions = {
      low_mood: "Their partner logged a sad or stressed mood",
      daily_sync: "Their partner checked in but they haven't yet today",
      inactivity: "They haven't interacted with the app in over 24 hours",
    };

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.6,
      max_tokens: 100,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content: `You write short, caring push notification text for a couples app. Be warm and human. Never robotic. Respond with JSON: { "title": "...", "body": "..." }. Title: max 8 words. Body: max 15 words.`,
        },
        {
          role: "user",
          content: `Situation: ${typeDescriptions[context.type] || context.type}. Write a notification.`,
        },
      ],
    });

    const content = completion.choices[0]?.message?.content;
    if (!content) return null;

    const parsed = JSON.parse(content);
    if (parsed.title && parsed.body) return parsed;

    return null;
  } catch (error) {
    console.warn("AI notification generation failed, using template:", error.message);
    return null;
  }
}

// =============================================================================
// MARK: - Helper Functions
// =============================================================================

function pickRandom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function startOfToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

/**
 * Check how many notifications were sent to a user today.
 * Returns true if the user can still receive notifications.
 */
async function canSendNotification(userId) {
  const today = startOfToday();

  const snapshot = await db
    .collection("notifications")
    .where("userId", "==", userId)
    .where("sentAt", ">=", Timestamp.fromDate(today))
    .get();

  return snapshot.size < MAX_NOTIFICATIONS_PER_DAY;
}

/**
 * Check if a duplicate notification of this type was already sent today.
 */
async function isDuplicateToday(userId, type) {
  const today = startOfToday();

  const snapshot = await db
    .collection("notifications")
    .where("userId", "==", userId)
    .where("type", "==", type)
    .where("sentAt", ">=", Timestamp.fromDate(today))
    .limit(1)
    .get();

  return !snapshot.empty;
}

/**
 * Record that a notification was sent.
 */
async function recordNotification(userId, type, title, body) {
  await db.collection("notifications").add({
    userId,
    type,
    title,
    body,
    sentAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Get the user's FCM token from Firestore.
 */
async function getFcmToken(userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return null;
  return userDoc.data().fcmToken || null;
}

/**
 * Get the partner's userId from the couple document.
 */
async function getPartnerId(coupleId, userId) {
  const coupleDoc = await db.collection("couples").doc(coupleId).get();
  if (!coupleDoc.exists) return null;

  const userIds = coupleDoc.data().userIds || [];
  return userIds.find((id) => id !== userId) || null;
}

/**
 * Find the coupleId for a given userId.
 */
async function findCoupleId(userId) {
  const snapshot = await db
    .collection("couples")
    .where("userIds", "array-contains", userId)
    .limit(1)
    .get();

  if (snapshot.empty) return null;
  return snapshot.docs[0].id;
}

/**
 * Send a push notification via FCM.
 */
async function sendNotification(userId, type, title, body, data = {}) {
  // Rate limit check
  const allowed = await canSendNotification(userId);
  if (!allowed) {
    console.log(`Rate limit reached for user ${userId}. Skipping.`);
    return false;
  }

  // Duplicate check
  const duplicate = await isDuplicateToday(userId, type);
  if (duplicate) {
    console.log(`Duplicate ${type} notification for user ${userId}. Skipping.`);
    return false;
  }

  // Get FCM token
  const token = await getFcmToken(userId);
  if (!token) {
    console.log(`No FCM token for user ${userId}. Skipping.`);
    return false;
  }

  // Try AI-personalized message first
  const personalized = await generatePersonalizedNotification(null, {
    type,
    userId,
  });

  const finalTitle = personalized?.title || title;
  const finalBody = personalized?.body || body;

  // Send via FCM
  try {
    await messaging.send({
      token,
      notification: {
        title: finalTitle,
        body: finalBody,
      },
      data: {
        type,
        ...data,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            "mutable-content": 1,
            "thread-id": "coupley-nudge",
          },
        },
      },
    });

    // Record the notification
    await recordNotification(userId, type, finalTitle, finalBody);
    console.log(`Sent ${type} notification to user ${userId}`);
    return true;
  } catch (error) {
    console.error(`Failed to send notification to ${userId}:`, error.message);

    // Clean up invalid tokens
    if (
      error.code === "messaging/invalid-registration-token" ||
      error.code === "messaging/registration-token-not-registered"
    ) {
      await db.collection("users").doc(userId).update({ fcmToken: FieldValue.delete() });
      console.log(`Removed invalid FCM token for user ${userId}`);
    }

    return false;
  }
}

// =============================================================================
// MARK: - 1. LOW MOOD ALERT (Firestore Trigger)
// =============================================================================

exports.onMoodCreated = onDocumentCreated(
  "couples/{coupleId}/moods/{moodId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const moodData = snapshot.data();
    const coupleId = event.params.coupleId;
    const userId = moodData.userId;
    const mood = moodData.mood;

    console.log(`New mood logged: ${mood} by user ${userId} in couple ${coupleId}`);

    // Update user's lastMoodAt
    await db.collection("users").doc(userId).update({
      lastMoodAt: FieldValue.serverTimestamp(),
      lastActive: FieldValue.serverTimestamp(),
    });

    // Only trigger for low moods (sad or stressed)
    if (mood !== "sad" && mood !== "stressed") {
      console.log(`Mood ${mood} does not trigger alert. Skipping.`);
      return;
    }

    // Find partner
    const partnerId = await getPartnerId(coupleId, userId);
    if (!partnerId) {
      console.log("Partner not found. Skipping.");
      return;
    }

    // Send low mood alert to partner
    const message = pickRandom(LOW_MOOD_MESSAGES);
    await sendNotification(partnerId, "low_mood", message.title, message.body, {
      coupleId,
      moodUserId: userId,
      mood,
    });
  }
);

// =============================================================================
// MARK: - 2. DAILY SYNC CHECK (Scheduled — every 4 hours)
// =============================================================================

// Runs hourly; only nudges users whose *local* hour matches their preferred
// reminder hour (defaults to 20 / 8pm). Timezone comes from users/{uid}.timezone.
exports.dailySyncCheck = onSchedule("every 1 hours", async () => {
  console.log("Running daily sync check (TZ-aware)...");

  const today = startOfToday();
  const couplesSnapshot = await db.collection("couples").get();

  for (const coupleDoc of couplesSnapshot.docs) {
    const coupleId = coupleDoc.id;
    const userIds = coupleDoc.data().userIds || [];

    if (userIds.length !== 2) continue;

    const moodsSnapshot = await db
      .collection(`couples/${coupleId}/moods`)
      .where("timestamp", ">=", Timestamp.fromDate(today))
      .get();

    const usersWhoLogged = new Set(moodsSnapshot.docs.map((doc) => doc.data().userId));

    for (const userId of userIds) {
      if (usersWhoLogged.has(userId)) continue;
      const partnerId = userIds.find((id) => id !== userId);

      const hourOk = await isUsersReminderHour(userId);
      if (!hourOk) continue;

      // Partner already checked in → urgent daily_sync. Otherwise gentle self-nudge.
      const isPartnerReminder = usersWhoLogged.has(partnerId);
      const messages = isPartnerReminder ? DAILY_SYNC_MESSAGES : INACTIVITY_MESSAGES;
      const type = isPartnerReminder ? "daily_sync" : "inactivity";
      const message = pickRandom(messages);

      await sendNotification(userId, type, message.title, message.body, { coupleId });
    }
  }

  console.log("Daily sync check complete.");
});

/**
 * Returns true if the current UTC time equals the user's preferred local
 * reminder hour, per their stored timezone. Defaults: 20:00 local.
 */
async function isUsersReminderHour(userId) {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return false;

  const data = userDoc.data();
  const tz = data.timezone || "UTC";
  const reminderHour = typeof data.reminderHour === "number" ? data.reminderHour : 20;

  // Get the current hour in the user's local timezone
  let localHour;
  try {
    const fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hour: "numeric",
      hour12: false,
    });
    localHour = parseInt(fmt.format(new Date()), 10);
  } catch (e) {
    console.warn(`Invalid timezone for user ${userId}: ${tz}`);
    return false;
  }

  return localHour === reminderHour;
}

// =============================================================================
// MARK: - 3. INACTIVITY CHECK (Scheduled — every 6 hours)
// =============================================================================

exports.inactivityCheck = onSchedule("every 6 hours", async () => {
  console.log("Running inactivity check...");

  const thresholdDate = new Date(
    Date.now() - INACTIVITY_THRESHOLD_HOURS * 60 * 60 * 1000
  );

  const couplesSnapshot = await db.collection("couples").get();

  for (const coupleDoc of couplesSnapshot.docs) {
    const coupleId = coupleDoc.id;
    const userIds = coupleDoc.data().userIds || [];

    if (userIds.length !== 2) continue;

    for (const userId of userIds) {
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data();
      const lastActive = userData.lastActive?.toDate();

      // If no lastActive or it's beyond the threshold
      if (!lastActive || lastActive < thresholdDate) {
        const message = pickRandom(INACTIVITY_MESSAGES);
        await sendNotification(userId, "inactivity", message.title, message.body, {
          coupleId,
        });
      }
    }
  }

  console.log("Inactivity check complete.");
});

// =============================================================================
// MARK: - 4. AI SUGGESTION ENDPOINT (HTTP)
// =============================================================================

// In-memory cache: key = hash of request, value = { result, timestamp }
const suggestionCache = new Map();
const CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes

function buildCacheKey(mood, energy, communicationStyle) {
  return `${mood}:${energy}:${communicationStyle}`;
}

function getCachedResult(key) {
  const entry = suggestionCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.timestamp > CACHE_TTL_MS) {
    suggestionCache.delete(key);
    return null;
  }
  return entry.result;
}

function setCachedResult(key, result) {
  // Cap cache size
  if (suggestionCache.size > 200) {
    const oldest = suggestionCache.keys().next().value;
    suggestionCache.delete(oldest);
  }
  suggestionCache.set(key, { result, timestamp: Date.now() });
}

// --- Input Validation ---

const VALID_MOODS = ["happy", "neutral", "sad", "stressed"];
const VALID_ENERGIES = ["low", "medium", "high"];
const VALID_STYLES = ["introvert", "expressive", "avoidant"];

function validateRequest(body) {
  const errors = [];

  if (!body.mood || !VALID_MOODS.includes(body.mood)) {
    errors.push(`mood must be one of: ${VALID_MOODS.join(", ")}`);
  }
  if (!body.energy || !VALID_ENERGIES.includes(body.energy)) {
    errors.push(`energy must be one of: ${VALID_ENERGIES.join(", ")}`);
  }
  if (!body.profile || typeof body.profile !== "object") {
    errors.push("profile object is required");
  } else {
    if (
      !body.profile.communicationStyle ||
      !VALID_STYLES.includes(body.profile.communicationStyle)
    ) {
      errors.push(
        `profile.communicationStyle must be one of: ${VALID_STYLES.join(", ")}`
      );
    }
    if (body.profile.likes && !Array.isArray(body.profile.likes)) {
      errors.push("profile.likes must be an array");
    }
    if (body.profile.dislikes && !Array.isArray(body.profile.dislikes)) {
      errors.push("profile.dislikes must be an array");
    }
  }

  return errors;
}

// --- OpenAI Prompt Builder ---

function buildSystemPrompt() {
  return `You are a warm, emotionally intelligent relationship assistant. Your job is to help one partner support the other when they're going through a hard time.

Rules:
- Every message must be 1-2 sentences max
- Sound like a caring human, never robotic or clinical
- Be specific when possible — reference their interests and preferences
- Never be preachy, generic, or give unsolicited advice
- The action must be concrete and doable today

You MUST respond with valid JSON only, no markdown, no explanation.`;
}

function buildUserPrompt(mood, energy, note, profile) {
  const likes = (profile.likes || []).join(", ") || "not specified";
  const dislikes = (profile.dislikes || []).join(", ") || "not specified";
  const style = profile.communicationStyle || "expressive";
  const noteText = note ? `They mentioned: "${note}"` : "No specific note.";

  return `My partner is feeling ${mood} with ${energy} energy.
${noteText}

About them:
- Communication style: ${style}
- Things they like: ${likes}
- Things they dislike: ${dislikes}

Generate:
1. Three short messages I could send them, each with a different tone:
   - "gentle": warm and soft
   - "playful": light and fun
   - "direct": honest and supportive
2. One real-world action I can do today to help

Respond in this exact JSON format:
{
  "messages": {
    "gentle": "...",
    "playful": "...",
    "direct": "..."
  },
  "action": "..."
}`;
}

// --- Cloud Function ---

exports.generateSuggestion = onRequest(
  {
    secrets: [openaiApiKey],
    cors: true,
    maxInstances: 20,
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (req, res) => {
    // Only allow POST
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed. Use POST." });
      return;
    }

    // Validate Firebase Auth (optional but recommended)
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith("Bearer ")) {
      // Future: verify Firebase ID token
      // const token = authHeader.split("Bearer ")[1];
      // const decoded = await admin.auth().verifyIdToken(token);
    }

    // Parse & validate input
    const body = req.body;
    const errors = validateRequest(body);
    if (errors.length > 0) {
      res.status(400).json({ error: "Invalid request", details: errors });
      return;
    }

    const { mood, energy, note, profile } = body;

    // Check cache
    const cacheKey = buildCacheKey(mood, energy, profile.communicationStyle);
    const cached = getCachedResult(cacheKey);
    if (cached && !note) {
      // Only use cache when there's no personal note (notes make it unique)
      res.status(200).json({
        ...cached,
        cached: true,
      });
      return;
    }

    // Call OpenAI
    try {
      const openai = new OpenAI({ apiKey: openaiApiKey.value() });

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.5,
        max_tokens: 400,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: buildSystemPrompt() },
          { role: "user", content: buildUserPrompt(mood, energy, note, profile) },
        ],
      });

      const content = completion.choices[0]?.message?.content;
      if (!content) {
        res.status(502).json({ error: "Empty response from AI" });
        return;
      }

      // Parse the AI response
      let parsed;
      try {
        parsed = JSON.parse(content);
      } catch {
        console.error("Failed to parse AI response:", content);
        res.status(502).json({ error: "Invalid JSON from AI" });
        return;
      }

      // Validate response structure
      if (
        !parsed.messages ||
        !parsed.messages.gentle ||
        !parsed.messages.playful ||
        !parsed.messages.direct ||
        !parsed.action
      ) {
        console.error("Malformed AI response:", parsed);
        res.status(502).json({ error: "Malformed response from AI" });
        return;
      }

      const result = {
        messages: {
          gentle: String(parsed.messages.gentle).slice(0, 300),
          playful: String(parsed.messages.playful).slice(0, 300),
          direct: String(parsed.messages.direct).slice(0, 300),
        },
        action: String(parsed.action).slice(0, 500),
        mood,
        energy,
        generatedAt: new Date().toISOString(),
      };

      // Cache (only when no personal note)
      if (!note) {
        setCachedResult(cacheKey, result);
      }

      // Log for analytics
      try {
        await db.collection("aiSuggestionLogs").add({
          mood,
          energy,
          communicationStyle: profile.communicationStyle,
          hasNote: !!note,
          tokensUsed: completion.usage?.total_tokens || 0,
          model: completion.model,
          createdAt: FieldValue.serverTimestamp(),
        });
      } catch (logError) {
        // Non-critical — don't fail the request
        console.warn("Failed to log suggestion:", logError.message);
      }

      res.status(200).json(result);
    } catch (error) {
      console.error("OpenAI API error:", error.message);

      // Return appropriate status based on error type
      if (error.status === 429) {
        res.status(429).json({ error: "Rate limited. Please try again shortly." });
      } else if (error.status === 401) {
        res.status(500).json({ error: "AI service configuration error" });
      } else {
        res.status(500).json({ error: "Failed to generate suggestion" });
      }
    }
  }
);

// =============================================================================
// MARK: - 5. MOOD REACTION (Firestore Trigger)
// =============================================================================

exports.onReactionCreated = onDocumentCreated(
  "couples/{coupleId}/moods/{moodId}/reactions/{reactionId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reaction = snap.data();
    const { coupleId, moodId } = event.params;
    const reactorId = reaction.userId;
    const kind = reaction.kind || "heart";

    // Fetch the mood to find the author (the person who should be notified)
    const moodDoc = await db.doc(`couples/${coupleId}/moods/${moodId}`).get();
    if (!moodDoc.exists) return;

    const moodAuthorId = moodDoc.data().userId;
    if (!moodAuthorId || moodAuthorId === reactorId) return;

    const label = REACTION_LABELS[kind] || REACTION_LABELS.heart;

    await sendNotification(
      moodAuthorId,
      "reaction",
      `${label.emoji} Your partner ${label.phrase}`,
      "Open Coupley to respond.",
      { coupleId, moodId, kind }
    );
  }
);

// =============================================================================
// MARK: - 6. THINKING-OF-YOU PING (Firestore Trigger)
// =============================================================================

exports.onPingCreated = onDocumentCreated(
  "couples/{coupleId}/pings/{pingId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const ping = snap.data();
    const { coupleId } = event.params;
    const senderId = ping.fromUserId;
    if (!senderId) return;

    const partnerId = await getPartnerId(coupleId, senderId);
    if (!partnerId) return;

    const message = pickRandom(PING_MESSAGES);
    await sendNotification(partnerId, "ping", message.title, message.body, {
      coupleId,
      fromUserId: senderId,
    });
  }
);

// =============================================================================
// MARK: - 7. PREMIUM ENTITLEMENT PROPAGATION
// =============================================================================
//
// Keeps couples/{coupleId}.premium in sync when:
//   a) a user purchases premium while solo (users/{uid}.premium → becomes active),
//   b) two users pair (couple doc created) and either already owns premium.
//
// The client writes premium to both docs on purchase, but this server-side
// copy is the safety net so partner inheritance never depends on the buyer's
// client being online when pairing happens.
// =============================================================================

exports.onUserPremiumChanged = onDocumentWritten(
  "users/{userId}",
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data() || {};

    const prevPremium = before.premium || {};
    const nextPremium = after.premium || {};
    const premiumChanged =
      JSON.stringify(prevPremium) !== JSON.stringify(nextPremium);
    if (!premiumChanged) return;

    const coupleId = after.coupleId;
    if (!coupleId) return; // solo users — nothing to propagate
    if (!nextPremium.active) return; // on cancellation, the client also clears the couple doc

    await db.collection("couples").doc(coupleId).set(
      { premium: nextPremium },
      { merge: true }
    );
    console.log(`Propagated premium to couple ${coupleId} from user ${event.params.userId}`);
  }
);

exports.onCoupleCreated = onDocumentCreated(
  "couples/{coupleId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const couple = snap.data();
    const userIds = couple.userIds || [];
    if (userIds.length < 2) return;

    // Find the first active entitlement among partners and copy it to the
    // couple doc. If both purchased (edge case), prefer the one that expires
    // later.
    const userDocs = await Promise.all(
      userIds.map((uid) => db.collection("users").doc(uid).get())
    );

    const candidates = userDocs
      .map((doc) => doc.data()?.premium)
      .filter((p) => p && p.active === true);

    if (candidates.length === 0) return;

    const chosen = candidates.sort((a, b) => {
      const ae = a.expiresAt?.toMillis?.() || 0;
      const be = b.expiresAt?.toMillis?.() || 0;
      return be - ae;
    })[0];

    await snap.ref.set({ premium: chosen }, { merge: true });
    console.log(`Seeded couple ${event.params.coupleId} with existing premium`);
  }
);
