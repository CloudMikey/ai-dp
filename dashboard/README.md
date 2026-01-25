# AI-DP Analytics Dashboard

A dual-query dashboard built with vanilla HTML, CSS, and JavaScript that visualizes sentiment analysis data from the AI-DP pipeline.

## Architecture

This dashboard implements the **dual-query strategy** from the AI-DP architecture:

| Data Source | Use Case | Features |
|-------------|----------|----------|
| **DynamoDB** | Real-time (last 30 days) | Metrics cards, Recent events table |
| **Athena** | Historical (all data) | Sentiment distribution, Entity type analysis, Total processed count |
| **SQS** | Pipeline health | DLQ message count (optional) |

## Features & Functionality

### 1. Real-Time Metrics (DynamoDB)
- **Total Records**: Count of records in hot store (last 30 days with TTL)
- **Sentiment Breakdown**: POSITIVE, NEUTRAL, NEGATIVE, MIXED counts
- **Color-coded Cards**: Visual indicators for each sentiment category
- **Live Updates**: Auto-refresh every 60 seconds

### 2. Pipeline Status Monitoring
- **Total Processed**: All-time count from Athena historical data
- **Last Record Time**: Time ago format (e.g., "5m ago", "2h ago") from most recent DynamoDB record
- **Pipeline Health**:
  - Healthy (green) - 0 DLQ messages
  - Warning (orange) - 1-10 DLQ messages
  - Degraded (red) - 10+ DLQ messages
- **DLQ Message Count**: Dead letter queue depth for error monitoring (optional, requires SQS permissions)

### 3. Sentiment Distribution Chart (Athena)
- **Pie chart** showing historical sentiment breakdown across all processed data
- **SQL aggregation** using Athena for scalable analytics
- **Query**: `SELECT sentiment, COUNT(*) FROM processed GROUP BY sentiment`
- Shows exact counts in legend (e.g., "Positive: 150")

### 4. Entity Type Analysis (Athena)
- **Doughnut chart** visualizing entity types detected by AWS Comprehend
- **Entity types tracked**:
  - ORGANIZATION (blue) - Companies, government agencies
  - PERSON (pink) - People names
  - LOCATION (green) - Cities, countries, landmarks
  - DATE (orange) - Dates and times
  - QUANTITY (indigo) - Numbers and measurements
  - TITLE (purple) - Job titles, document titles
  - COMMERCIAL_ITEM (teal) - Products and brands
  - EVENT (orange-red) - Events and occasions
  - OTHER (gray) - Miscellaneous entities
- **SQL query**: Uses `CROSS JOIN UNNEST(entitydetails)` to flatten nested entity array

### 5. Recent Events Table (DynamoDB)
- **20 most recent records** sorted by timestamp (newest first)
- **Columns**:
  - **Time**: Local timestamp (e.g., "1/19/2026, 8:25:05 PM")
  - **Sentiment**: Color-coded badge (green/orange/red/purple)
  - **Confidence**: Percentage score (e.g., "99.0%")
  - **Entities**: Badges showing extracted entities
    - Shows up to 4 entities with "+N more" indicator
    - Clean badge UI with hover effects
- **Entity display**: Simple text badges (full entity type analysis available in chart)

### 6. User Experience
- **Auto-refresh**: Data reloads every 60 seconds automatically
- **Loading states**: Visual feedback while fetching from DynamoDB and Athena
- **Error handling**: Graceful fallback with error messages if queries fail
- **Responsive design**:
  - Desktop: 5-column metrics grid, side-by-side charts
  - Tablet: 3-column metrics, stacked charts
  - Mobile: 2-column metrics, vertical layout
- **Performance**: Parallel queries (DynamoDB + Athena run simultaneously)

## Files

```
dashboard/
├── index.html    # Main page structure
├── styles.css    # All styling (colors, layout, responsive)
├── app.js        # JavaScript (AWS SDK, data fetching, chart rendering)
├── config.js     # AWS credentials (DO NOT COMMIT!)
└── README.md     # This file
```

## Setup Instructions

### Step 1: Configure AWS Credentials

Create `config.js` with your AWS credentials:

```javascript
const CONFIG = {
    // AWS Region
    AWS_REGION: 'us-west-2',

    // Your AWS Access Key ID
    AWS_ACCESS_KEY_ID: 'YOUR_ACCESS_KEY_HERE',

    // Your AWS Secret Access Key
    AWS_SECRET_ACCESS_KEY: 'YOUR_SECRET_KEY_HERE',

    // DynamoDB Table Name (real-time data)
    DYNAMODB_TABLE: 'ai-dp-dev-enriched-data',

    // Athena Configuration (historical analytics)
    ATHENA_DATABASE: 'ai-dp-dev-analytics',
    ATHENA_TABLE: 'processed',
    ATHENA_WORKGROUP: 'ai-dp-dev-workgroup',
    ATHENA_OUTPUT_LOCATION: 's3://ai-dp-athena-results-dev-us-west-2/query-results/',

    // SQS DLQ URL (optional - for pipeline health monitoring)
    // Leave empty if you don't want to monitor DLQ
    DLQ_URL: ''  // e.g., 'https://sqs.us-west-2.amazonaws.com/123456789/ai-dp-dev-etl-dlq'
};
```

### Step 2: IAM Permissions Required

Your AWS credentials need these permissions:

**DynamoDB:**
- `dynamodb:Scan` on `ai-dp-dev-enriched-data`

**Athena:**
- `athena:StartQueryExecution`
- `athena:GetQueryExecution`
- `athena:GetQueryResults`

**S3 (for Athena results):**
- `s3:GetObject` on Athena results bucket
- `s3:PutObject` on Athena results bucket
- `s3:GetBucketLocation` on Athena results bucket

**Glue (for Athena catalog):**
- `glue:GetTable`
- `glue:GetDatabase`

**SQS (optional - for DLQ monitoring):**
- `sqs:GetQueueAttributes` on your DLQ (e.g., `ai-dp-dev-etl-dlq`)
- If you don't have SQS permissions, leave `DLQ_URL` empty - dashboard will skip DLQ checks

### Step 3: Open the Dashboard

Simply open `index.html` in your web browser:

```bash
# Windows
start index.html

# Mac
open index.html

# Linux
xdg-open index.html
```

### Step 4: Check Browser Console

Press `F12` to open Developer Tools and check the Console tab:
- Should see "AI-DP Dashboard loaded!"
- Should see DynamoDB and Athena query logs
- Any errors will appear here

## How It Works

### Data Flow

1. **Page Load**: Triggers `loadData()` which runs 3 parallel operations:
   - DynamoDB scan for recent events
   - Athena queries (sentiment + entities)
   - Pipeline status check (Athena count + SQS DLQ)

2. **DynamoDB Query**:
   - Scans hot store for up to 50 recent records
   - Updates metrics cards (Total, Positive, Neutral, Negative, Mixed)
   - Populates Recent Events table

3. **Athena Queries** (run in parallel):
   - **Sentiment aggregation**: Updates pie chart
   - **Entity type analysis**: Updates doughnut chart
   - **Total count**: For pipeline status card
   - Each query waits for completion (polling with 1s interval)

4. **Pipeline Status**:
   - Total processed from Athena COUNT query
   - Last record time from cached DynamoDB results
   - DLQ count from SQS (if configured)
   - Health status computed based on DLQ depth

5. **Auto-refresh**: Every 60 seconds, all queries run again

### Athena Queries

**Sentiment Distribution:**
```sql
SELECT sentiment, COUNT(*) as count
FROM "ai-dp-dev-analytics"."processed"
GROUP BY sentiment
```

**Entity Type Analysis:**
```sql
SELECT entity.Type as entity_type, COUNT(*) as count
FROM "ai-dp-dev-analytics"."processed"
CROSS JOIN UNNEST(entitydetails) AS t(entity)
GROUP BY entity.Type
ORDER BY count DESC
```

**Total Processed Count:**
```sql
SELECT COUNT(*) as total
FROM "ai-dp-dev-analytics"."processed"
```

### Fallback Behavior

If Athena queries fail:
- Error message shown in affected chart area
- DynamoDB data still displays normally
- Pipeline status shows "-" for total processed
- Check browser console for detailed error messages

## Customization

### Change Auto-refresh Interval

Edit `app.js` line ~420:
```javascript
}, 60000); // Change to desired milliseconds (e.g., 30000 for 30s)
```

### Change Number of Table Records

Edit `app.js` line ~305:
```javascript
const displayData = sortedData.slice(0, 20); // Change 20 to desired number
```

### Modify Colors

Edit `styles.css`:
- Lines 86-100: Metric card colors
- Lines 201-228: Sentiment badge colors
- Lines 240-252: Pie chart colors are in `app.js`

## Troubleshooting

### "Failed to load recent events from DynamoDB"
- Check AWS credentials in `config.js`
- Verify DynamoDB table name matches your deployed table
- Ensure IAM user has `dynamodb:Scan` permission

### "Athena query failed"
- Check Athena workgroup name in `config.js`
- Verify Glue database and table exist (run crawler first)
- Ensure IAM user has Athena and Glue permissions
- Check S3 results bucket exists and is accessible

### No data in pie chart
- Run the Glue Crawler to catalog data: `aws glue start-crawler --name ai-dp-dev-crawler`
- Wait for crawler to complete
- Refresh dashboard

### CORS errors
- This is expected when running locally with browser-based AWS SDK
- The dashboard uses direct AWS API calls which may be blocked by CORS
- Solution: Use a local web server or deploy to S3 static hosting

## Security Notes

**LOCAL DEMO ONLY - NOT FOR PRODUCTION**

This dashboard uses hardcoded AWS credentials for **local demonstration purposes only**.

**Why this is OK for a portfolio project:**
- Runs only on your local machine
- `config.js` is in `.gitignore` and never committed
- Perfect for demos, screenshots, and portfolio videos

**For production, you would use:**
- AWS Cognito Identity Pools (temporary browser credentials)
- Backend API with Lambda + API Gateway
- IAM roles for hosted applications

**Interview talking point:** "For this portfolio demo, I'm using local credentials since it only runs on my machine. In production, I would implement Cognito Identity Pools for secure, temporary browser credentials, or route all AWS calls through a backend API."

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
  "rawDataLocation": "s3://ai-dp-data-lake-dev/raw/year=2026/month=01/day=15/file.json",
  "processedDataLocation": "s3://ai-dp-data-lake-dev/processed/year=2026/month=01/day=15/uuid.json",
  "mergedAt": "2026-01-15T12:00:05.123Z",
  "expiresAt": 1739534400
}
```

### Athena Table Schema

The `processed` table contains enriched data with these key columns:
- `sentiment`: POSITIVE, NEUTRAL, NEGATIVE, or MIXED
- `sentimentscore`: Confidence score (0.0 to 1.0)
- `entities`: Array of extracted entities
- `timestamp`: Processing timestamp
- Partition keys: `year`, `month`, `day`
