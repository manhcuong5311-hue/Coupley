// Minimal client for the Firestore emulator's REST API, used to test
// firestore.rules with no npm dependencies (Node 20+ has fetch and node:test).
//
// Run from the repo root (the emulator needs Java 21; set JAVA_HOME if java
// is not on PATH):
//
//   firebase emulators:exec --only firestore --project demo-coupley-rules \
//     "node --test firestore-tests/"
//
// A `demo-` project id keeps the emulator fully offline: nothing here can
// reach the real Firebase project.

const HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080'
export const PROJECT = process.env.GCLOUD_PROJECT || 'demo-coupley-rules'

/** Marks a field to be set to the server's request time (FieldValue.serverTimestamp()). */
export const SERVER_TIME = Symbol('serverTime')

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString('base64url')
}

/** An unsigned ID token the emulator accepts as `request.auth.uid == uid`. */
export function tokenFor(uid) {
  const now = Math.floor(Date.now() / 1000)
  return [
    b64url({ alg: 'none', kid: 'fakekid', typ: 'JWT' }),
    b64url({
      iss: `https://securetoken.google.com/${PROJECT}`,
      aud: PROJECT,
      iat: now,
      exp: now + 3600,
      auth_time: now,
      sub: uid,
      user_id: uid,
      firebase: { sign_in_provider: 'custom', identities: {} },
    }),
    '',
  ].join('.')
}

export function encode(v) {
  if (v === null || v === undefined) return { nullValue: null }
  if (v instanceof Date) return { timestampValue: v.toISOString() }
  if (typeof v === 'string') return { stringValue: v }
  if (typeof v === 'boolean') return { booleanValue: v }
  if (typeof v === 'number') {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v }
  }
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encode) } }
  if (typeof v === 'object') return { mapValue: { fields: fields(v) } }
  throw new Error(`cannot encode ${typeof v}`)
}

function fields(obj) {
  return Object.fromEntries(
    Object.entries(obj)
      .filter(([, v]) => v !== SERVER_TIME)
      .map(([k, v]) => [k, encode(v)]),
  )
}

/**
 * `auth` is a uid, 'owner' (bypasses rules, for seeding), or null (signed out).
 * Resolves to { ok, status, body } and never throws on a denied request.
 */
async function call(method, url, auth, body) {
  const headers = { 'Content-Type': 'application/json' }
  if (auth) headers.Authorization = `Bearer ${auth === 'owner' ? 'owner' : tokenFor(auth)}`
  const res = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined })
  const text = await res.text()
  return { ok: res.ok, status: res.status, body: text ? JSON.parse(text) : null }
}

/**
 * The client for one database of the emulator. The top-level exports below
 * are the `(default)` database.
 *
 * `node --test firestore-tests/` runs the test files in parallel, and each
 * file resets its database before every test. A file that shared a database
 * with another would have its seed wiped mid-test, so every file after the
 * first takes a database of its own: `forDatabase('memories-rules')`. The
 * rules apply to every database alike (`$(database)` is the one in use).
 */
export function forDatabase(database = '(default)') {
  const root = `projects/${PROJECT}/databases/${database}/documents`
  const base = `http://${HOST}/v1/${root}`

  function updateWrite(path, data, { mask = false, mustNotExist = false, mustExist = false } = {}) {
    const w = { update: { name: `${root}/${path}`, fields: fields(data) } }
    const transforms = Object.entries(data)
      .filter(([, v]) => v === SERVER_TIME)
      .map(([k]) => ({ fieldPath: k, setToServerValue: 'REQUEST_TIME' }))
    if (transforms.length) w.updateTransforms = transforms
    // Like the SDK's updateData: only the named fields change, and a field set
    // to the server time is carried by its transform, not by the mask.
    if (mask) w.updateMask = { fieldPaths: Object.keys(data).filter((k) => data[k] !== SERVER_TIME) }
    if (mustNotExist) w.currentDocument = { exists: false }
    if (mustExist) w.currentDocument = { exists: true }
    return w
  }

  /** Write builders for `commit` (one atomic batch, like WriteBatch). */
  const W = {
    set: (path, data) => updateWrite(path, data),
    create: (path, data) => updateWrite(path, data, { mustNotExist: true }),
    update: (path, data) => updateWrite(path, data, { mask: true, mustExist: true }),
    /**
     * Like the SDK's setData(data, merge: true): no precondition (a missing
     * document is created), and the mask is every key of `data` (except
     * SERVER_TIME ones, which ride on their transforms) plus `deleteFields`.
     * A masked field absent from `data` is removed, which is how
     * FieldValue.delete() reaches the server.
     */
    merge: (path, data, deleteFields = []) => {
      const both = deleteFields.filter((k) => Object.hasOwn(data, k))
      if (both.length) throw new Error(`W.merge: ${both.join(', ')} both set and deleted`)
      const w = updateWrite(path, data, { mask: true })
      w.updateMask.fieldPaths.push(...deleteFields)
      return w
    },
    del: (path) => ({ delete: `${root}/${path}` }),
  }

  const commit = (writes, auth) => call('POST', `${base}:commit`, auth, { writes })

  return {
    database,
    W,
    commit,
    setDoc: (path, data, auth) => commit([W.set(path, data)], auth),
    updateDoc: (path, data, auth) => commit([W.update(path, data)], auth),
    deleteDoc: (path, auth) => commit([W.del(path)], auth),
    getDoc: (path, auth) => call('GET', `${base}/${path}`, auth),
    /** A collection list is evaluated by the rules as a query (`allow list`). */
    listDocs: (collectionPath, auth) => call('GET', `${base}/${collectionPath}`, auth),
    /** Deletes every document in this database (and only this one). */
    async reset() {
      const res = await fetch(
        `http://${HOST}/emulator/v1/projects/${PROJECT}/databases/${database}/documents`,
        { method: 'DELETE' },
      )
      if (!res.ok) throw new Error(`emulator reset failed: ${res.status}`)
    },
  }
}

const defaultDatabase = forDatabase()

/** Write builders for `commit` (one atomic batch, like WriteBatch). */
export const W = defaultDatabase.W
export const commit = defaultDatabase.commit
export const setDoc = defaultDatabase.setDoc
export const updateDoc = defaultDatabase.updateDoc
export const deleteDoc = defaultDatabase.deleteDoc
export const getDoc = defaultDatabase.getDoc
/** A collection list is evaluated by the rules as a query (`allow list`). */
export const listDocs = defaultDatabase.listDocs
/** Deletes every document in the emulator's `(default)` database. */
export const reset = defaultDatabase.reset

/** Decodes a REST document's field into plain JS (enough for assertions). */
export function value(doc, name) {
  const f = doc?.fields?.[name]
  if (!f) return undefined
  if ('stringValue' in f) return f.stringValue
  if ('integerValue' in f) return Number(f.integerValue)
  if ('doubleValue' in f) return f.doubleValue
  if ('booleanValue' in f) return f.booleanValue
  if ('timestampValue' in f) return new Date(f.timestampValue)
  if ('nullValue' in f) return null
  return f
}
