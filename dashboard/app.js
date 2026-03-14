// ========================================
// AI-DP Dashboard - Main Application
// ========================================
// Data Sources:
// - DynamoDB: Real-time metrics cards + recent events table (last 30 days)
// - S3 Curated: Top Entities bar chart (pre-aggregated, instant ~100ms)
// ========================================

// ========================================
// STEP 1: Configure AWS SDK
// ========================================
AWS.config.update({
    region: CONFIG.AWS_REGION,
    accessKeyId: CONFIG.AWS_ACCESS_KEY_ID,
    secretAccessKey: CONFIG.AWS_SECRET_ACCESS_KEY
});

const dynamoDB = new AWS.DynamoDB.DocumentClient();
const s3       = new AWS.S3();

// ========================================
// STEP 2: Global Variables
// ========================================
let entitiesChart = null;
let cachedDynamoDBItems  = [];
let cachedCuratedSummary = null;

// ========================================
// STEP 3: Main Load Function
// ========================================
async function loadData() {
    console.log('Reloading dashboard data...');
    updateTimestamp();

    await Promise.all([
        loadDynamoDBData(),
        loadCuratedSummary()
    ]);

    console.log('Dashboard data loaded.');
}

// ========================================
// STEP 4: DynamoDB - Real-time Recent Events
// ========================================
async function loadDynamoDBData() {
    setTableLoading(true);

    try {
        const result = await dynamoDB.scan({
            TableName: CONFIG.DYNAMODB_TABLE,
            Limit: 50
        }).promise();

        const allItems = result.Items || [];
        // Filter out internal metadata records (e.g. METRICS_SUMMARY) that have no sentiment
        const items = allItems.filter(item => item.sentiment);
        cachedDynamoDBItems = items;
        console.log(`DynamoDB: ${items.length} event records (${allItems.length} total including metadata)`);

        updateTable(items);
        updateMetrics(items);

    } catch (error) {
        console.error('DynamoDB error:', error);
        showTableError('Failed to load recent events from DynamoDB');
    } finally {
        setTableLoading(false);
    }
}

// ========================================
// STEP 5: S3 Curated Layer - Top Entities Chart
// ========================================
// Pre-aggregated by Merge Lambda on every write — instant response (~100ms)
async function loadCuratedSummary() {
    setChartLoading(true, 'entities-chart');

    try {
        const result = await s3.getObject({
            Bucket: CONFIG.DATA_LAKE_BUCKET,
            Key: 'curated/latest_summary.json'
        }).promise();

        const summary = JSON.parse(result.Body.toString('utf-8'));
        cachedCuratedSummary = summary;
        updateEntitiesChart(summary.top_entities || {});
        console.log(`Curated: ${summary.total_records} total records`);

    } catch (error) {
        console.error('Curated summary error:', error);
        showChartError('Curated summary not available', 'entities-chart');
    } finally {
        setChartLoading(false, 'entities-chart');
    }
}

// ========================================
// STEP 6: Send Test Event (Live Demo Button)
// ========================================
async function sendTestEvent() {
    const btn = document.getElementById('test-event-btn');
    const statusEl = document.getElementById('test-event-status');

    btn.disabled = true;
    btn.textContent = 'Sending...';
    statusEl.style.display = 'block';
    statusEl.className = 'test-event-info';
    statusEl.textContent = 'Sending event to Kinesis \u2192 Lambda \u2192 Comprehend pipeline...';

    const testPayload = {
        event_type: 'dashboard_test',
        event_timestamp: new Date().toISOString(),
        text: `Dashboard test event sent at ${new Date().toLocaleTimeString()} \u2014 sentiment analysis by Amazon Comprehend`,
        source: 'dashboard'
    };

    try {
        // Send directly to Kinesis (same path as API Gateway, avoids CORS issues)
        const kinesis = new AWS.Kinesis();
        await kinesis.putRecord({
            StreamName: CONFIG.KINESIS_STREAM,
            Data: JSON.stringify(testPayload),
            PartitionKey: 'dashboard-test'
        }).promise();

        statusEl.className = 'test-event-success';
        statusEl.textContent = 'Event sent to Kinesis! It will appear below after the pipeline processes it (~10-30s). Click Refresh to check.';

    } catch (error) {
        console.error('Send test event error:', error);
        statusEl.className = 'test-event-error';
        statusEl.textContent = `Failed to send event: ${error.message}`;
    } finally {
        btn.disabled = false;
        btn.textContent = 'Send Test Event';
    }
}

// ========================================
// STEP 7: Update Metrics Cards
// ========================================
function updateMetrics(data) {
    let positive = 0, neutral = 0, negative = 0, mixed = 0;

    data.forEach(item => {
        const s = item.sentiment;
        if (s === 'POSITIVE')  positive++;
        else if (s === 'NEUTRAL')   neutral++;
        else if (s === 'NEGATIVE')  negative++;
        else if (s === 'MIXED')     mixed++;
    });

    document.getElementById('total-records').textContent    = data.length;
    document.getElementById('positive-count').textContent   = positive;
    document.getElementById('neutral-count').textContent    = neutral;
    document.getElementById('negative-count').textContent   = negative;

    const mixedEl = document.getElementById('mixed-count');
    if (mixedEl) mixedEl.textContent = mixed;
}

// ========================================
// STEP 8: Top Entities Bar Chart (S3 Curated)
// ========================================
function updateEntitiesChart(topEntities) {
    if (entitiesChart) entitiesChart.destroy();

    const ctx    = document.getElementById('entities-chart').getContext('2d');
    const labels = Object.keys(topEntities);
    const data   = Object.values(topEntities);

    if (labels.length === 0) {
        showChartError('No entity data available', 'entities-chart');
        return;
    }

    // Color palette for bars
    const colors = [
        '#3b82f6', '#ec4899', '#10b981', '#f59e0b', '#6366f1',
        '#8b5cf6', '#14b8a6', '#f97316', '#ef4444', '#6b7280'
    ];

    entitiesChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: colors.slice(0, labels.length),
                borderWidth: 2,
                borderColor: '#fff'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        font: { size: 12 },
                        padding: 12,
                        generateLabels: function(chart) {
                            const d = chart.data;
                            return d.labels.map((label, i) => ({
                                text: `${label}: ${d.datasets[0].data[i]}`,
                                fillStyle: d.datasets[0].backgroundColor[i],
                                hidden: false,
                                index: i
                            }));
                        }
                    }
                },
                title: {
                    display: true,
                    text: 'Source: S3 Curated Layer (Comprehend NLP)',
                    font: { size: 11 },
                    color: '#888'
                }
            }
        }
    });
}

// ========================================
// STEP 9: Recent Events Table
// ========================================
function updateTable(data) {
    const tbody = document.getElementById('events-tbody');
    tbody.innerHTML = '';

    if (data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="no-data">No recent events found</td></tr>';
        return;
    }

    const sorted = [...data].sort((a, b) => {
        const tsA = typeof a.timestamp === 'number' ? a.timestamp : 0;
        const tsB = typeof b.timestamp === 'number' ? b.timestamp : 0;
        return tsB - tsA;
    });

    sorted.slice(0, 20).forEach(item => {
        const row = document.createElement('tr');

        let timestamp = 'N/A';
        if (typeof item.timestamp === 'number') {
            timestamp = new Date(item.timestamp).toLocaleString();
        } else if (item.mergedAt) {
            timestamp = new Date(item.mergedAt).toLocaleString();
        }

        const sentiment      = item.sentiment || 'UNKNOWN';
        const sentimentClass = sentiment.toLowerCase();

        let confidence = 'N/A';
        if (typeof item.sentimentScore === 'number') {
            confidence = (item.sentimentScore * 100).toFixed(1) + '%';
        }

        // Filter out timestamp/metadata strings that Comprehend misidentified as entities
        const realEntities = (item.entities || []).filter(e =>
            e && !e.match(/^\d{4}-\d{2}-/) && e !== '00:00' && !e.match(/^\.\d+/) &&
            !e.match(/^\d{1,2}:\d{2}/) && !e.includes('\\u')
        );

        let entitiesHtml = '<span class="no-data">None</span>';
        if (realEntities.length > 0) {
            const badges = realEntities.slice(0, 4).map(e =>
                `<span class="entity-badge other"><span class="entity-text">${escapeHtml(e)}</span></span>`
            );
            if (realEntities.length > 4) {
                badges.push(`<span class="entity-badge other">+${realEntities.length - 4}</span>`);
            }
            entitiesHtml = `<div class="entity-list">${badges.join('')}</div>`;
        }

        row.innerHTML = `
            <td>${timestamp}</td>
            <td><span class="sentiment-badge ${sentimentClass}">${sentiment}</span></td>
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
        tbody.innerHTML = '<tr><td colspan="4" class="loading">Loading recent events...</td></tr>';
    }
}

function setChartLoading(isLoading, chartId) {
    const canvas    = document.getElementById(chartId);
    if (!canvas) return;
    const container = canvas.parentElement;
    const loaderId  = `${chartId}-loading`;

    if (isLoading && !document.getElementById(loaderId)) {
        const loader = document.createElement('div');
        loader.id        = loaderId;
        loader.className = 'chart-loading';
        loader.textContent = 'Loading...';
        container.insertBefore(loader, container.firstChild);
    } else if (!isLoading) {
        const loader = document.getElementById(loaderId);
        if (loader) loader.remove();
    }
}

function showTableError(message) {
    document.getElementById('events-tbody').innerHTML =
        `<tr><td colspan="4" class="error">${message}</td></tr>`;
}

function showChartError(message, chartId) {
    const canvas = document.getElementById(chartId);
    if (!canvas) return;
    const container = canvas.parentElement;
    const errorId   = `${chartId}-error`;

    let errorDiv = document.getElementById(errorId);
    if (!errorDiv) {
        errorDiv = document.createElement('div');
        errorDiv.id        = errorId;
        errorDiv.className = 'chart-error';
        container.insertBefore(errorDiv, container.firstChild);
    }
    errorDiv.textContent = message;
}

// ========================================
// STEP 11: Timestamp
// ========================================
function updateTimestamp() {
    document.getElementById('last-update').textContent = new Date().toLocaleTimeString();
}

// ========================================
// STEP 12: Initialize & Auto-refresh
// ========================================
window.addEventListener('load', function() {
    console.log('AI-DP Dashboard loaded');
    loadData();
});

setInterval(function() {
    console.log('Auto-refreshing...');
    loadData();
}, 60000);
