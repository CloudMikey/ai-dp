// ========================================
// AI-DP Dashboard - Main Application
// ========================================
// Data Sources:
// - S3 curated summary: metric cards + Top Entities bar chart (pre-aggregated, one GetObject)
// - DynamoDB timestamp-index GSI: recent events table (newest 50)
// ========================================

AWS.config.update({
    region: CONFIG.AWS_REGION,
    accessKeyId: CONFIG.AWS_ACCESS_KEY_ID,
    secretAccessKey: CONFIG.AWS_SECRET_ACCESS_KEY
});

const dynamoDB = new AWS.DynamoDB.DocumentClient();
const s3       = new AWS.S3();

let entitiesChart = null;
let cachedDynamoDBItems  = [];
let cachedCuratedSummary = null;

async function loadData() {
    console.log('Reloading dashboard data...');
    updateTimestamp();

    await Promise.all([
        loadDynamoDBData(),
        loadCuratedSummary()
    ]);

    console.log('Dashboard data loaded.');
}

async function loadDynamoDBData() {
    setTableLoading(true);

    try {
        // Query the timestamp-index GSI (recordType HASH + timestamp RANGE) for true
        // newest-first results. A plain scan returns items in hash order, not by time,
        // so it can't power a "recent events" view and never surfaces new records.
        const result = await dynamoDB.query({
            TableName: CONFIG.DYNAMODB_TABLE,
            IndexName: 'timestamp-index',
            KeyConditionExpression: 'recordType = :rt',
            ExpressionAttributeValues: { ':rt': 'text' },
            ScanIndexForward: false, // newest first
            Limit: 50
        }).promise();

        const allItems = result.Items || [];
        // Filter out internal metadata records (e.g. METRICS_SUMMARY) that have no sentiment
        const items = allItems.filter(item => item.sentiment);
        cachedDynamoDBItems = items;
        console.log(`DynamoDB: ${items.length} recent event records`);

        updateTable(items);

    } catch (error) {
        console.error('DynamoDB error:', error);
        showTableError('Failed to load recent events from DynamoDB');
    } finally {
        setTableLoading(false);
    }
}

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
        // A pipeline that started empty has now produced data, so drop the earlier error
        const staleError = document.getElementById('entities-chart-error');
        if (staleError) staleError.remove();
        updateMetrics(summary);
        updateEntitiesChart(summary.top_entities || {});
        updateDataStatus(summary);
        console.log(`Curated: ${summary.total_records} total records`);

    } catch (error) {
        console.error('Curated summary error:', error);
        showChartError('Curated summary not available', 'entities-chart');
        document.getElementById('data-status').textContent = 'No records yet';
    } finally {
        setChartLoading(false, 'entities-chart');
    }
}

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

// Cards reflect pipeline-wide aggregates from the curated summary (total_records +
// sentiment_counts), not the recent-events sample — so they show true, self-consistent
// totals (the sentiment counts sum to the total) that update as the pipeline runs.
function updateMetrics(summary) {
    const counts = (summary && summary.sentiment_counts) || {};
    const total  = (summary && typeof summary.total_records === 'number') ? summary.total_records : 0;

    document.getElementById('total-records').textContent  = total;
    document.getElementById('positive-count').textContent = counts.POSITIVE || 0;
    document.getElementById('neutral-count').textContent  = counts.NEUTRAL  || 0;
    document.getElementById('negative-count').textContent = counts.NEGATIVE || 0;

    const mixedEl = document.getElementById('mixed-count');
    if (mixedEl) mixedEl.textContent = counts.MIXED || 0;

    updateSentimentBar(counts, total);
}

// Shows when data last arrived, which the footer's page-refresh time can't tell you
function updateDataStatus(summary) {
    const total = summary.total_records || 0;
    const lastRecord = new Date(summary.last_updated);
    const noun = total === 1 ? 'record' : 'records';

    document.getElementById('data-status').textContent = isNaN(lastRecord)
        ? `${total} ${noun}`
        : `${total} ${noun} · Last record ${lastRecord.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}`;
}

function updateSentimentBar(counts, total) {
    const bar    = document.getElementById('sentiment-bar');
    const legend = document.getElementById('sentiment-legend');
    bar.innerHTML = '';
    legend.innerHTML = '';

    if (total === 0) return;

    const parts = [];
    // Same order as the metric cards, so the two read together
    ['POSITIVE', 'NEUTRAL', 'NEGATIVE', 'MIXED'].forEach(sentiment => {
        const count = counts[sentiment] || 0;
        const name  = sentiment.charAt(0) + sentiment.slice(1).toLowerCase();
        const pct   = Math.round((count / total) * 100);
        parts.push(`${name} ${pct}%`);

        // A zero-width segment would still leave a stray gap in the bar
        if (count > 0) {
            const segment = document.createElement('div');
            segment.className = `sentiment-segment ${sentiment.toLowerCase()}`;
            segment.style.flexGrow = count;
            segment.title = `${name}: ${count} of ${total} (${pct}%)`;
            bar.appendChild(segment);
        }

        const item = document.createElement('span');
        item.className = 'sentiment-legend-item';
        item.innerHTML = `<span class="sentiment-swatch ${sentiment.toLowerCase()}"></span>${name} <strong>${pct}%</strong>`;
        legend.appendChild(item);
    });

    bar.setAttribute('aria-label', `Sentiment mix: ${parts.join(', ')}`);
}

function updateEntitiesChart(topEntities) {
    if (entitiesChart) entitiesChart.destroy();

    const ctx     = document.getElementById('entities-chart').getContext('2d');
    // The summary holds every entity's count; bars read top-down, so show the 10 most mentioned
    const entries = Object.entries(topEntities).sort((a, b) => b[1] - a[1]).slice(0, 10);

    if (entries.length === 0) {
        showChartError('No entity data available', 'entities-chart');
        return;
    }

    entitiesChart = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: entries.map(([label]) => label),
            datasets: [{
                label: 'Mentions',
                data: entries.map(([, count]) => count),
                backgroundColor: '#3b82f6',
                borderRadius: 4,
                borderSkipped: 'start',
                maxBarThickness: 18
            }]
        },
        options: {
            indexAxis: 'y',
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                x: {
                    beginAtZero: true,
                    ticks: { precision: 0, color: '#888' }, // counts are whole numbers
                    grid: { color: '#eee' },
                    border: { display: false }
                },
                y: {
                    ticks: { color: '#333', font: { size: 13 } },
                    grid: { display: false }
                }
            },
            plugins: {
                legend: { display: false }, // one series; the section title names it
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

function updateTable(data) {
    const tbody = document.getElementById('events-tbody');
    tbody.innerHTML = '';

    if (data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="no-data">No recent events found</td></tr>';
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

        // Full text lives in the title attribute; CSS clamps the visible cell to 4 lines
        const preview = item.textPreview || '';
        const previewHtml = preview
            ? `<td class="text-preview" title="${escapeHtml(preview)}"><div class="text-clamp">${escapeHtml(preview)}</div></td>`
            : '<td class="text-preview"><span class="no-data">—</span></td>';

        row.innerHTML = `
            <td class="time-cell">${timestamp}</td>
            <td><span class="sentiment-badge ${sentimentClass}">${sentiment}</span></td>
            <td>${confidence}</td>
            ${previewHtml}
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

// Loading & error states
function setTableLoading(isLoading) {
    const tbody = document.getElementById('events-tbody');
    if (isLoading) {
        tbody.innerHTML = '<tr><td colspan="5" class="loading">Loading recent events...</td></tr>';
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
        `<tr><td colspan="5" class="error">${message}</td></tr>`;
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

function updateTimestamp() {
    document.getElementById('last-update').textContent = new Date().toLocaleTimeString();
}

// Initial load + 60s auto-refresh
window.addEventListener('load', function() {
    console.log('AI-DP Dashboard loaded');
    loadData();
});

setInterval(function() {
    console.log('Auto-refreshing...');
    loadData();
}, 60000);
