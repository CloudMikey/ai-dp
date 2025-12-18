# AI-DP Analytics Dashboard

Simple HTML/JavaScript dashboard for visualizing AI-enriched data.

## Files

- `index.html` - Main HTML structure
- `styles.css` - Styling and layout
- `app.js` - JavaScript logic for AWS queries

## Setup

### Prerequisites

- AWS CLI configured with valid credentials (`aws configure`)
- Data in S3 `processed/` layer
- Glue crawler has run successfully

### Configuration

Edit `app.js` and update the `CONFIG` object:

```javascript
const CONFIG = {
    region: 'us-west-2',                        // Your AWS region
    dynamoTableName: 'ai-dp-dev-enriched-data', // DynamoDB table name
    glueDatabase: 'ai-dp-dev-analytics',         // Glue database
    glueTable: 'processed',                      // Glue table name
    athenaWorkgroup: 'ai-dp-dev-workgroup'       // Athena workgroup
};
```

## Running the Dashboard

### Option 1: Python HTTP Server (Recommended)

```bash
cd dashboard
python -m http.server 8080
```

Then open http://localhost:8080 in your browser.

### Option 2: Node.js HTTP Server

```bash
cd dashboard
npx http-server -p 8080
```

Then open http://localhost:8080 in your browser.

### Option 3: VS Code Live Server

1. Install "Live Server" extension in VS Code
2. Right-click `index.html`
3. Select "Open with Live Server"

## Features

### Metrics (DynamoDB)
- Total records count
- Positive/Negative/Neutral sentiment counts

### Charts (Athena)
- **Sentiment Distribution** - Pie chart showing sentiment breakdown

### Tables (DynamoDB)
- **Recent Events** - Last 20 records with timestamps

## How It Works

1. **AWS SDK Authentication**: Uses credentials from `~/.aws/credentials`
2. **Athena Queries**: Runs SQL queries on S3 data via Glue Data Catalog
3. **DynamoDB Scans**: Fetches recent records for real-time view
4. **Chart.js**: Renders interactive charts

## Troubleshooting

### "Access Denied" errors

Make sure AWS CLI is configured:
```bash
aws configure
aws sts get-caller-identity
```

### "Table not found" in Athena

Run the Glue crawler first:
```bash
aws glue start-crawler --name ai-dp-dev-crawler --region us-west-2
```

### CORS errors

Use a local HTTP server (Option 1 or 2 above), don't open `index.html` directly in browser.

### No data showing

1. Check if data exists in S3: `aws s3 ls s3://ai-dp-data-lake-dev-us-west-2/processed/ --recursive`
2. Check DynamoDB: `aws dynamodb scan --table-name ai-dp-dev-enriched-data --limit 5`
3. Check browser console for errors (F12)

## Interview Talking Points

**"Walk me through your dashboard"**
- "I built a simple HTML/JS dashboard that queries both real-time and historical data. It uses the AWS SDK for JavaScript to connect to Athena for SQL analytics on S3, and DynamoDB for real-time recent events. Chart.js renders the visualizations."

**"Why separate files (HTML, CSS, JS)?"**
- "Better organization and maintainability. The HTML defines the structure, CSS handles all the styling, and JavaScript handles the logic. This follows separation of concerns principle."

**"How does authentication work?"**
- "The AWS SDK uses the default credential provider chain, which reads from `~/.aws/credentials`. In production, you'd use IAM roles or temporary credentials via AWS Cognito."

**"Why Athena + DynamoDB?"**
- "Dual-query strategy: DynamoDB for fast real-time queries (last 20 records, sub-10ms), Athena for complex SQL analytics on historical data (partition pruning by date). Best of both worlds."
