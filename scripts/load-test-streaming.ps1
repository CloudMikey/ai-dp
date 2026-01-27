<#
.SYNOPSIS
    Load test for AI-DP streaming pipeline (API Gateway -> Kinesis -> Lambda -> S3)

.DESCRIPTION
    Sends events to the API Gateway endpoint and validates the pipeline handles them correctly.
    Collects CloudWatch metrics and checks success criteria.

.PARAMETER ApiEndpoint
    The API Gateway URL. If not provided, auto-detects from Terraform output.

.PARAMETER EventCount
    Number of events to send. Default: 1000

.PARAMETER Concurrency
    Number of parallel requests. Default: 50

.EXAMPLE
    .\load-test-streaming.ps1
    # Auto-detect endpoint, send 1000 events

.EXAMPLE
    .\load-test-streaming.ps1 -ApiEndpoint "https://xxx.execute-api.us-west-2.amazonaws.com/ingest" -EventCount 100
    # Use specific endpoint, send 100 events
#>

param(
    [string]$ApiEndpoint,
    [int]$EventCount = 1000,
    [int]$Concurrency = 50,
    [string]$Region = "us-west-2",
    [int]$ProcessingWaitSeconds = 90,
    [switch]$ExportResults
)

# ============================================================
#                    CONFIGURATION
# ============================================================

$ErrorActionPreference = "Stop"

# Resource names (must match Terraform outputs)
$LambdaFunctionName = "ai-dp-dev-etl"
$KinesisStreamName = "ai-dp-dev-ingestion-stream"
$DLQName = "ai-dp-dev-etl-dlq"

# Generate unique ID for this test run
$TestRunId = [guid]::NewGuid().ToString().Substring(0, 8)

# ============================================================
#                    HELPER FUNCTIONS
# ============================================================

function Write-ColorText {
    # Simple helper to write colored text to console
    param(
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

function Get-ApiEndpointUrl {
    # Get API endpoint from Terraform or use provided value
    param([string]$ProvidedEndpoint)

    if ($ProvidedEndpoint) {
        Write-ColorText "Using provided API endpoint" "Gray"
        return $ProvidedEndpoint
    }

    # Try to get from Terraform output
    Write-ColorText "Detecting API endpoint from Terraform..." "Gray"

    try {
        $scriptDir = Split-Path -Parent $PSScriptRoot
        $terraformDir = Join-Path $scriptDir "envs/dev"

        $endpoint = terraform -chdir=$terraformDir output -raw api_gateway_invoke_url 2>$null

        if ($endpoint -and $endpoint -notlike "*Error*" -and $endpoint -notlike "*No outputs*") {
            Write-ColorText "Found endpoint: $endpoint" "Green"
            return $endpoint
        }
    }
    catch {
        # Terraform not available or failed
    }

    throw "Could not detect API endpoint. Please provide it with -ApiEndpoint parameter."
}

function New-TestEvent {
    # Create a test event with required fields
    param([int]$EventNumber)

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    # Event must have: event_type, event_timestamp (required by ETL Lambda)
    $event = @{
        event_type      = "load_test"
        event_timestamp = $timestamp
        event_id        = $EventNumber
        source          = "load-test-streaming.ps1"
        test_run_id     = $TestRunId
        message         = "Load test event number $EventNumber"
    }

    return ($event | ConvertTo-Json -Compress)
}

function Get-DLQMessageCount {
    # Check how many messages are in the Dead Letter Queue

    Write-ColorText "Checking DLQ message count..." "Gray"

    try {
        # Get the queue URL first
        $queueUrl = aws sqs get-queue-url `
            --queue-name $DLQName `
            --region $Region `
            --output text `
            --query 'QueueUrl' 2>$null

        if (-not $queueUrl) {
            Write-ColorText "Warning: Could not find DLQ $DLQName" "Yellow"
            return 0
        }

        # Get the message count (note: AWS uses "ApproximateNumberOfMessages" not "Visible")
        $result = aws sqs get-queue-attributes `
            --queue-url $queueUrl `
            --attribute-names "ApproximateNumberOfMessages" `
            --region $Region `
            --output json 2>$null | ConvertFrom-Json

        if ($result -and $result.Attributes) {
            $count = [int]$result.Attributes.ApproximateNumberOfMessages
            return $count
        }
        return 0
    }
    catch {
        Write-ColorText "Warning: Could not check DLQ - $_" "Yellow"
        return 0
    }
}

function Send-SingleEvent {
    # Send one event to API Gateway and return the result
    param(
        [string]$Endpoint,
        [string]$EventJson,
        [string]$PartitionKey
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $response = Invoke-WebRequest `
            -Uri $Endpoint `
            -Method POST `
            -Body $EventJson `
            -ContentType "application/json" `
            -Headers @{ "X-Partition-Key" = $PartitionKey } `
            -UseBasicParsing `
            -ErrorAction Stop

        $stopwatch.Stop()

        return @{
            Success    = $true
            StatusCode = $response.StatusCode
            LatencyMs  = $stopwatch.ElapsedMilliseconds
            Error      = $null
        }
    }
    catch {
        $stopwatch.Stop()

        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        return @{
            Success    = $false
            StatusCode = $statusCode
            LatencyMs  = $stopwatch.ElapsedMilliseconds
            Error      = $_.Exception.Message
        }
    }
}

function Send-EventsInParallel {
    # Send multiple events using parallel jobs
    param(
        [string]$Endpoint,
        [int]$Count,
        [int]$MaxParallel
    )

    Write-ColorText "Sending $Count events (concurrency: $MaxParallel)..." "Cyan"

    $results = @()
    $jobs = @()

    # Process in batches to control concurrency
    for ($i = 1; $i -le $Count; $i += $MaxParallel) {
        $batchEnd = [Math]::Min($i + $MaxParallel - 1, $Count)
        $batchJobs = @()

        # Start parallel jobs for this batch
        for ($j = $i; $j -le $batchEnd; $j++) {
            $eventJson = New-TestEvent -EventNumber $j
            $partitionKey = "load-test-$j"

            $job = Start-Job -ScriptBlock {
                param($Endpoint, $EventJson, $PartitionKey)

                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

                try {
                    $response = Invoke-WebRequest `
                        -Uri $Endpoint `
                        -Method POST `
                        -Body $EventJson `
                        -ContentType "application/json" `
                        -Headers @{ "X-Partition-Key" = $PartitionKey } `
                        -UseBasicParsing `
                        -ErrorAction Stop

                    $stopwatch.Stop()

                    @{
                        Success    = $true
                        StatusCode = $response.StatusCode
                        LatencyMs  = $stopwatch.ElapsedMilliseconds
                        Error      = $null
                    }
                }
                catch {
                    $stopwatch.Stop()

                    @{
                        Success    = $false
                        StatusCode = 0
                        LatencyMs  = $stopwatch.ElapsedMilliseconds
                        Error      = $_.Exception.Message
                    }
                }
            } -ArgumentList $Endpoint, $eventJson, $partitionKey

            $batchJobs += $job
        }

        # Wait for batch to complete and collect results
        $batchResults = $batchJobs | Wait-Job | Receive-Job
        $batchJobs | Remove-Job

        $results += $batchResults

        # Progress update every 100 events
        $completed = [Math]::Min($batchEnd, $Count)
        if ($completed % 100 -eq 0 -or $completed -eq $Count) {
            Write-ColorText "  Progress: $completed / $Count events sent" "Gray"
        }
    }

    return $results
}

function Get-CloudWatchMetrics {
    # Fetch Lambda and Kinesis metrics from CloudWatch
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    Write-ColorText "Collecting CloudWatch metrics..." "Gray"

    $startStr = $StartTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endStr = $EndTime.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $metrics = @{
        LambdaConcurrency    = 0
        LambdaP95DurationMs  = 0
        LambdaErrors         = 0
        KinesisIteratorAgeMs = 0
    }

    # 1. Lambda Concurrent Executions (Maximum)
    try {
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

        if ($result.Datapoints) {
            $metrics.LambdaConcurrency = ($result.Datapoints | Measure-Object -Property Maximum -Maximum).Maximum
        }
    }
    catch {
        Write-ColorText "  Warning: Could not get Lambda concurrency metric" "Yellow"
    }

    # 2. Lambda Duration P95
    try {
        $result = aws cloudwatch get-metric-statistics `
            --namespace "AWS/Lambda" `
            --metric-name "Duration" `
            --dimensions "Name=FunctionName,Value=$LambdaFunctionName" `
            --start-time $startStr `
            --end-time $endStr `
            --period 300 `
            --extended-statistics "p95" `
            --region $Region `
            --output json | ConvertFrom-Json

        if ($result.Datapoints) {
            foreach ($dp in $result.Datapoints) {
                if ($dp.ExtendedStatistics -and $dp.ExtendedStatistics.p95) {
                    $p95 = $dp.ExtendedStatistics.p95
                    if ($p95 -gt $metrics.LambdaP95DurationMs) {
                        $metrics.LambdaP95DurationMs = $p95
                    }
                }
            }
        }
    }
    catch {
        Write-ColorText "  Warning: Could not get Lambda duration metric" "Yellow"
    }

    # 3. Lambda Errors (Sum)
    try {
        $result = aws cloudwatch get-metric-statistics `
            --namespace "AWS/Lambda" `
            --metric-name "Errors" `
            --dimensions "Name=FunctionName,Value=$LambdaFunctionName" `
            --start-time $startStr `
            --end-time $endStr `
            --period 300 `
            --statistics Sum `
            --region $Region `
            --output json | ConvertFrom-Json

        if ($result.Datapoints) {
            $metrics.LambdaErrors = ($result.Datapoints | Measure-Object -Property Sum -Sum).Sum
        }
    }
    catch {
        Write-ColorText "  Warning: Could not get Lambda errors metric" "Yellow"
    }

    # 4. Kinesis Iterator Age (Maximum)
    try {
        $result = aws cloudwatch get-metric-statistics `
            --namespace "AWS/Kinesis" `
            --metric-name "GetRecords.IteratorAgeMilliseconds" `
            --dimensions "Name=StreamName,Value=$KinesisStreamName" `
            --start-time $startStr `
            --end-time $endStr `
            --period 60 `
            --statistics Maximum `
            --region $Region `
            --output json | ConvertFrom-Json

        if ($result.Datapoints) {
            $metrics.KinesisIteratorAgeMs = ($result.Datapoints | Measure-Object -Property Maximum -Maximum).Maximum
        }
    }
    catch {
        Write-ColorText "  Warning: Could not get Kinesis iterator age metric" "Yellow"
    }

    return $metrics
}

function Write-TestReport {
    # Display results and validate success criteria
    param(
        [array]$SendResults,
        [hashtable]$CloudWatchMetrics,
        [int]$DLQBefore,
        [int]$DLQAfter,
        [datetime]$StartTime,
        [datetime]$EndTime
    )

    # Calculate API Gateway statistics
    $successCount = ($SendResults | Where-Object { $_.Success -eq $true }).Count
    $failCount = ($SendResults | Where-Object { $_.Success -ne $true }).Count
    $totalCount = $SendResults.Count

    $latencies = $SendResults | ForEach-Object { $_.LatencyMs } | Sort-Object
    $avgLatency = ($latencies | Measure-Object -Average).Average
    $maxLatency = ($latencies | Measure-Object -Maximum).Maximum

    # Calculate P95 latency (95th percentile)
    $p95Index = [Math]::Ceiling($latencies.Count * 0.95) - 1
    $apiP95Latency = $latencies[$p95Index]

    $newDLQMessages = $DLQAfter - $DLQBefore

    # Print report
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "         LOAD TEST RESULTS - STREAMING PATH" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""

    Write-Host "TEST INFO:" -ForegroundColor Cyan
    Write-Host "  Test Run ID:      $TestRunId"
    Write-Host "  Duration:         $([Math]::Round(($EndTime - $StartTime).TotalSeconds, 1)) seconds"
    Write-Host ""

    Write-Host "API GATEWAY RESULTS:" -ForegroundColor Cyan
    Write-Host "  Events Sent:      $totalCount"
    Write-Host "  Successful:       $successCount ($([Math]::Round($successCount / $totalCount * 100, 1))%)"
    Write-Host "  Failed:           $failCount"
    Write-Host "  Avg Latency:      $([Math]::Round($avgLatency, 0)) ms"
    Write-Host "  P95 Latency:      $apiP95Latency ms"
    Write-Host "  Max Latency:      $maxLatency ms"
    Write-Host ""

    Write-Host "LAMBDA METRICS (ETL):" -ForegroundColor Cyan
    Write-Host "  Max Concurrency:  $($CloudWatchMetrics.LambdaConcurrency)"
    Write-Host "  P95 Duration:     $([Math]::Round($CloudWatchMetrics.LambdaP95DurationMs, 0)) ms"
    Write-Host "  Total Errors:     $($CloudWatchMetrics.LambdaErrors)"
    Write-Host ""

    Write-Host "KINESIS METRICS:" -ForegroundColor Cyan
    Write-Host "  Max Iterator Age: $([Math]::Round($CloudWatchMetrics.KinesisIteratorAgeMs / 1000, 2)) seconds"
    Write-Host ""

    Write-Host "ERROR HANDLING:" -ForegroundColor Cyan
    Write-Host "  DLQ Before:       $DLQBefore messages"
    Write-Host "  DLQ After:        $DLQAfter messages"
    Write-Host "  New DLQ Messages: $newDLQMessages"
    Write-Host ""

    # Validate success criteria
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "         SUCCESS CRITERIA VALIDATION" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""

    $allPassed = $true

    # Criterion 1: No API errors
    $apiPassed = $failCount -eq 0
    Write-Criterion -Name "API Gateway: 0 errors" -Passed $apiPassed -Actual "$failCount errors"
    $allPassed = $allPassed -and $apiPassed

    # Criterion 2: No Lambda errors
    $lambdaPassed = $CloudWatchMetrics.LambdaErrors -eq 0
    Write-Criterion -Name "Lambda: 0 errors" -Passed $lambdaPassed -Actual "$($CloudWatchMetrics.LambdaErrors) errors"
    $allPassed = $allPassed -and $lambdaPassed

    # Criterion 3: No new DLQ messages
    $dlqPassed = $newDLQMessages -eq 0
    Write-Criterion -Name "DLQ: 0 new messages" -Passed $dlqPassed -Actual "$newDLQMessages messages"
    $allPassed = $allPassed -and $dlqPassed

    # Criterion 4: P95 latency < 5000ms (5 seconds)
    $p95Passed = $CloudWatchMetrics.LambdaP95DurationMs -lt 5000
    Write-Criterion -Name "P95 Latency: < 5000ms" -Passed $p95Passed -Actual "$([Math]::Round($CloudWatchMetrics.LambdaP95DurationMs, 0))ms"
    $allPassed = $allPassed -and $p95Passed

    Write-Host ""
    if ($allPassed) {
        Write-Host "OVERALL: PASSED" -ForegroundColor Green -BackgroundColor DarkGreen
    }
    else {
        Write-Host "OVERALL: FAILED" -ForegroundColor White -BackgroundColor DarkRed
    }
    Write-Host ""

    # Return report data for optional export
    return @{
        TestRunId             = $TestRunId
        StartTime             = $StartTime.ToString("o")
        EndTime               = $EndTime.ToString("o")
        DurationSeconds       = [Math]::Round(($EndTime - $StartTime).TotalSeconds, 1)
        EventCount            = $totalCount
        SuccessCount          = $successCount
        FailCount             = $failCount
        ApiAvgLatencyMs       = [Math]::Round($avgLatency, 0)
        ApiP95LatencyMs       = $apiP95Latency
        ApiMaxLatencyMs       = $maxLatency
        LambdaMaxConcurrency  = $CloudWatchMetrics.LambdaConcurrency
        LambdaP95DurationMs   = [Math]::Round($CloudWatchMetrics.LambdaP95DurationMs, 0)
        LambdaErrors          = $CloudWatchMetrics.LambdaErrors
        KinesisIteratorAgeMs  = $CloudWatchMetrics.KinesisIteratorAgeMs
        DLQNewMessages        = $newDLQMessages
        AllCriteriaPassed     = $allPassed
    }
}

function Write-Criterion {
    # Display a single pass/fail criterion
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Actual
    )

    if ($Passed) {
        Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
    }
    else {
        Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
    }

    Write-Host "$Name " -NoNewline
    Write-Host "(Actual: $Actual)" -ForegroundColor Gray
}

# ============================================================
#                    MAIN EXECUTION
# ============================================================

try {
    Write-Host ""
    Write-Host "AI-DP Load Test - Streaming Path" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "Test Run ID: $TestRunId" -ForegroundColor Gray
    Write-Host ""

    # Step 1: Get API endpoint
    $endpoint = Get-ApiEndpointUrl -ProvidedEndpoint $ApiEndpoint
    Write-Host "Target:      $endpoint" -ForegroundColor Gray
    Write-Host "Events:      $EventCount" -ForegroundColor Gray
    Write-Host "Concurrency: $Concurrency" -ForegroundColor Gray
    Write-Host ""

    # Step 2: Check baseline DLQ
    $dlqBefore = Get-DLQMessageCount
    Write-Host "DLQ baseline: $dlqBefore messages" -ForegroundColor Gray
    Write-Host ""

    # Step 3: Send events
    $startTime = Get-Date
    $sendResults = Send-EventsInParallel -Endpoint $endpoint -Count $EventCount -MaxParallel $Concurrency
    $sendEndTime = Get-Date

    $sendDuration = [Math]::Round(($sendEndTime - $startTime).TotalSeconds, 1)
    Write-Host ""
    Write-ColorText "All events sent in $sendDuration seconds" "Green"
    Write-Host ""

    # Step 4: Wait for Lambda to process
    Write-ColorText "Waiting $ProcessingWaitSeconds seconds for Lambda to process all records..." "Yellow"
    Write-ColorText "(Kinesis batches records, Lambda processes them in batches of 100)" "Gray"

    for ($i = $ProcessingWaitSeconds; $i -gt 0; $i -= 10) {
        Start-Sleep -Seconds ([Math]::Min(10, $i))
        $remaining = [Math]::Max(0, $i - 10)
        if ($remaining -gt 0) {
            Write-Host "  $remaining seconds remaining..." -ForegroundColor Gray
        }
    }

    $endTime = Get-Date
    Write-Host ""

    # Step 5: Collect metrics
    $metrics = Get-CloudWatchMetrics -StartTime $startTime -EndTime $endTime

    # Step 6: Check DLQ after test
    $dlqAfter = Get-DLQMessageCount

    # Step 7: Generate report
    $report = Write-TestReport `
        -SendResults $sendResults `
        -CloudWatchMetrics $metrics `
        -DLQBefore $dlqBefore `
        -DLQAfter $dlqAfter `
        -StartTime $startTime `
        -EndTime $endTime

    # Step 8: Export results if requested
    if ($ExportResults) {
        $exportPath = "load-test-results-$TestRunId.json"
        $report | ConvertTo-Json -Depth 5 | Set-Content $exportPath
        Write-ColorText "Results exported to: $exportPath" "Gray"
    }

    # Exit with appropriate code
    if ($report.AllCriteriaPassed) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  1. Check AWS CLI is configured: aws sts get-caller-identity"
    Write-Host "  2. Verify API endpoint is correct"
    Write-Host "  3. Ensure you're in the AI-DP project directory"
    Write-Host ""
    exit 1
}
