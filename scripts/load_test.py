"""Load test for AI-DP streaming pipeline (Kinesis → ETL Lambda → S3)."""

import json
import time
import boto3
from datetime import datetime, timezone

# Setup
STREAM_NAME = 'ai-dp-dev-ingestion-stream'
REGION = 'us-west-2'

kinesis = boto3.client('kinesis', region_name=REGION)


def send_test_data(count=1000):
    """Send test events directly to Kinesis and print results."""
    print(f"\nStarting load test: Sending {count} records...")
    print(f"   Stream: {STREAM_NAME} ({REGION})\n")

    successes = 0
    failures = 0
    start_time = time.time()

    for i in range(count):
        payload = {
            "event_type": "load_test_ping",
            "event_timestamp": datetime.now(timezone.utc).isoformat(),
            "test_id": f"test_{i}",
            "value": i * 10
        }

        data_bytes = json.dumps(payload).encode('utf-8')

        try:
            response = kinesis.put_record(
                StreamName=STREAM_NAME,
                Data=data_bytes,
                PartitionKey=f"partition_{i % 5}"  # Distributes data across shards
            )
            print(f"[OK] Sent record {i+1}/{count} - Sequence: {response['SequenceNumber'][:20]}...")
            successes += 1
        except Exception as e:
            print(f"[FAIL] Failed record {i+1}/{count}: {e}")
            failures += 1

        time.sleep(0.01)  # 10ms delay — ~100 rec/s, safely under 1000/s shard limit

    # Summary
    elapsed = time.time() - start_time
    print(f"\n{'='*50}")
    print(f"LOAD TEST RESULTS")
    print(f"{'='*50}")
    print(f"  Total:     {count}")
    print(f"  Success:   {successes}")
    print(f"  Failed:    {failures}")
    print(f"  Duration:  {elapsed:.1f}s")
    print(f"  Rate:      {count/elapsed:.1f} events/sec")
    print(f"{'='*50}")

    if failures == 0:
        print("PASSED - All events sent successfully")
    else:
        print(f"FAILED - {failures} events failed")


if __name__ == '__main__':
    send_test_data()
