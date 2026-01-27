/**
 * Professional Load Test for AI-DP Streaming Pipeline
 *
 * This is how real engineers write load tests - using purpose-built tools.
 * k6 is used by GitLab, Microsoft, Grafana Labs, and many others.
 *
 * Install k6:
 *   Windows: choco install k6  OR  winget install k6
 *   Mac:     brew install k6
 *   Linux:   https://k6.io/docs/getting-started/installation/
 *
 * Run:
 *   k6 run scripts/load-test-streaming.js
 *
 * With custom endpoint:
 *   k6 run -e API_ENDPOINT=https://xxx.execute-api.us-west-2.amazonaws.com/ingest scripts/load-test-streaming.js
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// ============================================================
//                    CUSTOM METRICS
// ============================================================
// k6 tracks many metrics automatically, but we can add our own

const errorRate = new Rate('custom_errors');      // Percentage of failed requests
const latencyTrend = new Trend('custom_latency'); // Latency distribution

// ============================================================
//                    TEST CONFIGURATION
// ============================================================

export const options = {
  // Scenario: How the load is applied
  scenarios: {
    streaming_load_test: {
      executor: 'constant-vus',  // Keep constant number of virtual users
      vus: 50,                   // 50 concurrent users
      duration: '20s',           // Run for 20 seconds
      // This will generate ~1000 requests (50 users * 20 seconds * ~1 req/sec each)
    },
  },

  // Thresholds: Pass/fail criteria (same as our PowerShell script)
  thresholds: {
    http_req_failed: ['rate<0.01'],      // Less than 1% of requests can fail
    http_req_duration: ['p(95)<5000'],   // 95% of requests must be under 5 seconds
    custom_errors: ['rate<0.01'],        // Our custom error rate
  },
};

// ============================================================
//                    CONFIGURATION
// ============================================================

// Get API endpoint from environment variable or use default
const API_ENDPOINT = __ENV.API_ENDPOINT || 'https://pvqb2gzg7i.execute-api.us-west-2.amazonaws.com/ingest';

// ============================================================
//                    MAIN TEST FUNCTION
// ============================================================
// This function runs once per "iteration" for each virtual user
// __VU = Virtual User number (1-50)
// __ITER = Iteration number for this VU (0, 1, 2, ...)

export default function () {
  // Create the event payload (same format as PowerShell script)
  const payload = JSON.stringify({
    event_type: 'load_test',
    event_timestamp: new Date().toISOString(),
    event_id: `${__VU}-${__ITER}`,
    source: 'k6-load-test',
    test_run_id: `k6-${Date.now()}`,
    message: `Load test event from VU ${__VU}, iteration ${__ITER}`,
  });

  // Request headers (X-Partition-Key is required by our API Gateway)
  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Partition-Key': `k6-${__VU}-${__ITER}`,
    },
  };

  // Send the HTTP POST request
  const response = http.post(API_ENDPOINT, payload, params);

  // Record custom latency metric
  latencyTrend.add(response.timings.duration);

  // Validate the response
  const passed = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has SequenceNumber': (r) => r.body && r.body.includes('SequenceNumber'),
    'response has ShardId': (r) => r.body && r.body.includes('ShardId'),
  });

  // Record to our custom error rate metric
  errorRate.add(!passed);

  // Small pause between requests (100ms)
  // This prevents overwhelming the system and simulates realistic user behavior
  sleep(0.1);
}

// ============================================================
//                    SETUP (runs once before test)
// ============================================================

export function setup() {
  console.log('========================================');
  console.log('AI-DP Load Test - Streaming Pipeline');
  console.log('========================================');
  console.log(`Target: ${API_ENDPOINT}`);
  console.log(`Virtual Users: ${options.scenarios.streaming_load_test.vus}`);
  console.log(`Duration: ${options.scenarios.streaming_load_test.duration}`);
  console.log('');

  // Verify the endpoint is reachable
  const testPayload = JSON.stringify({
    event_type: 'setup_test',
    event_timestamp: new Date().toISOString(),
  });

  const response = http.post(API_ENDPOINT, testPayload, {
    headers: {
      'Content-Type': 'application/json',
      'X-Partition-Key': 'k6-setup-test',
    },
  });

  if (response.status !== 200) {
    console.error(`Setup check failed! Status: ${response.status}`);
    console.error(`Response: ${response.body}`);
  } else {
    console.log('Setup check passed - API is reachable');
  }

  return { startTime: Date.now() };
}

// ============================================================
//                    TEARDOWN (runs once after test)
// ============================================================

export function teardown(data) {
  const duration = (Date.now() - data.startTime) / 1000;
  console.log('');
  console.log('========================================');
  console.log('Test completed');
  console.log(`Total duration: ${duration.toFixed(1)} seconds`);
  console.log('========================================');
  console.log('');
  console.log('Next steps:');
  console.log('1. Check CloudWatch metrics for Lambda performance');
  console.log('2. Verify S3 has new objects in raw/ prefix');
  console.log('3. Check DLQ for any failed records');
}
