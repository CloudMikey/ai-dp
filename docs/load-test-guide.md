# Load Test Script Guide

This guide explains how `scripts/load-test-streaming.ps1` works, step by step. Written for entry-level understanding.

## What Does This Script Do?

The script tests if your streaming pipeline can handle load (many requests at once). It:
1. Sends 1000 events to your API Gateway
2. Waits for Lambda to process them
3. Checks CloudWatch metrics to see how the system performed
4. Reports pass/fail based on success criteria

```
Your Computer                    AWS Cloud
    |                               |
    |  1. Send 1000 HTTP requests   |
    |------------------------------>| API Gateway
    |                               |     |
    |                               |     v
    |                               | Kinesis Stream (buffers events)
    |                               |     |
    |                               |     v
    |                               | Lambda (processes in batches of 100)
    |                               |     |
    |                               |     v
    |  2. Query CloudWatch metrics  | S3 (stores processed data)
    |<------------------------------|
    |                               |
    |  3. Show results              |
    |                               |
```

---

## Script Structure Overview

The script has 4 main sections:

```
1. PARAMETERS      (lines 27-34)   - What options you can pass in
2. CONFIGURATION   (lines 36-48)   - Constants and setup
3. HELPER FUNCTIONS (lines 50-524) - Reusable code blocks
4. MAIN EXECUTION  (lines 526-614) - The actual test flow
```

---

## Section 1: Parameters (lines 27-34)

```powershell
param(
    [string]$ApiEndpoint,           # The URL to send events to
    [int]$EventCount = 1000,        # How many events to send (default: 1000)
    [int]$Concurrency = 50,         # How many to send at once (default: 50)
    [string]$Region = "us-west-2",  # AWS region
    [int]$ProcessingWaitSeconds = 90,  # Time to wait for Lambda
    [switch]$ExportResults          # Save results to JSON file
)
```

**How parameters work:**
- Parameters let you customize the script without editing it
- Default values are used if you don't provide them
- `[switch]` means it's a flag (true/false) - just add `-ExportResults` to enable

**Example usage:**
```powershell
# Use all defaults
.\load-test-streaming.ps1

# Override some parameters
.\load-test-streaming.ps1 -EventCount 100 -Concurrency 10

# With explicit endpoint
.\load-test-streaming.ps1 -ApiEndpoint "https://xxx.execute-api.us-west-2.amazonaws.com/ingest"
```

---

## Section 2: Configuration (lines 36-48)

```powershell
$ErrorActionPreference = "Stop"  # Stop script on any error

# These names MUST match your Terraform resources
$LambdaFunctionName = "ai-dp-dev-etl"
$KinesisStreamName = "ai-dp-dev-ingestion-stream"
$DLQName = "ai-dp-dev-etl-dlq"

# Generate unique ID for this test run (for tracking in logs)
$TestRunId = [guid]::NewGuid().ToString().Substring(0, 8)
```

**Why this matters:**
- The script uses these names to query CloudWatch metrics
- If you rename resources, update these constants
- `$TestRunId` lets you filter CloudWatch logs to find events from this specific test

---

## Section 3: Helper Functions

### Function 1: `Write-ColorText` (lines 54-61)

```powershell
function Write-ColorText {
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}
```

**What it does:** Prints colored text to the console.

**Why it exists:** Makes the output easier to read. Green = good, Yellow = warning, Red = error.

---

### Function 2: `Get-ApiEndpointUrl` (lines 63-91)

```powershell
function Get-ApiEndpointUrl {
    param([string]$ProvidedEndpoint)

    # If user provided endpoint, use it
    if ($ProvidedEndpoint) {
        return $ProvidedEndpoint
    }

    # Otherwise, try to get it from Terraform
    try {
        $endpoint = terraform -chdir=$terraformDir output -raw api_gateway_invoke_url
        if ($endpoint) {
            return $endpoint
        }
    }
    catch {
        # Terraform failed
    }

    throw "Could not detect API endpoint..."
}
```

**What it does:** Gets the API Gateway URL either from:
1. The `-ApiEndpoint` parameter (if provided)
2. Terraform output (auto-detect)

**Key PowerShell concepts:**
- `throw` stops the script with an error message
- `try/catch` handles errors gracefully
- `2>$null` suppresses error output (the `2` is stderr)

---

### Function 3: `New-TestEvent` (lines 93-110)

```powershell
function New-TestEvent {
    param([int]$EventNumber)

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    $event = @{
        event_type      = "load_test"           # Required by ETL Lambda
        event_timestamp = $timestamp            # Required by ETL Lambda
        event_id        = $EventNumber
        source          = "load-test-streaming.ps1"
        test_run_id     = $TestRunId
        message         = "Load test event number $EventNumber"
    }

    return ($event | ConvertTo-Json -Compress)
}
```

**What it does:** Creates a JSON event that matches what the ETL Lambda expects.

**Key PowerShell concepts:**
- `@{ }` creates a hashtable (like a dictionary)
- `| ConvertTo-Json` converts the hashtable to JSON string
- `-Compress` removes whitespace to make it smaller

**Example output:**
```json
{"event_type":"load_test","event_timestamp":"2026-01-26T12:00:00.000Z","event_id":1,"source":"load-test-streaming.ps1","test_run_id":"abc12345","message":"Load test event number 1"}
```

---

### Function 4: `Get-DLQMessageCount` (lines 112-147)

```powershell
function Get-DLQMessageCount {
    try {
        # Step 1: Get the queue URL from queue name
        $queueUrl = aws sqs get-queue-url --queue-name $DLQName ...

        # Step 2: Get attributes (including message count)
        $result = aws sqs get-queue-attributes --queue-url $queueUrl ...

        # Step 3: Extract the count
        $count = [int]$result.Attributes.ApproximateNumberOfMessages
        return $count
    }
    catch {
        return 0  # If something fails, assume 0 (don't fail the test)
    }
}
```

**What it does:** Checks how many messages are in the Dead Letter Queue (DLQ).

**Why it matters:**
- DLQ = where failed records go after 3 retries
- If DLQ has messages after the test, something failed
- We check before AND after to calculate "new" failures

**AWS CLI breakdown:**
```bash
# Get queue URL from name
aws sqs get-queue-url --queue-name ai-dp-dev-etl-dlq

# Get queue attributes (message count)
aws sqs get-queue-attributes --queue-url <url> --attribute-names ApproximateNumberOfMessages
```

---

### Function 5: `Send-EventsInParallel` (lines 195-271)

This is the most complex function. Let's break it down:

```powershell
function Send-EventsInParallel {
    param(
        [string]$Endpoint,
        [int]$Count,
        [int]$MaxParallel
    )

    $results = @()  # Array to store all results

    # Process in batches (e.g., 50 at a time)
    for ($i = 1; $i -le $Count; $i += $MaxParallel) {
        $batchJobs = @()

        # Start parallel jobs for this batch
        for ($j = $i; $j -le $batchEnd; $j++) {
            $job = Start-Job -ScriptBlock {
                # This code runs in a separate process
                Invoke-WebRequest -Uri $Endpoint -Method POST -Body $EventJson ...
            }
            $batchJobs += $job
        }

        # Wait for all jobs in this batch to finish
        $batchResults = $batchJobs | Wait-Job | Receive-Job
        $results += $batchResults

        # Clean up completed jobs
        $batchJobs | Remove-Job
    }

    return $results
}
```

**How parallel execution works:**

```
Without parallelism (sequential):
Event 1 -----> Event 2 -----> Event 3 -----> Event 4 -----> ...
[takes 4 seconds if each takes 1 second]

With parallelism (50 concurrent):
Event 1  ----\
Event 2  ----\\
Event 3  ----\\\
...           |-----> All complete together
Event 50 ----/
[takes ~1 second for 50 events]
```

**Key PowerShell concepts:**
- `Start-Job` runs code in a background process
- `Wait-Job` pauses until jobs complete
- `Receive-Job` gets the output from jobs
- `Remove-Job` cleans up finished jobs

**Why batches?**
- We don't start all 1000 at once (would overwhelm system)
- Instead: start 50, wait, start next 50, wait, etc.
- This controls the concurrency

---

### Function 6: `Get-CloudWatchMetrics` (lines 273-384)

```powershell
function Get-CloudWatchMetrics {
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    $metrics = @{
        LambdaConcurrency    = 0
        LambdaP95DurationMs  = 0
        LambdaErrors         = 0
        KinesisIteratorAgeMs = 0
    }

    # Query each metric from CloudWatch
    # Example: Lambda Concurrent Executions
    $result = aws cloudwatch get-metric-statistics `
        --namespace "AWS/Lambda" `
        --metric-name "ConcurrentExecutions" `
        --dimensions "Name=FunctionName,Value=$LambdaFunctionName" `
        --start-time $startStr `
        --end-time $endStr `
        --period 60 `
        --statistics Maximum `
        --region $Region `
        --output json | ConvertFrom-Json

    return $metrics
}
```

**What it does:** Fetches performance metrics from CloudWatch.

**Metrics explained:**

| Metric | What it measures | Why it matters |
|--------|------------------|----------------|
| `ConcurrentExecutions` | How many Lambdas ran at once | Shows if Lambda scaled up |
| `Duration` (P95) | 95th percentile processing time | Success criteria: <5000ms |
| `Errors` | Number of Lambda failures | Should be 0 |
| `IteratorAgeMilliseconds` | How far behind Kinesis consumer is | High = backlog building |

**AWS CLI breakdown:**
```bash
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Lambda" \           # Service namespace
    --metric-name "ConcurrentExecutions" \
    --dimensions "Name=FunctionName,Value=ai-dp-dev-etl" \
    --start-time "2026-01-26T12:00:00Z" \
    --end-time "2026-01-26T12:10:00Z" \
    --period 60 \                        # 60-second intervals
    --statistics Maximum \               # Get max value
    --region us-west-2
```

---

### Function 7: `Write-TestReport` (lines 386-505)

```powershell
function Write-TestReport {
    # Calculate statistics
    $successCount = ($SendResults | Where-Object { $_.Success -eq $true }).Count
    $latencies = $SendResults | ForEach-Object { $_.LatencyMs } | Sort-Object

    # Calculate P95 (95th percentile)
    $p95Index = [Math]::Ceiling($latencies.Count * 0.95) - 1
    $apiP95Latency = $latencies[$p95Index]

    # Print formatted report
    Write-Host "API GATEWAY RESULTS:" -ForegroundColor Cyan
    Write-Host "  Events Sent:      $totalCount"
    ...

    # Validate success criteria
    $apiPassed = $failCount -eq 0
    Write-Criterion -Name "API Gateway: 0 errors" -Passed $apiPassed ...
}
```

**What is P95 (95th percentile)?**
```
If you have 100 latency measurements sorted:
[10, 15, 20, 25, ... 95 values ... , 500, 600, 700]
                                     ^
                                     P95 = 95th value

Meaning: 95% of requests were faster than this value.
Why not average? Averages hide outliers. P95 shows worst-case for most users.
```

**Key PowerShell concepts:**
- `Where-Object { }` filters arrays (like SQL WHERE)
- `ForEach-Object { }` transforms each item
- `Measure-Object` calculates statistics (sum, average, max, etc.)

---

## Section 4: Main Execution (lines 526-614)

```powershell
try {
    # Step 1: Get API endpoint
    $endpoint = Get-ApiEndpointUrl -ProvidedEndpoint $ApiEndpoint

    # Step 2: Check baseline DLQ (before test)
    $dlqBefore = Get-DLQMessageCount

    # Step 3: Send all events
    $startTime = Get-Date
    $sendResults = Send-EventsInParallel -Endpoint $endpoint -Count $EventCount
    $sendEndTime = Get-Date

    # Step 4: Wait for Lambda to process
    Start-Sleep -Seconds $ProcessingWaitSeconds

    # Step 5: Collect CloudWatch metrics
    $metrics = Get-CloudWatchMetrics -StartTime $startTime -EndTime $endTime

    # Step 6: Check DLQ after test
    $dlqAfter = Get-DLQMessageCount

    # Step 7: Generate report
    $report = Write-TestReport -SendResults $sendResults -CloudWatchMetrics $metrics ...

    # Step 8: Exit with appropriate code
    if ($report.AllCriteriaPassed) {
        exit 0  # Success
    } else {
        exit 1  # Failure
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
```

**Why we wait 90 seconds:**
- Kinesis buffers records (batch_size=100, batching_window=5s)
- Lambda processes batches (up to 60s timeout)
- CloudWatch metrics have ~1 minute delay
- 90 seconds ensures all data is available

---

## Success Criteria

The script validates these criteria from `docs/roadmap.md`:

| Criterion | Threshold | How it's checked |
|-----------|-----------|------------------|
| API errors | 0 | Count failed HTTP requests |
| Lambda errors | 0 | CloudWatch `Errors` metric |
| DLQ messages | 0 new | Compare before/after count |
| P95 latency | <5000ms | CloudWatch `Duration` P95 |

---

## Common Issues and Fixes

### Issue 1: "Could not detect API endpoint"
```powershell
# Solution: Provide endpoint explicitly
.\load-test-streaming.ps1 -ApiEndpoint "https://your-api-id.execute-api.us-west-2.amazonaws.com/ingest"

# Or run terraform output to find it:
terraform -chdir=envs/dev output api_gateway_invoke_url
```

### Issue 2: CloudWatch metrics show 0
This is normal if:
- Metrics haven't propagated yet (wait 2-3 minutes)
- No Lambda invocations happened (check API Gateway logs)

### Issue 3: DLQ has messages
Check what failed:
```bash
aws sqs receive-message \
    --queue-url https://sqs.us-west-2.amazonaws.com/YOUR_ACCOUNT/ai-dp-dev-etl-dlq \
    --region us-west-2
```

---

## Interview Talking Points

When discussing this script in interviews, highlight:

1. **Load testing methodology**
   - Why 1000 events? (realistic traffic simulation)
   - Why 50 concurrency? (stress without overwhelming)

2. **Observability**
   - How to query CloudWatch metrics programmatically
   - Understanding P95 vs average latency

3. **Error handling**
   - DLQ pattern for failed records
   - Before/after comparison to detect regressions

4. **PowerShell patterns**
   - Parallel job execution
   - Parameter handling with defaults
   - AWS CLI integration

---

## Quick Reference

```powershell
# Basic usage
.\scripts\load-test-streaming.ps1 -ApiEndpoint "https://xxx.execute-api.us-west-2.amazonaws.com/ingest"

# Quick test (100 events)
.\scripts\load-test-streaming.ps1 -ApiEndpoint "..." -EventCount 100 -ProcessingWaitSeconds 30

# Full test with export
.\scripts\load-test-streaming.ps1 -ApiEndpoint "..." -ExportResults
```

---

## The Professional Way: k6

The PowerShell script above is great for learning, but real engineers use purpose-built tools. Here's the same test using **k6** - an industry-standard load testing tool.

### Why k6?

| PowerShell Script | k6 |
|-------------------|-----|
| ~450 lines of code | ~60 lines of code |
| Manual metric collection | Built-in metrics |
| Custom P95 calculation | Automatic percentiles |
| No HTML reports | Built-in reporting |
| Windows-only | Cross-platform |

**Who uses k6?** GitLab, Microsoft, Grafana Labs, and thousands of companies.

### The k6 Script Explained

```javascript
// scripts/load-test-streaming.js

import http from 'k6/http';
import { check, sleep } from 'k6';

// Test configuration - this replaces 50+ lines of PowerShell
export const options = {
  scenarios: {
    load_test: {
      executor: 'constant-vus',  // Keep constant virtual users
      vus: 50,                   // 50 concurrent users
      duration: '20s',           // Run for 20 seconds
    },
  },
  // Pass/fail thresholds - same as our success criteria
  thresholds: {
    http_req_failed: ['rate<0.01'],      // <1% errors
    http_req_duration: ['p(95)<5000'],   // P95 < 5 seconds
  },
};

// Main test function - runs for each virtual user
export default function () {
  const payload = JSON.stringify({
    event_type: 'load_test',
    event_timestamp: new Date().toISOString(),
  });

  const response = http.post(API_URL, payload, {
    headers: {
      'Content-Type': 'application/json',
      'X-Partition-Key': `k6-${__VU}-${__ITER}`,  // __VU = user, __ITER = iteration
    },
  });

  // Validate response
  check(response, {
    'status is 200': (r) => r.status === 200,
  });

  sleep(0.1);  // 100ms pause between requests
}
```

### Key k6 Concepts

**Virtual Users (VUs):** Simulated concurrent users. 50 VUs = 50 people using your API simultaneously.

**Iterations:** Each VU runs the `default` function repeatedly. If duration is 20s and each iteration takes ~0.2s, each VU runs ~100 iterations = 5000 total requests.

**Thresholds:** Automatic pass/fail criteria. k6 checks these at the end and returns exit code 0 (pass) or 1 (fail).

**Built-in Metrics:**
- `http_req_duration` - request latency (with p50, p90, p95, p99 automatically)
- `http_req_failed` - percentage of failed requests
- `http_reqs` - total request count
- `vus` - active virtual users

### Running k6

```bash
# Install k6
choco install k6        # Windows (chocolatey)
winget install k6       # Windows (winget)
brew install k6         # Mac

# Run the test
k6 run scripts/load-test-streaming.js

# With custom endpoint
k6 run -e API_ENDPOINT=https://xxx.execute-api.us-west-2.amazonaws.com/ingest scripts/load-test-streaming.js
```

### k6 Output

```
          /\      |‾‾| /‾‾/   /‾‾/
     /\  /  \     |  |/  /   /  /
    /  \/    \    |     (   /   ‾‾\
   /          \   |  |\  \ |  (‾)  |
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: scripts/load-test-streaming.js
     output: -

  scenarios: (100.00%) 1 scenario, 50 max VUs, 50s max duration
           * load_test: 50 looping VUs for 20s

running (20.0s), 00/50 VUs, 4521 complete and 0 interrupted iterations
load_test ✓ [======================================] 50 VUs  20s

     ✓ status is 200
     ✓ response has SequenceNumber

     checks.........................: 100.00% ✓ 9042      ✗ 0
     http_req_duration..............: avg=42.3ms  min=18ms  med=38ms  max=234ms  p(90)=65ms  p(95)=89ms
     http_req_failed................: 0.00%   ✓ 0         ✗ 4521
     http_reqs......................: 4521    226.05/s

     ✓ thresholds passed
```

### When to Use Which

| Use PowerShell When | Use k6 When |
|---------------------|-------------|
| Learning how load testing works | Running actual load tests |
| Need CloudWatch metric collection | Just need HTTP testing |
| Windows-only environment | Any environment |
| Want to understand internals | Want reliable results |

### Interview Answer

> "I built two load test versions. The PowerShell script helped me understand the fundamentals - parallel execution, percentile calculations, and CloudWatch metrics. But in production, I'd use k6 because it's purpose-built for this. It handles edge cases automatically, gives me P95/P99 out of the box, and is what companies like GitLab and Microsoft use. The key insight is knowing when to build from scratch for learning versus using the right tool for the job."
