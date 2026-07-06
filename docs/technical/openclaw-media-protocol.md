# OpenClaw Media Delivery Protocol

**Version**: 2026-07-06 (snapshot against OpenClaw 2026.6.10 / aa69b12)
**Status**: Reference document — derived from OpenClaw dist/ source + empirical captures
**Audience**: Engineers integrating clients (webchat, mobile, custom UIs) with OpenClaw gateway

---

## 0. Scope & Non-Goals

This document describes the **media (image / audio / video / document) delivery protocol** for OpenClaw 2026.6.10.

**In scope**:
- File storage layout on the gateway
- Upload path: client → gateway → agent
- Send-back path: agent → gateway → client (MEDIA: directive + attachment blocks)
- HTTP endpoints exposed by the Control UI / Gateway for media fetch
- Authentication tickets for assistant-originated media
- Security headers and constraints
- Inbound message envelope (openclaw.inbound_meta.v2)
- Sender blocks injected by openclaw-android

**Out of scope** (separate docs needed):
- Session lifecycle, WebSocket transport framing, chat.send RPC schema
- Channel adapter internals (Telegram/Signal/Discord/etc. transport adapters)
- Plugin SDK, ACP bridge, ACP pairing protocol
- Cron / wake event payloads

For anything not covered here, see `docs/gateway/configuration.md` or the OpenClaw source.

---

## 1. Terminology

| Term | Meaning |
|---|---|
| **Gateway** | The OpenClaw server process hosting HTTP + WebSocket endpoints |
| **Agent** | The LLM runtime (a single Claude/MiniMax/etc. session bound to a session key) |
| **Channel** | The transport used to reach a human (webchat, openclaw-android, telegram, signal, …) |
| **Inbound media** | A file sent by the human (uploaded via any channel) |
| **Outbound media** | A file sent by the agent back to the human |
| **Media ID** | The on-disk filename for a stored media file (`{prefix}---{uuid}.{ext}`) |
| **MEDIA: directive** | The legacy text-based directive the agent emits to attach a file to its reply |
| **Attachment block** | The structured `{type: 'attachment', attachment: {...}}` content part |
| **mediaTicket** | A short-lived HMAC-signed ticket authorizing the client to fetch assistant media |

---

## 2. Media Storage Layout

### 2.1 Directory

All media goes through a single root:

```
${configDir}/media/      # default: /root/.openclaw/media/
├── inbound/             # files delivered INTO the gateway (from humans OR agent)
│   ├── attachment-1---{uuid}.jpg        # user upload (openclaw-android default name)
│   ├── 微信图片_20230514---{uuid}.jpg    # user upload (webchat keeps original name)
│   └── assistant-media---{uuid}.png     # agent-generated / agent-sent media
└── (other subdirs added by plugins)
```

### 2.2 File naming

Naming is produced by `buildSavedMediaId()` in `dist/store-C8gpb2Gk.js`:

```js
function buildSavedMediaId({ baseId, ext, originalFilename }) {
  if (!originalFilename) return ext ? `${baseId}${ext}` : baseId;
  const sanitized = sanitizeFilename(nameFromAnyPath(originalFilename));
  return sanitized ? `${sanitized}---${baseId}${ext}` : `${baseId}${ext}`;
}
```

| Component | Source |
|---|---|
| `baseId` | `crypto.randomUUID()` (v4) |
| `ext` | Detected via `detectMime()` + `extensionForMime()` |
| `originalFilename` | Client-supplied upload name; for assistant media, the literal string `"assistant-media"` |

### 2.3 Constraints

- Max file size: **`MEDIA_MAX_BYTES = 5 * 1024 * 1024`** (5 MB). Exceeding it throws.
- Mode: `MEDIA_FILE_MODE = 420` (octal, = `0o644`).
- Symlinks: refused by `assertLocalMediaAllowed`.
- Path traversal: validated by `resolveMediaRelativePath()` (no `/`, `\`, `\0`, or `..`).

### 2.4 Empirical observation: no content-addressable dedup

The gateway does **not deduplicate by content hash**. Empirically observed:

```
7b70f4fa9b2020ef90d65594ac25d086  attachment-1---dd897a3c-...jpg (Jul 6 20:01)
7b70f4fa9b2020ef90d65594ac25d086  attachment-1---22635d24-...jpg (Jul 4)
... (4 more copies across Jul 4-6)
```

Same MD5, different UUIDs, separate files. **Plan for storage growth**: clients that re-send the same image accumulate independent copies.

---

## 3. Upload Path: Human → Agent

### 3.1 Channel-specific upload conventions

The gateway ingests uploads via `chat.send` RPC (WebSocket) with `images: [{data, mimeType}]` payload. The Control UI / openclaw-android client is responsible for:

1. Reading the file as a Buffer (binary).
2. Base64-encoding it into the `images[].data` field.
3. Setting `images[].mimeType`.
4. Including `imageOrder: ['inline', ...]` when multiple images are sent.

### 3.2 Server-side processing

In `dist/chat-BmzuyR4R.js`:

```js
async function persistChatSendImages(params) {
  const inlineSaved = [];
  for (const img of params.images) {
    inlineSaved.push(
      await saveMediaBuffer(Buffer.from(img.data, "base64"), img.mimeType, "inbound")
    );
  }
  // ... merges with offloaded refs and imageOrder ...
}
```

`saveMediaBuffer()` writes to `media/inbound/` and returns a `SavedMedia { id, path, size, contentType }`. **No `originalFilename` is passed** for direct uploads, so the file ID is just `{uuid}{ext}` unless the caller sets it.

### 3.3 Agent's view: media reference

In the agent's context window, an inbound image appears as:

```jsonc
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/jpeg",
    "data": "<base64>"
  }
}
```

The agent does NOT directly see the on-disk path of inbound images. To produce a MEDIA: directive that round-trips the same bytes, the agent would have to save the base64 to disk itself first.

---

## 4. Send-Back Path: Agent → Human

### 4.1 The MEDIA: directive (legacy)

The agent emits a single line of text:

```
MEDIA:/absolute/path/to/file.ext
```

**Rules** (enforced by `dist/control-ui/assets/index-*.js`):
- Must start a line (after optional whitespace)
- One directive per line; multiple attachments = multiple lines
- Path can be absolute (`/...`), `file://...`, `~/...`, `./...`, or `..` (path-traversal-safe)
- URL-encoded paths via `media://inbound/<id>` are also accepted (canonical form)
- Backticks around the path are tolerated and stripped
- The directive **MUST NOT be wrapped** in markdown (`**`, backticks, etc.)

The gateway parses with:

```js
const MEDIA_TOKEN_RE = /\bMEDIA:\s*`?([^\n]+)`?/gi;
```

### 4.2 Transformation pipeline

1. **Strip**: the `MEDIA:` line is removed from the visible reply text.
2. **Resolve**: the path is mapped to a local file via `resolveMediaReferenceLocalPath()`.
3. **Classify**: by extension → `{kind: 'image'|'audio'|'video'|'document', label, mimeType}`.
4. **Emit**: as a structured attachment block:

```jsonc
{
  "type": "attachment",
  "attachment": {
    "url": "/__openclaw__/assistant-media?source=<urlencoded>&mediaTicket=v1.<sig>",
    "kind": "image",
    "label": "probe-1783347699.png",
    "mimeType": "image/png"
  }
}
```

(URL construction done in `qF()` in `control-ui/assets/index-*.js`.)

### 4.3 URL shape (the wire format you see in packet captures)

**Two endpoints the client uses**:

| Endpoint | Used for | Path |
|---|---|---|
| **Outgoing media** | The agent fetching a human's uploaded image | `/api/chat/media/outgoing/<media-id>` |
| **Assistant media** | The client rendering the agent's reply image | `/__openclaw__/assistant-media` |

---

## 5. Assistant Media Fetch Protocol

### 5.1 Endpoint

```
GET /__openclaw__/assistant-media?source=<urlencoded-path>[&meta=1][&token=<bearer>]
```

Only `GET` and `HEAD` are accepted (`isReadHttpMethod`). Anything else returns 405.

### 5.2 Authentication: `mediaTicket`

The client must prove it has a valid ticket for the requested `source` path.

**Ticket structure** (after `mediaTicket=v1.`):

```
v1.<base64url(payload)>.<base64url(hmac-sha256(payload, secret))>
```

**Payload** (JSON, base64url-encoded):

```json
{
  "scope": "assistant-media",
  "source": "/absolute/path/to/file.ext",
  "exp": 1783347900000
}
```

**HMAC signing**:

```js
const secret = randomBytes(32);            // regenerated per gateway startup
const sig    = createHmac("sha256", secret)
                 .update(encodedPayload)
                 .digest("base64url");
```

> ⚠️ **Important**: The HMAC secret is **per-process**, generated with `crypto.randomBytes(32)` at module load. Every gateway restart invalidates all outstanding tickets.

**TTL**: `CONTROL_UI_ASSISTANT_MEDIA_TICKET_TTL_MS = 300_000` → **5 minutes** from issuance.

**Verification**:

```js
function verifyAssistantMediaTicket(ticket, source) {
  const [v, payload, sig] = ticket.split(".");
  if (v !== "v1" || !payload || !sig) return false;
  const expected = signAssistantMediaTicketPayload(payload);
  if (!timingSafeEqual(Buffer.from(sig, "base64url"), Buffer.from(expected, "base64url")))
    return false;
  const decoded = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
  return decoded.scope === "assistant-media"
      && decoded.source === source
      && decoded.exp >= Date.now();
}
```

**Fallback auth**: if the ticket is invalid/missing, the endpoint falls back to `authorizeControlUiReadRequest` (Bearer token via `Authorization: Bearer <token>` header **or** `?token=<token>` query param).

### 5.3 The two-step flow

**Step 1: Availability check**

```
GET /__openclaw__/assistant-media?source=<urlencoded>&meta=1
→ 200 application/json:
{
  "available": true,
  "mediaTicket": "v1.<base64>.<sig>",
  "mediaTicketExpiresAt": "2026-07-06T22:26:39.000Z"
}
```

OR if unavailable:

```json
{ "available": false, "reason": "Attachment unavailable", "checkedAt": <epoch-ms> }
```

Possible `reason` values:
- `"Outside allowed folders"` — path outside agent's `mediaLocalRoots`
- `"Attachment unavailable"` — generic catch-all
- `MediaReferenceError.code` mappings: `invalid-path`, `not-file`, `path-mismatch`, `too-large`, `not-found`

**Step 2: Actual fetch**

```
GET /__openclaw__/assistant-media?source=<urlencoded>&mediaTicket=v1.<base64>.<sig>
→ 200 <mime-type>
   <binary bytes, streamed from disk>
```

### 5.4 Security headers (always applied)

```
X-Frame-Options: DENY
Content-Security-Policy: <from buildControlUiCspHeader()>
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
```

JSON responses additionally get `Content-Type: application/json; charset=utf-8`.

### 5.5 Allowed folders (path traversal protection)

Server resolves `source` via `resolveMediaReferenceLocalPath()` and checks against `getAgentScopedMediaLocalRoots(config, agentId)` (per-agent allowlist from gateway config). Default roots if unconfigured:

```
['~/.openclaw/media', '~/.openclaw/workspace-<agentId>', ...]
```

Symlinks are refused. `..` segments are normalized and re-checked.

---

## 6. Outgoing Media Fetch (Agent Reads User Upload)

### 6.1 Endpoint

```
GET /api/chat/media/outgoing/<urlencoded-media-id>
```

### 6.2 Authorization

Standard Control UI read auth: `Authorization: Bearer <token>` header **or** `?token=<token>` query. Same scope rules as the assistant-media endpoint (operator.read).

### 6.3 Response

```
200 <mime-type>
<binary bytes>
```

Same security headers as §5.4.

---

## 7. Inbound Message Envelope (openclaw.inbound_meta.v2)

Every inbound message from any channel carries a **trusted metadata envelope** generated by OpenClaw core (NOT by the client):

```json
{
  "schema": "openclaw.inbound_meta.v2",
  "channel": "webchat",
  "provider": "webchat",
  "surface": "webchat",
  "chat_type": "direct"
}
```

| Field | Meaning | Example values |
|---|---|---|
| `schema` | Schema version (constant `openclaw.inbound_meta.v2`) | |
| `channel` | Transport channel identifier | `webchat`, `telegram`, `signal`, `discord`, `slack`, `whatsapp`, `imessage`, `openclaw-android` (sometimes), … |
| `provider` | Underlying provider (usually = channel for direct adapters) | `webchat`, `telegram`, … |
| `surface` | UI surface | `webchat`, `mobile`, … |
| `chat_type` | Conversation topology | `direct`, `group`, `thread` |

**Trust level**: this block is **trusted**. It is injected at the prompt level by OpenClaw core, not by the user. Treat channel/surface as authoritative routing metadata.

> ⚠️ **Note**: `channel: webchat` does NOT mean "browser webchat client". openclaw-android also produces `channel: webchat` in some versions because it reuses the webchat namespace. To disambiguate, cross-reference with the **Sender block** (§8).

---

## 8. Sender Blocks (openclaw-android auto-injection)

openclaw-android **automatically prepends** a `Sender (untrusted metadata):` block to every outbound message. This is client-side metadata produced by the app, NOT user input.

**Format**:

```
Sender (untrusted metadata):
{
  "label": "<name> (openclaw-android)",
  "id": "openclaw-android",
  "name": "<name>",
  "username": "<name>"
}
```

**Trust level**: semi-trusted (more trusted than user chat content, less trusted than `inbound_meta.v2`). The label `"untrusted"` refers to trust relative to the OpenClaw envelope, **not** to authorship — the user did NOT type this block.

### 8.1 Cross-validation: who actually sent this message?

| Inbound source | `channel` field | `id` field | Use as authoritative? |
|---|---|---|---|
| Browser webchat | `webchat` | (none / user-typed) | Yes |
| openclaw-android | `webchat` (sometimes) | `openclaw-android` | Yes (use `id`) |
| Telegram / Signal / etc. | `<channel>` | varies | Yes (use `channel`) |

**Rule of thumb**: when ambiguous, trust the **Sender block `id`** over the `inbound_meta.v2.channel` field.

---

## 9. Worked Example: Image Round-Trip (Probe)

**Scenario**: a controlled probe where Atlas generates a fresh image and sends it back via MEDIA: directive.

**Generated file**:
- Path: `/root/.openclaw/workspace-<agentId>/probes/probe-1783347699.png`
- Size: 5429 bytes
- MD5: `2b010520718cfc91ea72560049d3ae0b`
- Content: dark-navy 1200×500 PNG with timestamp text

**Atlas emits**:

```
MEDIA:/root/.openclaw/workspace-agent_cfc70b81/probes/probe-1783347699.png
```

**Expected packet capture**:

```
T+0.0s   GET /__openclaw__/assistant-media?source=...probe-1783347699.png&meta=1
         ← 200 application/json
            {"available":true,
             "mediaTicket":"v1.<base64>.<sig>",
             "mediaTicketExpiresAt":"2026-07-06T22:26:39.000Z"}

T+0.05s  GET /__openclaw__/assistant-media
            ?source=...probe-1783347699.png
            &mediaTicket=v1.<base64>.<sig>
         ← 200 image/png, 5429 bytes, MD5=2b010520718cfc91ea72560049d3ae0b
         (Headers: X-Frame-Options: DENY, X-Content-Type-Options: nosniff,
                   Content-Security-Policy: ..., Referrer-Policy: no-referrer)
```

---

## 10. Edge Cases & Known Quirks

| Issue | Workaround / Note |
|---|---|
| No content-addressable dedup | Same image re-uploaded N times → N copies in `media/inbound/`. Storage grows linearly. |
| `attachment-1.jpg` is the default openclaw-android upload name | If you upload N images at once, you get `attachment-1`, `attachment-2`, … |
| Multi-image upload via openclaw-android can drop extras | Only 1 of N selected images actually reaches the gateway (verified empirically 2026-07-06). |
| `/status` and similar slash commands are NOT parsed by openclaw-android | They arrive as literal text. Agents must invoke tools manually. |
| `mediaTicket` secret rotates per gateway restart | Clients must re-fetch via `?meta=1` after gateway restart, even if TTL hasn't elapsed. |
| `mediaTicket` expires after 5 min | Long-lived client caches must invalidate on 401/403 from the assistant-media endpoint. |
| Symlink paths are refused for assistant media | Don't try to be clever with symlinks — use real files. |
| `MEDIA:` directive can't be inside a markdown code fence | The directive is consumed by the parser regardless of fence context; escape with leading backticks or place outside any fence. |
| `media://inbound/<id>` form is the canonical reference | Both this and absolute filesystem paths work; the former is preferred for portability. |

---

## 11. Reference Source Locations

All findings above were extracted from these files under `/www/server/nodejs/v24.16.0/lib/node_modules/openclaw/dist/`:

| Topic | File | Function |
|---|---|---|
| MEDIA: parsing | `control-ui/assets/index-BEWaPr0D.js` | `pA`, `Rk`, `tA` |
| Attachment emission | `control-ui/assets/index-BEWaPr0D.js` | `TA` |
| Assistant-media endpoint | `control-ui-B471pQxO.js` | `handleControlUiAssistantMediaRequest` |
| Ticket creation / verification | `control-ui-B471pQxO.js` | `createAssistantMediaTicket`, `verifyAssistantMediaTicket`, `signAssistantMediaTicketPayload` |
| Media storage | `store-C8gpb2Gk.js` | `saveMediaBuffer`, `saveMediaStream`, `buildSavedMediaId`, `resolveMediaBufferPath` |
| Chat upload | `chat-BmzuyR4R.js` | `persistChatSendImages` |
| Local path resolution | `media-reference-DBsCyVgf.js` | `normalizeMediaReferenceSource`, `classifyMediaReferenceSource`, `resolveMediaReferenceLocalPath` |
| Security headers | `control-ui-B471pQxO.js` | `applyControlUiSecurityHeaders`, `buildControlUiCspHeader` |
| Request routing | `server.impl-DCXuyKYo.js` | `requestStages[].name === "control-ui-assistant-media"` |

---

## 12. Open Questions / TODO

1. **How does openclaw-android decide `originalFilename: 'attachment-N'` vs webchat keeping the real filename?** Probably client-side; needs source review of the Android client repo (not in this gateway dist).
2. **What is the WebSocket frame format for `chat.send`?** Out of scope here; see session/transport docs.
3. **Why does the same MD5 file accumulate 6+ copies?** Suspected: gateway has no content-hash dedup at storage layer; each upload is independent.
4. **Is there a server-side cap on total `inbound/` size?** Not found in code; empirical only.
5. **Behavior when `MEDIA:` directive points to a path outside `mediaLocalRoots`?** Returns `{"available":false,"reason":"Outside allowed folders"}` on meta; 404 (or auth fail) on direct fetch.

---

*Document generated by Atlas on 2026-07-06 22:25 CST. Snapshot against OpenClaw 2026.6.10 (aa69b12). For corrections / additions, update this file in the workspace and re-distribute.*