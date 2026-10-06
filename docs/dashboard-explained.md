# How the Dashboard Works

A plain-language walkthrough of `dashboard/` — what it shows, where each number comes from, and why it was built this way.

---

## The one-sentence version

**It is three static files with no backend.** The browser itself is the client, calling AWS directly with the JavaScript SDK. Open `index.html` from disk and it works — there is no server to start.

---

## The files

```
dashboard/
├── index.html   the empty skeleton — boxes with IDs, no data
├── config.js    the address book (region, table, bucket, stream) + credentials
├── app.js       the engine — fetches from AWS, fills in the boxes
└── styles.css   appearance only
```

`index.html` contains no data at all. Every number starts as a literal dash:

```html
<h3 id="total-records">-</h3>
<canvas id="entities-chart"></canvas>
<tbody id="events-tbody">Loading...</tbody>
```

Those `id` attributes are the contract. `app.js` finds each one and swaps in real data. Open the page with the network disconnected and you see exactly those dashes — proof the HTML carries nothing.

---

## Three widgets, two data sources

```
   ┌─────────────────────────┐         ┌─────────────────────────┐
   │  ONE file in S3         │         │  DynamoDB table         │
   │  curated/               │         │  ai-dp-dev-enriched-    │
   │  latest_summary.json    │         │  data                   │
   └───────────┬─────────────┘         └───────────┬─────────────┘
               │                                   │
       ┌───────┴────────┐                          │
       ▼                ▼                          ▼
   Metric cards    Entities chart           Recent Events table
```

Both reads fire **in parallel**, so the page fills at the speed of the slower one rather than the sum:

```js
await Promise.all([ loadDynamoDBData(), loadCuratedSummary() ]);
```

---

## Source 1 — the curated summary (cards + chart)

One `getObject` pulls a single small JSON file that the **Merge Lambda already computed**:

```json
{
  "total_records": 26,
  "sentiment_counts": { "POSITIVE": 9, "NEUTRAL": 2, "NEGATIVE": 9, "MIXED": 6 },
  "top_entities": { "Seattle": 4, "Tesla": 2, "Comcast": 2 }
}
```

That one file feeds both widgets:

```
   latest_summary.json
         ├── total_records + sentiment_counts ──► the 5 metric cards
         └── top_entities ─────────────────────► the doughnut chart
```

The counting already happened at write time, inside the pipeline. The browser does no arithmetic — it reads finished numbers and prints them. That is why it responds in roughly 100 ms.

The numbers are also **self-consistent**: the sentiment counts sum to `total_records`. That matters. An earlier version tallied sentiments from a 50-row sample while showing a true total, so the cards could read "Total: 42" while the four sentiment counts summed to 50. Numbers that do not add up destroy trust in a dashboard faster than numbers that are missing.

---

## Source 2 — DynamoDB (the recent events table)

This widget needs *individual, current* records rather than an aggregate, so it queries the table directly:

```js
dynamoDB.query({
  IndexName: 'timestamp-index',
  KeyConditionExpression: 'recordType = :rt',
  ExpressionAttributeValues: { ':rt': 'text' },
  ScanIndexForward: false,     // newest first
  Limit: 50
})
```

### Why this is a `query` and not a `scan`

```
   scan  →  ┌───┬───┬───┬───┐   hash order — effectively random.
            │ ? │ ? │ ? │ ? │   Limit 50 grabs the first 50 it walks past,
            └───┴───┴───┴───┘   so new records may NEVER appear.

   query →  ┌───┬───┬───┬───┐   sorted by timestamp, descending.
   on GSI   │now│-1m│-5m│-1h│   Limit 50 = genuinely the newest 50.
            └───┴───┴───┴───┘
```

The `timestamp-index` GSI uses `recordType` as its partition key and `timestamp` as its sort key. Every record shares `recordType='text'`, so they all land in one partition, pre-sorted by time. Read it backwards with `ScanIndexForward: false` and you have "newest N" as a cheap, correct operation.

A plain `scan` returned hash-ordered results, capped at the page size, and never surfaced new records — it could not power a "recent events" view at all.

### The five columns

| Column | Source |
|--------|--------|
| Time | `item.timestamp`, epoch milliseconds → `toLocaleString()` |
| Sentiment | `item.sentiment`, styled by a CSS class |
| Confidence | `item.sentimentScore` × 100, one decimal |
| Text | `item.textPreview`, truncated by CSS, full text on hover via `title` |
| Entities | `item.entities`, first 4 as badges, then `+N` |

The Text column truncates visually with an ellipsis and shows the complete preview in a native browser tooltip on hover. Both the visible text and the tooltip run through `escapeHtml()` — the sample data contains apostrophes (`O'Hare`, `I'm`) that would otherwise break the HTML attribute.

The table renders at most 20 rows even though the query returns 50. It is a live feed, not a data browser.

---

## The Send Test Event button

This is the one control that pushes data **into** the system, and it deliberately enters through the same door as production traffic:

```
   [Send Test Event]
          │  kinesis.putRecord()  — the button's job ends here, ~200 ms
          ▼
   ┌──────────────┐
   │   Kinesis    │  ◄── API Gateway writes to this same stream
   └──────┬───────┘
          ▼
     ETL Lambda ──────────────► S3 raw/
          ▼
     EventBridge
          ▼
   Step Functions ──► Comprehend (sentiment + entities, in parallel)
          ▼
     Merge Lambda
       ╱       ╲
  DynamoDB   S3 processed/ + curated/
      │            │
      └─► ~5-30s ──┘
             ▼
        [Refresh] → the row appears
```

It calls Kinesis directly rather than going through API Gateway. Both paths make the identical `PutRecord` call — API Gateway uses an `AWS_PROXY` integration with subtype `Kinesis-PutRecord`, so there is no Lambda in between either way. Going direct avoids configuring CORS for a browser calling the API cross-origin.

**One click exercises the entire pipeline**: ingestion → ETL → orchestration → AI → dual storage → back to the screen. If the row appears, every component works.

The trade-off: it does **not** test API Gateway itself — its throttling, access logging, or the `X-Partition-Key` header mapping. A working button does not prove the public endpoint works. Test that separately with `curl`.

---

## When the page updates

```
   page load ──────────────► loadData()
   [Refresh] button ───────► loadData()
   every 60 seconds ───────► loadData()
```

Three triggers, one function — nothing is special-cased. There is no push mechanism; after sending a test event you either press Refresh or wait for the next automatic cycle.

---

## Why the design is split this way

Three possible read sources existed, and each widget got a deliberate choice:

| Widget | Source | Why not the others |
|--------|--------|--------------------|
| Cards + chart | S3 curated JSON | Pre-computed at write time. One small GET. Aggregating all history at read time would need a full scan or Athena. |
| Recent events | DynamoDB GSI | Needs individual, fresh records sorted by time — exactly what a hot store with a time-sorted index provides. |
| — | ~~Athena~~ | **Intentionally not wired in.** Seconds of latency and a per-query cost on every page view. |

That is the hot/cold split done properly: pre-aggregate what you display constantly, index what must be fresh, and reserve the SQL engine for questions you did not anticipate.

**Athena is the console-only cold path.** The answer to "why doesn't your dashboard use Athena?" is not that it could not — it is that a billed multi-second query per page load is the wrong tool for a number that does not change between refreshes.

---

## What the dashboard cannot show you

The dashboard is a **live-operations view**, and it is bounded in three independent ways:

```
   All records ever processed  (permanent in S3 processed/)
          │
          │  ① DynamoDB TTL deletes anything older than 30 days
          ▼
   Records in the hot store
          │
          │  ② query Limit: 50
          ▼
   50 returned
          │
          │  ③ .slice(0, 20) in the code
          ▼
   20 rows on screen
```

1. **TTL (30 days)** — every record carries an `expiresAt`; AWS deletes it automatically. The hot store is a rolling window, not an archive.
2. **`Limit: 50`** — the query ceiling.
3. **`.slice(0, 20)`** — the display ceiling.

The metric cards have a **different** limit: they read a running tally that only counts records written since the file was last created. Reset the summary and it starts from zero regardless of what is in DynamoDB.

None of this is a defect. S3 `processed/` keeps every record for a year (365-day lifecycle), and Athena queries that history. The dashboard answers *"what is happening lately"* — and answers it correctly.

---

## Known issues and design notes

**Credentials in `config.js`.** The dashboard authenticates with a static IAM access key embedded in client-side JavaScript. The file is gitignored and has never been committed, but the key currently belongs to a user with `AdministratorAccess` — far more than the three permissions the page actually needs (`kinesis:PutRecord`, `dynamodb:Query`, `s3:GetObject`). Production would use a Cognito Identity Pool or an API Gateway/Lambda proxy so the browser never holds credentials at all.

**Browser caching of the summary.** `s3.getObject` on `latest_summary.json` can be served from browser cache, so updates may need a hard reload (Ctrl+Shift+R). Adding `ResponseCacheControl: 'no-cache'` to the call would fix it.

**The summary is a derived artifact.** It is maintained incrementally by the Merge Lambda using a conditional write with retries (see [errorlog.md](errorlog.md) Error #6). If it ever drifts from DynamoDB, `scripts/rebuild_summary.py` recomputes it from scratch.

---

## Quick reference

| Question | Answer |
|----------|--------|
| Where do the metric cards come from? | `curated/latest_summary.json` in S3 |
| Where does the chart come from? | The same file — its `top_entities` field |
| Where does the table come from? | DynamoDB, via the `timestamp-index` GSI |
| Why not Athena? | Too slow and billed per query for a per-page-view read |
| Why only 20 rows? | `.slice(0, 20)` — it is a feed, not a browser |
| Why do old records vanish? | DynamoDB TTL, 30 days |
| Is anything lost when they vanish? | No — S3 `processed/` keeps everything |
| Does the table auto-update? | Every 60 seconds, or on Refresh |
| Is there a backend? | No. The browser calls AWS directly. |

---

## Related documentation

- [architecture.md](architecture.md) — the full pipeline, with diagrams
- [errorlog.md](errorlog.md) — Error #6 covers the summary's concurrency fix
- [test-data/batch/](../test-data/batch/) — sample `.txt` files for generating data to see on the dashboard
- [dashboard/README.md](../dashboard/README.md) — setup and configuration
