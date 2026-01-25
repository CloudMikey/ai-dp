// ========================================
// AI-DP Dashboard - Main Application
// ========================================
// Data Sources (Optimized Strategy):
// - DynamoDB: Real-time recent events + metrics cards (last 30 days)
// - Curated (S3): Sentiment pie chart + total processed (pre-aggregated, instant)
// - Athena: Entity type chart (UNNEST query - demonstrates SQL skills)
// ========================================

// ========================================
// STEP 1: Configure AWS SDK
// ========================================
AWS.config.update({
    region: CONFIG.AWS_REGION,
    accessKeyId: CONFIG.AWS_ACCESS_KEY_ID,
    secretAccessKey: CONFIG.AWS_SECRET_ACCESS_KEY
});

// Create AWS service clients
const dynamoDB = new AWS.DynamoDB.DocumentClient();
const athena = new AWS.Athena();
const sqs = new AWS.SQS();
const s3 = new AWS.S3();

// ========================================
// STEP 2: Global Variables
// ========================================
let sentimentChart = null;
let entityChart = null;
let isLoadingDynamoDB = false;
let isLoadingAthena = false;
let cachedDynamoDBItems = [];
let cachedCuratedSummary = null;

// ========================================
// STEP 3: Main Load Function
// ========================================
async function loadData() {
    console.log('🔄 Loading dashboard data...');
    updateTimestamp();

    // Load all data sources in parallel (optimized strategy)
    // - DynamoDB: Real-time metrics + table
    // - Curated (S3): Sentiment chart + total processed (instant, pre-aggregated)
    // - Athena: Entity type chart only (demonstrates UNNEST SQL skill)
    await Promise.all([
        loadDynamoDBData(),
        loadCuratedSummary(),
        loadEntityTypesFromAthena()
    ]);

    // Pipeline status uses cached data from above
    loadPipelineStatus();

    console.log('✅ Dashboard data loaded!');
}

// ========================================
// STEP 4: DynamoDB - Real-time Recent Events
// ========================================
async function loadDynamoDBData() {
    if (isLoadingDynamoDB) return;
    isLoadingDynamoDB = true;

    setTableLoading(true);

    try {
        const params = {
            TableName: CONFIG.DYNAMODB_TABLE,
            Limit: 50
        };

        const result = await dynamoDB.scan(params).promise();
        const items = result.Items || [];
        cachedDynamoDBItems = items;

        console.log(`DynamoDB: Found ${items.length} records`);

        // Update table with recent events
        updateTable(items);

        // Update metrics cards from DynamoDB data
        updateMetrics(items);

    } catch (error) {
        console.error('DynamoDB error:', error);
        showTableError('Failed to load recent events from DynamoDB');
    } finally {
        isLoadingDynamoDB = false;
        setTableLoading(false);
    }
}

// ========================================
// STEP 5: Curated Layer - Pre-aggregated Summaries (S3)
// ========================================
// Why Curated? Instant response (~100ms) vs Athena (~2-5s)
// The Merge Lambda pre-computes sentiment counts on each record
async function loadCuratedSummary() {
    setChartLoading(true, 'sentiment-chart');

    try {
        const params = {
            Bucket: CONFIG.DATA_LAKE_BUCKET,
            Key: 'curated/latest_summary.json'
        };

        console.log('S3: Fetching curated summary...');
        const result = await s3.getObject(params).promise();
        const summary = JSON.parse(result.Body.toString('utf-8'));

        // Cache for pipeline status
        cachedCuratedSummary = summary;

        // Update sentiment pie chart with pre-aggregated data
        updateSentimentChart(summary.sentiment_counts);

        console.log(`✅ Curated: Loaded summary (${summary.total_records} total records)`);
        return summary;

    } catch (error) {
        console.error('Curated summary error:', error);
        showChartError('Curated summary not available', 'sentiment-chart');
        return null;
    } finally {
        setChartLoading(false, 'sentiment-chart');
    }
}

// ========================================
// STEP 5b: Athena - Entity Type Analysis (UNNEST Demo)
// ========================================
// Why Athena for this? CROSS JOIN UNNEST demonstrates advanced SQL skills
// This flattens nested arrays - something curated can't easily pre-compute
async function loadEntityTypesFromAthena() {
    if (isLoadingAthena) return;
    isLoadingAthena = true;

    setChartLoading(true, 'entity-chart');

    try {
        // Entity type query uses UNNEST to flatten nested entityDetails array
        // This demonstrates schema-on-read and complex SQL capabilities
        const entityQuery = `
            SELECT entity.Type as entity_type, COUNT(*) as count
            FROM "${CONFIG.ATHENA_DATABASE}"."${CONFIG.ATHENA_TABLE}"
            CROSS JOIN UNNEST(entitydetails) AS t(entity)
            GROUP BY entity.Type
            ORDER BY count DESC
        `;

        console.log('Athena: Starting entity UNNEST query...');
        const entityResult = await runAthenaQuery(entityQuery);

        if (entityResult) {
            const entityCounts = parseEntityResults(entityResult);
            updateEntityChart(entityCounts);
            console.log('✅ Athena: Entity chart updated (UNNEST query)');
        }

    } catch (error) {
        console.error('Athena entity query error:', error);
        showChartError('Athena query failed', 'entity-chart');
    } finally {
        isLoadingAthena = false;
        setChartLoading(false, 'entity-chart');
    }
}

// ========================================
// STEP 5c: Pipeline Status (uses cached data)
// ========================================
function loadPipelineStatus() {
    try {
        // Get total processed from CURATED SUMMARY (instant, no Athena query needed)
        // This is pre-calculated by Merge Lambda on each record
        const totalProcessed = cachedCuratedSummary?.total_records || 0;
        document.getElementById('total-processed').textContent = totalProcessed.toLocaleString();

        // Get last record time from DynamoDB cache
        if (cachedDynamoDBItems.length > 0) {
            const sorted = [...cachedDynamoDBItems].sort((a, b) => (b.timestamp || 0) - (a.timestamp || 0));
            const lastTime = new Date(sorted[0].timestamp);
            document.getElementById('last-record-time').textContent = getTimeAgo(lastTime);
        } else {
            document.getElementById('last-record-time').textContent = 'No data';
        }

        // Check DLQ message count (optional - may not have permissions)
        let dlqCount = 0;
        checkDLQCount().then(count => {
            dlqCount = count;
            document.getElementById('dlq-count').textContent = dlqCount;
            updateHealthStatus(dlqCount);
        });

    } catch (error) {
        console.error('Pipeline status error:', error);
        document.getElementById('total-processed').textContent = '-';
        document.getElementById('pipeline-health').textContent = 'Unknown';
    }
}

async function checkDLQCount() {
    try {
        if (CONFIG.DLQ_URL) {
            const dlqResult = await sqs.getQueueAttributes({
                QueueUrl: CONFIG.DLQ_URL,
                AttributeNames: ['ApproximateNumberOfMessages']
            }).promise();
            return parseInt(dlqResult.Attributes.ApproximateNumberOfMessages, 10) || 0;
        }
    } catch (dlqError) {
        console.log('DLQ check skipped (no permissions or URL not configured)');
    }
    return 0;
}

function updateHealthStatus(dlqCount) {
    const healthCard = document.querySelector('.status-card:nth-child(3)');
    let healthStatus = 'Healthy';
    let healthClass = 'healthy';

    if (dlqCount > 10) {
        healthStatus = 'Degraded';
        healthClass = 'error';
    } else if (dlqCount > 0) {
        healthStatus = 'Warning';
        healthClass = 'warning';
    }

    document.getElementById('pipeline-health').textContent = healthStatus;
    if (healthCard) healthCard.className = `status-card ${healthClass}`;

    // Update DLQ card styling
    const dlqCard = document.querySelector('.status-card:nth-child(4)');
    if (dlqCard) {
        dlqCard.className = dlqCount > 0 ? 'status-card warning' : 'status-card healthy';
    }
}

function getTimeAgo(date) {
    const seconds = Math.floor((new Date() - date) / 1000);
    if (seconds < 60) return 'Just now';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
    return `${Math.floor(seconds / 86400)}d ago`;
}

// ========================================
// STEP 6: Athena Query Helpers
// ========================================
async function runAthenaQuery(query) {
    const startParams = {
        QueryString: query,
        WorkGroup: CONFIG.ATHENA_WORKGROUP
    };

    const startResult = await athena.startQueryExecution(startParams).promise();
    const queryExecutionId = startResult.QueryExecutionId;

    return await waitForQueryCompletion(queryExecutionId);
}

async function waitForQueryCompletion(queryExecutionId, maxAttempts = 30) {
    for (let i = 0; i < maxAttempts; i++) {
        const statusParams = { QueryExecutionId: queryExecutionId };
        const statusResult = await athena.getQueryExecution(statusParams).promise();
        const state = statusResult.QueryExecution.Status.State;

        if (state === 'SUCCEEDED') {
            const resultsParams = { QueryExecutionId: queryExecutionId };
            return await athena.getQueryResults(resultsParams).promise();
        } else if (state === 'FAILED' || state === 'CANCELLED') {
            const reason = statusResult.QueryExecution.Status.StateChangeReason;
            throw new Error(`Athena query ${state}: ${reason}`);
        }

        await new Promise(resolve => setTimeout(resolve, 1000));
    }

    throw new Error('Athena query timed out');
}

function parseAthenaResults(queryResult) {
    const counts = {
        POSITIVE: 0,
        NEUTRAL: 0,
        NEGATIVE: 0,
        MIXED: 0
    };

    const rows = queryResult.ResultSet.Rows;
    for (let i = 1; i < rows.length; i++) {
        const row = rows[i].Data;
        const sentiment = row[0].VarCharValue;
        const count = parseInt(row[1].VarCharValue, 10);

        if (counts.hasOwnProperty(sentiment)) {
            counts[sentiment] = count;
        }
    }

    console.log('Athena sentiment counts:', counts);
    return counts;
}

function parseEntityResults(queryResult) {
    const counts = {};

    const rows = queryResult.ResultSet.Rows;
    for (let i = 1; i < rows.length; i++) {
        const row = rows[i].Data;
        const entityType = row[0].VarCharValue || 'OTHER';
        const count = parseInt(row[1].VarCharValue, 10);
        counts[entityType] = count;
    }

    console.log('Athena entity counts:', counts);
    return counts;
}

// ========================================
// STEP 7: Update Metrics Cards
// ========================================
function updateMetrics(data) {
    // Count sentiments from DynamoDB data
    let positive = 0, neutral = 0, negative = 0, mixed = 0;

    data.forEach(item => {
        const sentiment = item.sentiment;
        if (sentiment === 'POSITIVE') positive++;
        else if (sentiment === 'NEUTRAL') neutral++;
        else if (sentiment === 'NEGATIVE') negative++;
        else if (sentiment === 'MIXED') mixed++;
    });

    // Update HTML elements
    document.getElementById('total-records').textContent = data.length;
    document.getElementById('positive-count').textContent = positive;
    document.getElementById('neutral-count').textContent = neutral;
    document.getElementById('negative-count').textContent = negative;

    // Update mixed count if element exists
    const mixedElement = document.getElementById('mixed-count');
    if (mixedElement) {
        mixedElement.textContent = mixed;
    }
}

// ========================================
// STEP 8: Update Sentiment Pie Chart
// ========================================
function updateSentimentChart(sentimentCounts) {
    if (sentimentChart) {
        sentimentChart.destroy();
    }

    const ctx = document.getElementById('sentiment-chart').getContext('2d');

    const total = (sentimentCounts.POSITIVE || 0) + (sentimentCounts.NEUTRAL || 0) +
                  (sentimentCounts.NEGATIVE || 0) + (sentimentCounts.MIXED || 0);

    if (total === 0) {
        showChartError('No historical data available', 'sentiment-chart');
        return;
    }

    sentimentChart = new Chart(ctx, {
        type: 'pie',
        data: {
            labels: ['Positive', 'Neutral', 'Negative', 'Mixed'],
            datasets: [{
                data: [
                    sentimentCounts.POSITIVE || 0,
                    sentimentCounts.NEUTRAL || 0,
                    sentimentCounts.NEGATIVE || 0,
                    sentimentCounts.MIXED || 0
                ],
                backgroundColor: ['#10b981', '#f59e0b', '#ef4444', '#8b5cf6'],
                borderWidth: 2,
                borderColor: '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        font: { size: 12 },
                        padding: 15,
                        generateLabels: function(chart) {
                            const data = chart.data;
                            return data.labels.map((label, i) => ({
                                text: `${label}: ${data.datasets[0].data[i]}`,
                                fillStyle: data.datasets[0].backgroundColor[i],
                                hidden: false,
                                index: i
                            }));
                        }
                    }
                },
                title: {
                    display: true,
                    text: 'All-Time (Curated Layer)',
                    font: { size: 12 },
                    color: '#666'
                }
            }
        }
    });
}

// ========================================
// STEP 8b: Update Entity Type Chart
// ========================================
function updateEntityChart(entityCounts) {
    if (entityChart) {
        entityChart.destroy();
    }

    const ctx = document.getElementById('entity-chart').getContext('2d');

    const labels = Object.keys(entityCounts);
    const data = Object.values(entityCounts);

    if (labels.length === 0) {
        showChartError('No entity data available', 'entity-chart');
        return;
    }

    // Color palette for entity types
    const colors = {
        'ORGANIZATION': '#3b82f6',
        'PERSON': '#ec4899',
        'LOCATION': '#10b981',
        'DATE': '#f59e0b',
        'QUANTITY': '#6366f1',
        'TITLE': '#8b5cf6',
        'COMMERCIAL_ITEM': '#14b8a6',
        'EVENT': '#f97316',
        'OTHER': '#6b7280'
    };

    const backgroundColors = labels.map(l => colors[l] || '#6b7280');

    entityChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: backgroundColors,
                borderWidth: 2,
                borderColor: '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: true,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        font: { size: 11 },
                        padding: 10,
                        generateLabels: function(chart) {
                            const data = chart.data;
                            return data.labels.map((label, i) => ({
                                text: `${label}: ${data.datasets[0].data[i]}`,
                                fillStyle: data.datasets[0].backgroundColor[i],
                                hidden: false,
                                index: i
                            }));
                        }
                    }
                },
                title: {
                    display: true,
                    text: 'Athena SQL (CROSS JOIN UNNEST)',
                    font: { size: 12 },
                    color: '#666'
                }
            }
        }
    });
}

// ========================================
// STEP 9: Update Table with Recent Events
// ========================================
function updateTable(data) {
    const tbody = document.getElementById('events-tbody');
    tbody.innerHTML = '';

    if (data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="no-data">No recent events found</td></tr>';
        return;
    }

    // Sort by timestamp (newest first)
    const sortedData = [...data].sort((a, b) => {
        const tsA = typeof a.timestamp === 'number' ? a.timestamp : 0;
        const tsB = typeof b.timestamp === 'number' ? b.timestamp : 0;
        return tsB - tsA;
    });

    // Display first 20 records
    const displayData = sortedData.slice(0, 20);

    displayData.forEach(item => {
        const row = document.createElement('tr');

        // Format timestamp
        let timestamp = 'N/A';
        if (typeof item.timestamp === 'number') {
            timestamp = new Date(item.timestamp).toLocaleString();
        } else if (item.mergedAt) {
            timestamp = new Date(item.mergedAt).toLocaleString();
        }

        // Get text preview (truncate to 50 chars for display, full text on hover)
        let textPreview = item.textPreview || 'N/A';
        let fullText = textPreview;
        if (textPreview.length > 50) {
            textPreview = textPreview.substring(0, 50) + '...';
        }

        // Get sentiment
        const sentiment = item.sentiment || 'UNKNOWN';
        const sentimentClass = sentiment.toLowerCase();

        // Get confidence score
        let confidence = 'N/A';
        if (typeof item.sentimentScore === 'number') {
            confidence = (item.sentimentScore * 100).toFixed(1) + '%';
        }

        // Build entity badges
        let entitiesHtml = '<span class="no-data">None</span>';
        if (item.entities && item.entities.length > 0) {
            const badges = item.entities.slice(0, 4).map(entity => {
                return `<span class="entity-badge other">
                    <span class="entity-text">${escapeHtml(entity)}</span>
                </span>`;
            });
            if (item.entities.length > 4) {
                badges.push(`<span class="entity-badge other">+${item.entities.length - 4}</span>`);
            }
            entitiesHtml = `<div class="entity-list">${badges.join('')}</div>`;
        }

        // Create sentiment badge
        const sentimentBadge = `<span class="sentiment-badge ${sentimentClass}">${sentiment}</span>`;

        row.innerHTML = `
            <td>${timestamp}</td>
            <td class="text-preview" title="${escapeHtml(fullText)}">${escapeHtml(textPreview)}</td>
            <td>${sentimentBadge}</td>
            <td>${confidence}</td>
            <td>${entitiesHtml}</td>
        `;

        tbody.appendChild(row);
    });
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ========================================
// STEP 10: Loading & Error States
// ========================================
function setTableLoading(isLoading) {
    const tbody = document.getElementById('events-tbody');
    if (isLoading) {
        tbody.innerHTML = '<tr><td colspan="5" class="loading">Loading recent events...</td></tr>';
    }
}

function setChartLoading(isLoading, chartId) {
    const canvas = document.getElementById(chartId);
    if (!canvas) return;
    const container = canvas.parentElement;
    const loaderId = `${chartId}-loading`;

    if (isLoading && !document.getElementById(loaderId)) {
        const loader = document.createElement('div');
        loader.id = loaderId;
        loader.className = 'chart-loading';
        loader.textContent = 'Loading from Athena...';
        container.insertBefore(loader, container.firstChild);
    } else if (!isLoading) {
        const loader = document.getElementById(loaderId);
        if (loader) loader.remove();
    }
}

function showTableError(message) {
    const tbody = document.getElementById('events-tbody');
    tbody.innerHTML = `<tr><td colspan="5" class="error">${message}</td></tr>`;
}

function showChartError(message, chartId) {
    const canvas = document.getElementById(chartId);
    if (!canvas) return;
    const container = canvas.parentElement;
    const errorId = `${chartId}-error`;

    let errorDiv = document.getElementById(errorId);
    if (!errorDiv) {
        errorDiv = document.createElement('div');
        errorDiv.id = errorId;
        errorDiv.className = 'chart-error';
        container.insertBefore(errorDiv, container.firstChild);
    }
    errorDiv.textContent = message;
}

// ========================================
// STEP 11: Update Timestamp
// ========================================
function updateTimestamp() {
    const now = new Date().toLocaleTimeString();
    document.getElementById('last-update').textContent = now;
}

// ========================================
// STEP 12: Initialize on Page Load
// ========================================
window.addEventListener('load', function() {
    console.log('AI-DP Dashboard loaded!');
    console.log('Data sources (optimized strategy):');
    console.log('  - DynamoDB (real-time):', CONFIG.DYNAMODB_TABLE);
    console.log('  - Curated (S3):', CONFIG.DATA_LAKE_BUCKET + '/curated/latest_summary.json');
    console.log('  - Athena (entity UNNEST):', CONFIG.ATHENA_DATABASE + '.' + CONFIG.ATHENA_TABLE);
    loadData();
});

// ========================================
// STEP 13: Auto-refresh every 60 seconds
// ========================================
setInterval(function() {
    console.log('Auto-refreshing dashboard...');
    loadData();
}, 60000);
