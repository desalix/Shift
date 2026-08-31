# Shift — Data Model v1

> Draft for review. Based on Shift.md + clarifications.
> Stack: Swift, SwiftUI, SwiftData (+ CloudKit for sync).

---

## 1. Entities

### Event

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | auto | PK |
| `title` | String | ✅ | |
| `type` | EventType | ✅ | .work, .school, .calendar |
| `startDate` | Date | ✅ | |
| `endDate` | Date | ✅ | |
| `address` | String? | conditional | Required for work and calendar events if the event has a location |
| `compensationType` | CompensationType? | conditional | Required for work; not applicable elsewhere |
| `hourlyRateCents` | Int? | conditional | Required when work + `.hourly` |
| `fixedRateCents` | Int? | conditional | Required when work + `.fixed` |
| `schoolKind` | SchoolEventKind? | conditional | Required for school events |
| `notes` | String? | ❌ | Max 250 chars |
| `color` | String? | ❌ | Override; falls back to type color from settings |
| `isRecurring` | Bool | default false | Simple weekly recurrence |
| `recurrenceID` | UUID? | conditional | Shared by every occurrence in one native weekly series |
| `recurringWeekdays` | [Int]? | ❌ | 1=Sun … 7=Sat. Only when isRecurring=true |
| `recurringEndDate` | Date? | ❌ | When isRecurring=true |
| `createdAt` | Date | auto | |
| `updatedAt` | Date | auto | |

**Relationships**:
- `preset` → Preset? (optional — which preset was used, if any)
- `subject` → Subject? (required for school events; not applicable elsewhere)

**Recurring logic (native)**:
- Simple weekly repeat: create individual event instances until recurringEndDate and link them with a `recurrenceID` UUID. Editing or deleting a series operates on that explicit group.
- In the monthly calendar view, recurring events show a **"Rec" label** at the top-right of the event card.
- Complex recurrence (skip weeks, skip holidays, etc.) is handled by the AI expanding into individual events — not native.

### Preset

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | auto | PK |
| `name` | String | ✅ | User-facing label |
| `type` | EventType | ✅ | .work, .school, .calendar |
| `title` | String? | ❌ | Default title for the event |
| `compensationType` | CompensationType? | ❌ | Work only |
| `hourlyRateCents` | Int? | ❌ | Work + hourly only |
| `fixedRateCents` | Int? | ❌ | Work + fixed only |
| `schoolKind` | SchoolEventKind? | ❌ | School only |
| `subject` | Subject? | ❌ | School only |
| `address` | String? | ❌ | Work & calendar only |
| `notes` | String? | ❌ | |
| `color` | String? | ❌ | |
| `createdAt` | Date | auto | |

### Subject

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | auto | PK |
| `name` | String | ✅ | |
| `color` | String? | ❌ | |
| `createdAt` | Date | auto | |

**Relationships**:
- `events` → [Event] (inverse: events where type = .school and subject = this)

**Deletion**: Deleting a Subject deletes all its linked Events (cascade). Shows confirmation alert.

### AiUsageRecord (local display cache only)

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | UUID | auto | PK |
| `date` | Date | ✅ | When the call happened |
| `inputTokens` | Int | ✅ | |
| `outputTokens` | Int | ✅ | |
| `cachedInputTokens` | Int | default 0 | |
| `cacheCreationTokens` | Int | default 0 | Cache-write tokens charged by provider |
| `costMicrodollars` | Int | ✅ | Computed server charge; never a floating-point value |
| `requestID` | UUID | ✅ | Idempotency key from the server |
| `status` | String | ✅ | reserved / completed / released |

> The server ledger is the enforcement source of truth. This local record is a synced display cache only. When offline or out of sync, the app must not grant new paid AI usage.

### AppSettings (singleton, stored in UserDefaults + CloudKit NSUbiquitousKeyValueStore for simple sync)

| Key | Type | Default | Notes |
|---|---|---|---|
| `accentColor` | String | `"blue"` | Apple system blue |
| `workColor` | String | `"blue"` | |
| `schoolColor` | String | `"green"` | |
| `calendarColor` | String | `"gray"` | |
| `schoolEnabled` | Bool | `false` | |
| `language` | String | `"en"` | |
| `subscriptionTier` | String? | `nil` | Server-entitlement display cache; never authorization |
| `aiEnabled` | Bool | `false` | Server-entitlement display cache; never authorization |

---

## 2. Enums

```swift
enum EventType: String, Codable, CaseIterable {
    case work
    case school
    case calendar
}

enum CompensationType: String, Codable {
    case hourly
    case fixed
}

enum SchoolEventKind: String, Codable, CaseIterable {
    case exam
    case assignment
    case other
}

enum SubscriptionTier: String, Codable {
    case monthly10 = "monthly_10"
    case monthly20 = "monthly_20"
    case payPerUse = "api"
}
```

---

## 3. Token Budgets and Cost Control

**Claude Haiku 4.5 pricing**:
- Input (standard): $1.00 / 1M tokens
- Output (standard): $5.00 / 1M tokens
- 5-minute cache write: $1.25 / 1M tokens
- 1-hour cache write: $2.00 / 1M tokens
- Cache read: $0.10 / 1M tokens
- Batch input/output: $0.50 / $2.50

> Rates and model IDs are server configuration, not app constants. Review them before each release and whenever the provider changes pricing.

**Plan budgets**:

| Plan | Initial hard model-cost ceiling | ≈ exchanges/mo (500 in + 300 out, no cache writes) |
|---|---|---|
| $10/mo | **$7.00** | ~3,500 |
| $20/mo | **$12.00** | ~6,000 |

**Cost per exchange** (no caching):
`(500×1 + 300×5) / 1,000,000 = $0.002`

**Usage windows** (scaled proportionally to AI budget):

| Window | $10 plan cap | $20 plan cap | Purpose |
|---|---|---|---|
| Per 3-hour session | $0.49 | $0.84 | Prevents binge |
| Per day | $1.05 | $1.80 | Smooths across week |
| Per month (hard ceiling) | $7.00 | $12.00 | Never reserve above this amount |
| Reservation headroom | Provider/model dependent | Provider/model dependent | Protects an in-flight worst-case request |

**Formula (same for both tiers)**:
```
estimated_cost = standard_input + cache_writes + cache_reads + max_output + enabled_tool_charges
reserve atomically if (completed_cost + reserved_cost + estimated_cost) ≤ plan_hard_ceiling
settle actual cost idempotently; release unused reservation
```

**Enforcement**: server-side only. A subscription’s server ledger records completed and reserved spend in integer units; a database transaction performs the reservation. The local cache may show usage but must never authorize a request. SQLite is acceptable for one low-traffic VM only; move this ledger to PostgreSQL before concurrent production traffic.

---

## 4. Proxy Architecture (recommended)

**Initial stage** (Debian ARM64 VM on an Apple-silicon Mac, dev/early launch):

```
[iOS App] ←→ [Cloudflare Tunnel] ←→ [FastAPI Proxy in Linux VM] ←→ [Anthropic API]
                                          ↓
                                     [SQLite DB] — user tokens, usage records, caps
```

- **Stack**: Python FastAPI (free, lightweight, easy to deploy)
- **Identity and auth**: one server account per person, created through a deliberate account flow (for example Sign in with Apple). Each device receives a revocable, short-lived access token stored in Keychain. A random per-install UUID is not sufficient because it cannot safely unify a subscription across devices.
- **Entitlements**: StoreKit 2 signed transactions are verified server-side; App Store Server Notifications keep refunds, renewals, and revocations current. The server binds a subscription to the server account, never to a client-selected plan string.
- **Tracking**: Every AI call carries an idempotency key. The proxy reserves worst-case spend atomically before forwarding, settles the provider-reported cost afterwards, and checks session, daily, and monthly windows.
- **Deployment**: systemd inside the Debian VM. Can migrate to a $5-10 VPS later while retaining the same proxy architecture.

**Why FastAPI over alternatives**:
- Free (no external infra cost)
- SQLite = no separate DB server for a single-user/dev VM; PostgreSQL is required before concurrent production usage
- Runs in a native ARM Linux VM on Apple silicon
- Easy to containerize when migrating

---

## 5. Subscription & StoreKit

- **Products**: two auto-renewable subscriptions ($9.99 and $19.99 are placeholders until pricing is approved) and non-expiring consumable credits for pay-per-use AI. All purchases that unlock in-app AI functionality use StoreKit In-App Purchase.
- **Upgrade**: StoreKit supports **prorated upgrades** — Apple handles the math. The user gets immediate access to the higher tier.
- **Downgrade**: Takes effect at next billing cycle.
- **Transaction validation**: use StoreKit 2 JWS transactions and the App Store Server API/Notifications; do not build new work on the deprecated receipt-validation API.

---

## 6. Sync Architecture

- **SwiftData + CloudKit**: Use `ModelContainer` with CloudKit configuration.
- **Settings**: Use `NSUbiquitousKeyValueStore` for simple key-value sync across devices.
- **Conflict resolution**: Last-write-wins (sufficient for 1-user personal app).

---

## 7. Security

- **Tokens**: per-device, revocable access/refresh tokens stored in Keychain; rotate and revoke on suspicious activity.
- **Purchases**: StoreKit 2 JWS transaction verification on the proxy plus App Store Server Notifications.
- **AI proxy**: rate-limited per account and IP, atomically cost-reserved, request-size limited, and audited. The client never supplies a privileged system prompt, model name, plan, or price.
- **Tools/actions**: the model proposes typed calendar/settings mutations; the server validates them against the schema and the client shows a confirmation before applying destructive actions. Never execute model text as code or database queries.
- **Files**: accept only required formats, enforce small size/page limits, malware-scan where applicable, store encrypted with a retention/deletion policy, and do not place uploads in model prompts without explicit user action.
- **No credit card handling**: Apple handles in-app payments through StoreKit.
- **Privacy**: publish a privacy policy and in-app deletion/export path before collecting schedules, school data, or uploaded documents.
- **HTTPS-only**: Proxy endpoint requires TLS (Let's Encrypt for self-hosted, or Cloudflare tunnel)

---

## Next Steps

1. ✅ Review this model
2. I'll create the Xcode project with the SwiftData models
3. Then build views one by one
