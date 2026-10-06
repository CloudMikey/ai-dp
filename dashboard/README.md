# AI-DP Analytics Dashboard

A lightweight analytics dashboard built with vanilla HTML, CSS, and JavaScript that visualizes
sentiment-analysis results from the AI-DP pipeline. It runs entirely in the browser (no backend, no
build step) and talks directly to AWS via the AWS SDK for JavaScript.

## Architecture

The dashboard reads from two of the pipeline's storage layers: a **pre-aggregated summary** in the
data lake for the totals and chart, and the **hot store** for recent records:

| Data Source | What it powers | How it's read |
|-------------|----------------|---------------|
| **S3 curated layer** (`curated/latest_summary.json`) | Metric cards + "Top Entities Detected" chart | `GetObject` of a pre-aggregated JSON file |
| **DynamoDB** (`ai-dp-dev-enriched-data`) | Recent Events table | `Query` on the `timestamp-index` GSI, newest first (limit 50) |
| **Kinesis** (`ai-dp-dev-ingestion-stream`) | "Send Test Event" button | `PutRecord` into the ingestion stream |

> **Note on historical analytics:** Athena + Glue exist in this project as the **cold / historical
> query path** over the S3 data lake's `processed/` layer, but they are queried **manually via the
> AWS console / CLI** — the dashboard does **not** call Athena. The chart uses the pre-aggregated
> S3 summary instead, which loads in ~100 ms versus paying Athena query latency and cost on every
> page view.

## Features & Functionality

### 1. Sentiment Metric Cards (S3 curated summary)
- **Total Records**: `total_records` from the summary, a count of every record the pipeline has processed
- **Sentiment breakdown**: POSITIVE, NEUTRAL, NEGATIVE, MIXED from `sentiment_counts`, which sum to the total
- **Color-coded cards** for each sentiment category

### 2. Top Entities Detected (S3 curated summary)
- **Doughnut chart** (Chart.js) of the most frequently detected entities
- Data comes from `curated/latest_summary.json` (`top_entities`), which the **Merge Lambda
  pre-aggregates** on each run — no SQL, no query latency
- Legend shows each entity with its count (e.g. "AWS: 12")

### 3. Recent Events Table (DynamoDB)
- **Up to 20 most recent records**, sorted by timestamp (newest first)
- Columns:
  - **Time**: local timestamp
  - **Sentiment**: color-coded badge
  - **Confidence**: `sentimentScore` as a percentage (e.g. "99.0%")
  - **Text**: the first 500 characters of the review, truncated in the cell; hover for the full preview
  - **Entities**: up to 4 entity badges with a "+N" overflow indicator
- Junk "entities" that Comprehend misidentifies (timestamps, time strings) are filtered out before
  display, and all entity text is HTML-escaped to prevent injection

### 4. Send Test Event (Kinesis)
- The **Send Test Event** button writes a sample record **directly to Kinesis** (`PutRecord`) — the
  same entry point as API Gateway, bypassing HTTP to avoid browser CORS
- After ~10–30s (ETL → Comprehend → Merge), the new event appears in the table on the next refresh
- Great for demoing the live pipeline end-to-end

### 5. User Experience
- **Auto-refresh** every 60 seconds, plus a manual **Refresh** button
- **Loading states** while fetching, and per-widget **error handling** so a failure in one source
  doesn't blank the whole page
- **Last updated** timestamp in the footer

## Files

```
dashboard/
├── index.html    # Page structure
├── styles.css    # Styling (colors, layout, responsive)
├── app.js        # AWS SDK calls, data fetching, chart + table rendering
├── config.js     # AWS credentials + resource names (DO NOT COMMIT — gitignored)
└── README.md     # This file
```

## Setup Instructions

### Step 1: Configure AWS Credentials

Create `config.js` with your AWS credentials and resource names:

```javascript
const CONFIG = {
    // AWS Region
    AWS_REGION: 'us-west-2',

    // Your AWS Access Key ID
    AWS_ACCESS_KEY_ID: 'YOUR_ACCESS_KEY_HERE',

    // Your AWS Secret Access Key
    AWS_SECRET_ACCESS_KEY: 'YOUR_SECRET_KEY_HERE',

    // DynamoDB hot store (metric cards + recent events)
    DYNAMODB_TABLE: 'ai-dp-dev-enriched-data',

    // S3 data lake (curated/latest_summary.json powers the Top Entities chart)
    DATA_LAKE_BUCKET: 'ai-dp-data-lake-dev-us-west-2',

    // Kinesis ingestion stream ("Send Test Event" button)
    KINESIS_STREAM: 'ai-dp-dev-ingestion-stream'
};
```

### Step 2: IAM Permissions Required

The credentials in `config.js` need these permissions:

**DynamoDB:**
- `dynamodb:Query` on `ai-dp-dev-enriched-data/index/timestamp-index`

**S3 (for the metric cards and Top Entities chart):**
- `s3:GetObject` on the data lake bucket (`curated/latest_summary.json`)

**Kinesis (for the "Send Test Event" button):**
- `kinesis:PutRecord` on `ai-dp-dev-ingestion-stream`

### Step 3: Open the Dashboard

Open `index.html` in your web browser:

```bash
# Windows
start index.html

# Mac
open index.html

# Linux
xdg-open index.html
```

### Step 4: Check the Browser Console

Press `F12` and open the Console tab:
- You should see "AI-DP Dashboard loaded" and per-source load logs
- Any errors (credentials, permissions, CORS) appear here

## How It Works

### Data Flow

1. **Page load** triggers `loadData()`, which runs two operations in parallel (`Promise.all`):
   - `loadDynamoDBData()` — queries the `timestamp-index` GSI for the 50 newest records, filters out
     metadata records, then fills the Recent Events table
   - `loadCuratedSummary()` — fetches `curated/latest_summary.json` from S3, then updates the metric
     cards and renders the Top Entities doughnut chart
2. **Auto-refresh** re-runs `loadData()` every 60 seconds; the **Refresh** button runs it on demand.
3. **Send Test Event** is independent: it `PutRecord`s a sample payload to Kinesis and the result
   shows up in the table after the pipeline processes it.

### Fallback Behavior

- If the DynamoDB query fails, the table shows an error and the cards and chart still render (and vice versa) —
  the two sources fail independently.
- If `curated/latest_summary.json` doesn't exist yet (e.g. before the Merge Lambda has run), the
  chart shows "Curated summary not available" instead of breaking the page.

## Customization

### Auto-refresh interval
Edit the `setInterval(...)` call at the bottom of `app.js` (currently `60000` ms).

### Number of table rows
Edit `sorted.slice(0, 20)` in `updateTable()` in `app.js`.

### Colors
- Metric card colors: `styles.css`
- Sentiment badge colors: `styles.css`
- Chart palette: the `colors` array in `updateEntitiesChart()` in `app.js`

## Troubleshooting

### "Failed to load recent events from DynamoDB"
- Check the credentials in `config.js`
- Verify `DYNAMODB_TABLE` matches your deployed table
- Ensure the IAM user has `dynamodb:Query` on the `timestamp-index` GSI

### "Curated summary not available" (chart empty)
- The Merge Lambda writes `curated/latest_summary.json` on each run — send some data through the
  pipeline first (e.g. the **Send Test Event** button), then refresh
- Verify `DATA_LAKE_BUCKET` is correct and the IAM user has `s3:GetObject`

### "Send Test Event" fails
- Ensure the IAM user has `kinesis:PutRecord` on `ai-dp-dev-ingestion-stream`
- Check `KINESIS_STREAM` in `config.js`

### CORS errors
- Expected when calling AWS APIs directly from a local `file://` page
- Workaround: serve the folder from a local web server, or deploy to S3 static hosting

## Security Notes

**LOCAL DEMO ONLY — NOT FOR PRODUCTION**

This dashboard uses static AWS credentials in `config.js` for **local demonstration only**.

**Why this is acceptable for a portfolio demo:**
- Runs only on your local machine
- `config.js` is in `.gitignore` and is never committed
- Fine for demos, screenshots, and portfolio videos

**For production, you would instead use:**
- AWS Cognito Identity Pools (temporary, scoped browser credentials)
- A backend API (Lambda + API Gateway) so the browser holds no credentials
- IAM roles for hosted applications

## Data Schema

### DynamoDB Record Structure

```json
{
  "recordId": "2026-01-15T12:00:00Z-abc12345",
  "timestamp": 1736942400000,
  "recordType": "text",
  "sentiment": "POSITIVE",
  "sentimentScore": 0.9876,
  "entities": ["AWS", "Lambda", "Terraform"],
  "rawDataLocation": "s3://ai-dp-data-lake-dev-us-west-2/raw/...",
  "processedDataLocation": "s3://ai-dp-data-lake-dev-us-west-2/processed/...",
  "mergedAt": "2026-01-15T12:00:05.123Z",
  "expiresAt": 1739534400
}
```

### Curated Summary (`curated/latest_summary.json`)

Pre-aggregated by the Merge Lambda on each run. The dashboard reads `total_records` and
`sentiment_counts` (cards) and `top_entities` (chart); the other fields are unused:

```json
{
  "sentiment_counts": { "POSITIVE": 0, "NEGATIVE": 0, "NEUTRAL": 0, "MIXED": 0 },
  "total_records": 123,
  "top_entities": { "AWS": 12, "Lambda": 9, "Terraform": 7 },
  "first_record_at": "2026-01-15T12:00:05.123Z",
  "last_updated": "2026-01-15T12:30:05.456Z",
  "latest_sentiment": "POSITIVE",
  "latest_confidence": 0.9876,
  "latest_text_preview": "..."
}
```
