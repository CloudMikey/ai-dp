"""Rebuild curated/latest_summary.json from DynamoDB (the authoritative store).

The Merge Lambda maintains the summary incrementally, so drift is possible — a
conditional write that exhausts its retries under contention skips an increment
(docs/errorlog.md #6), and a partial /reset-data leaves the file and the table
disagreeing. This recomputes the file from scratch instead of adjusting it, so
running it twice produces the same result.

Scope matches the dashboard: DynamoDB holds a rolling 30-day window, so the
rebuilt totals describe recent records, not all-time history. S3 processed/ is
the permanent archive — query that through Athena for all-time counts.

Usage:
    python scripts/rebuild_summary.py --dry-run   # print what it would write
    python scripts/rebuild_summary.py             # write the file
"""

import argparse
import json
from collections import Counter
from datetime import datetime, timezone

import boto3

REGION = 'us-west-2'
TABLE = 'ai-dp-dev-enriched-data'
BUCKET = 'ai-dp-data-lake-dev-us-west-2'
SUMMARY_KEY = 'curated/latest_summary.json'
TOP_ENTITY_LIMIT = 10

dynamodb = boto3.client('dynamodb', region_name=REGION)
s3 = boto3.client('s3', region_name=REGION)


def scan_records():
    """Return every enriched record in the hot store."""
    records = []
    paginator = dynamodb.get_paginator('scan')
    for page in paginator.paginate(TableName=TABLE):
        records.extend(page.get('Items', []))
    # Internal bookkeeping items have no sentiment; the dashboard filters them too
    return [r for r in records if 'sentiment' in r]


def build_summary(records):
    """Fold records into the summary shape the dashboard expects."""
    sentiment_counts = {'POSITIVE': 0, 'NEGATIVE': 0, 'NEUTRAL': 0, 'MIXED': 0}
    entity_counts = Counter()

    for record in records:
        sentiment = record['sentiment']['S']
        if sentiment in sentiment_counts:
            sentiment_counts[sentiment] += 1
        for entity in record.get('entities', {}).get('L', []):
            text = entity.get('S', '')
            if text and len(text) > 2:  # matches the Merge Lambda's filter
                entity_counts[text] += 1

    newest = max(records, key=lambda r: int(r['timestamp']['N'])) if records else None
    oldest = min(records, key=lambda r: int(r['timestamp']['N'])) if records else None
    now = datetime.now(timezone.utc).isoformat() + 'Z'

    return {
        'sentiment_counts': sentiment_counts,
        'total_records': len(records),
        'top_entities': dict(entity_counts.most_common(TOP_ENTITY_LIMIT)),
        'first_record_at': oldest['mergedAt']['S'] if oldest and 'mergedAt' in oldest else now,
        'last_updated': now,
        'latest_sentiment': newest['sentiment']['S'] if newest else 'UNKNOWN',
        'latest_confidence': float(newest['sentimentScore']['N']) if newest and 'sentimentScore' in newest else 0,
        'latest_text_preview': newest.get('textPreview', {}).get('S', '')[:100] if newest else '',
    }


def read_current():
    """Current summary, or None if the file does not exist."""
    try:
        body = s3.get_object(Bucket=BUCKET, Key=SUMMARY_KEY)['Body'].read()
        return json.loads(body.decode('utf-8'))
    except s3.exceptions.NoSuchKey:
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='print without writing')
    args = parser.parse_args()

    records = scan_records()
    rebuilt = build_summary(records)
    current = read_current()

    print(f'DynamoDB records : {len(records)}')
    print(f'Current summary  : {current["total_records"] if current else "(missing)"}')
    print(f'Rebuilt summary  : {rebuilt["total_records"]}')

    if current and current['total_records'] != rebuilt['total_records']:
        drift = rebuilt['total_records'] - current['total_records']
        print(f'Drift detected   : {drift:+d} records unaccounted for')

    print()
    print(json.dumps(rebuilt, indent=2))

    if args.dry_run:
        print('\nDry run — nothing written.')
        return

    s3.put_object(
        Bucket=BUCKET,
        Key=SUMMARY_KEY,
        Body=json.dumps(rebuilt, indent=2),
        ContentType='application/json'
    )
    print(f'\nWrote s3://{BUCKET}/{SUMMARY_KEY}')


if __name__ == '__main__':
    main()
