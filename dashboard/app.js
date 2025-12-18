import { AthenaClient, StartQueryExecutionCommand, GetQueryExecutionCommand, GetQueryResultsCommand } from '@aws-sdk/client-athena';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand } from '@aws-sdk/lib-dynamodb';

// Configuration - Update for your environment
const CONFIG = {
    region: 'us-west-2',
    dynamoTableName: 'ai-dp-dev-enriched-data',
    glueDatabase: 'ai-dp-dev-analytics',
    glueTable: 'processed',
    athenaWorkgroup: 'ai-dp-dev-workgroup'
};

const athena = new AthenaClient({ region: CONFIG.region });
const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({ region: CONFIG.region }));

let chart = null;

async function runAthenaQuery(sql) {
    document.getElementById('status').textContent = 'Running Athena query...';

    const startResponse = await athena.send(new StartQueryExecutionCommand({
        QueryString: sql,
        WorkGroup: CONFIG.athenaWorkgroup
    }));
    const queryId = startResponse.QueryExecutionId;

    // Poll for completion
    let status = 'RUNNING';
    while (status === 'RUNNING' || status === 'QUEUED') {
        await new Promise(resolve => setTimeout(resolve, 1000));

        const checkResponse = await athena.send(new GetQueryExecutionCommand({
            QueryExecutionId: queryId
        }));
        status = checkResponse.QueryExecution.Status.State;

        if (status === 'FAILED') {
            throw new Error('Query failed: ' + checkResponse.QueryExecution.Status.StateChangeReason);
        }
    }

    const resultsResponse = await athena.send(new GetQueryResultsCommand({
        QueryExecutionId: queryId
    }));

    // Convert to array of objects
    const rows = resultsResponse.ResultSet.Rows;
    if (rows.length === 0) return [];

    const headers = rows[0].Data.map(col => col.VarCharValue);
    return rows.slice(1).map(row => {
        const obj = {};
        row.Data.forEach((col, i) => {
            obj[headers[i]] = col.VarCharValue;
        });
        return obj;
    });
}

async function getDynamoData() {
    document.getElementById('status').textContent = 'Querying DynamoDB...';

    const response = await dynamo.send(new ScanCommand({
        TableName: CONFIG.dynamoTableName,
        Limit: 20
    }));

    return response.Items || [];
}

window.loadData = async function() {
    try {
        document.getElementById('status').textContent = 'Loading...';

        const sentiments = await runAthenaQuery(`
            SELECT sentiment, COUNT(*) as count
            FROM "${CONFIG.glueDatabase}"."${CONFIG.glueTable}"
            GROUP BY sentiment
        `);

        // Update metrics
        const positive = sentiments.find(s => s.sentiment === 'POSITIVE');
        const negative = sentiments.find(s => s.sentiment === 'NEGATIVE');
        const neutral = sentiments.find(s => s.sentiment === 'NEUTRAL');

        document.getElementById('positiveCount').textContent = positive ? positive.count : '0';
        document.getElementById('negativeCount').textContent = negative ? negative.count : '0';
        document.getElementById('neutralCount').textContent = neutral ? neutral.count : '0';

        // Create chart
        const labels = sentiments.map(s => s.sentiment);
        const counts = sentiments.map(s => parseInt(s.count));

        if (chart) chart.destroy();

        chart = new Chart(document.getElementById('sentimentChart'), {
            type: 'pie',
            data: {
                labels: labels,
                datasets: [{
                    data: counts,
                    backgroundColor: ['#4CAF50', '#f44336', '#9e9e9e']
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });

        // Get recent events
        const events = await getDynamoData();
        document.getElementById('totalRecords').textContent = events.length;

        // Build table
        let tableHTML = '<table>';
        tableHTML += '<tr><th>Record ID</th><th>Timestamp</th><th>Sentiment</th><th>Type</th></tr>';

        events.forEach(event => {
            const timestamp = new Date(event.timestamp).toLocaleString();
            const sentimentClass = (event.sentiment || 'neutral').toLowerCase();

            tableHTML += '<tr>';
            tableHTML += `<td>${event.recordId || 'N/A'}</td>`;
            tableHTML += `<td>${timestamp}</td>`;
            tableHTML += `<td class="${sentimentClass}">${event.sentiment || 'N/A'}</td>`;
            tableHTML += `<td>${event.recordType || 'N/A'}</td>`;
            tableHTML += '</tr>';
        });

        tableHTML += '</table>';
        document.getElementById('eventsTable').innerHTML = tableHTML;

        document.getElementById('status').textContent = 'Last updated: ' + new Date().toLocaleTimeString();

    } catch (error) {
        document.getElementById('status').textContent = 'Error: ' + error.message;
        console.error('Dashboard error:', error);
        alert('Error loading dashboard. Check browser console for details.');
    }
};

loadData();
