"""
ETL Lambda: Kinesis → S3 Raw Layer

Reads from Kinesis, validates data, writes to S3 with date partitioning.
Date partitions (year=YYYY/month=MM) let Athena query faster by scanning less data.
"""

import base64
import json
import logging
import os
import uuid
from datetime import datetime
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize S3 client outside handler for connection reuse across invocations
s3_client = boto3.client('s3')

# Environment variables (set by Terraform)
DATA_LAKE_BUCKET = os.environ.get('DATA_LAKE_BUCKET')
RAW_PREFIX = os.environ.get('RAW_PREFIX', 'raw/')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and write to S3.
    If any record fails, the entire batch goes to DLQ for debugging.
    """
    logger.info(f"Processing {len(event['Records'])} records from Kinesis")

    # Validate required environment variables
    if not DATA_LAKE_BUCKET:
        raise ValueError("DATA_LAKE_BUCKET environment variable is not set")

    successful = 0
    failed = 0

    for record in event['Records']:
        try:
            # Process individual record
            result = process_record(record)
            logger.info(f"Successfully processed record: {result}")
            successful += 1

        except Exception as e:
            logger.error(f"Failed to process record: {str(e)}", exc_info=True)
            failed += 1
            # Re-raise to send batch to DLQ
            # In production, you might batch failures differently
            raise

    summary = {
        'successful': successful,
        'failed': failed,
        'total': len(event['Records'])
    }

    logger.info(f"Processing complete: {summary}")
    return summary


def process_record(record: Dict[str, Any]) -> Dict[str, str]:
    """
    Decode Kinesis record → Validate → Normalize → Write to S3.
    """
    # Kinesis stores data as base64
    encoded_data = record['kinesis']['data']
    decoded_data = base64.b64decode(encoded_data).decode('utf-8')
    data = json.loads(decoded_data)

    validated_data = validate_json(data)
    normalized_data = normalize_data(validated_data)

    # Extract timestamp for S3 partitioning
    timestamp_str = normalized_data.get('event_timestamp') or normalized_data.get('processed_at')
    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))

    s3_key = write_to_s3(normalized_data, timestamp)

    return {
        's3_key': s3_key,
        'status': 'success'
    }


def validate_json(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Check required fields: event_type and timestamp.
    """
    if 'event_type' not in data:
        raise ValueError("Missing required field: event_type")

    if 'event_timestamp' not in data and 'timestamp' not in data:
        raise ValueError("Missing required field: event_timestamp or timestamp")

    if not isinstance(data['event_type'], str):
        raise ValueError("event_type must be a string")

    return data


def normalize_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Standardize timestamps to ISO8601, add metadata.
    """
    normalized = data.copy()

    # Standardize field name
    if 'timestamp' in normalized and 'event_timestamp' not in normalized:
        normalized['event_timestamp'] = normalized.pop('timestamp')

    # Validate timestamp format
    timestamp_value = normalized.get('event_timestamp')
    if timestamp_value:
        try:
            datetime.fromisoformat(str(timestamp_value).replace('Z', '+00:00'))
        except (ValueError, TypeError):
            logger.warning(f"Invalid timestamp '{timestamp_value}', using current time")
            normalized['event_timestamp'] = datetime.utcnow().isoformat() + 'Z'

    # Add metadata
    normalized['processed_at'] = datetime.utcnow().isoformat() + 'Z'
    normalized['lambda_version'] = os.environ.get('AWS_LAMBDA_FUNCTION_VERSION', 'unknown')
    normalized['lambda_name'] = os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')

    return normalized


def write_to_s3(data: Dict[str, Any], timestamp: datetime) -> str:
    """
    Write to S3 with date partitions: raw/year=YYYY/month=MM/day=DD/{uuid}.json
    Athena can scan less data by filtering partitions (WHERE year=2025).
    """
    # Extract date parts for partitioning
    year = timestamp.strftime('%Y')
    month = timestamp.strftime('%m')
    day = timestamp.strftime('%d')
    unique_id = str(uuid.uuid4())

    s3_key = f"{RAW_PREFIX}year={year}/month={month}/day={day}/{unique_id}.json"

    # Convert data to JSON string
    json_data = json.dumps(data, indent=2)

    try:
        s3_client.put_object(
            Bucket=DATA_LAKE_BUCKET,
            Key=s3_key,
            Body=json_data,
            ContentType='application/json'
        )

        logger.info(f"Wrote to s3://{DATA_LAKE_BUCKET}/{s3_key}")
        return s3_key

    except ClientError as e:
        logger.error(f"S3 write failed: {str(e)}", exc_info=True)
        raise
