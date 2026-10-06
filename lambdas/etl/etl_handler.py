"""ETL Lambda: Kinesis → S3 Raw Layer with date partitioning for Athena."""

import base64
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

s3_client = boto3.client('s3')


def get_config():
    """Get configuration from environment variables."""
    bucket = os.environ.get('DATA_LAKE_BUCKET')
    if not bucket:
        raise ValueError("DATA_LAKE_BUCKET environment variable is not set")
    return {
        'bucket': bucket,
        'raw_prefix': os.environ.get('RAW_PREFIX', 'raw/')
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process Kinesis records and write to S3.

    Raises on the first bad record so Lambda retries the whole batch (S3 keys are
    sequence numbers, so re-writing earlier records is harmless). After 3 retries the
    event source mapping sends the batch to the DLQ.
    """
    logger.info(f"Processing {len(event['Records'])} records from Kinesis")

    get_config()  # fail fast if DATA_LAKE_BUCKET is missing

    successful = 0
    for record in event['Records']:
        try:
            result = process_record(record)
        except Exception as e:
            logger.error(f"Failed to process record: {str(e)}", exc_info=True)
            raise
        logger.info(f"Successfully processed record: {result}")
        successful += 1

    summary = {
        'successful': successful,
        'total': len(event['Records'])
    }

    logger.info(f"Processing complete: {summary}")
    return summary


def process_record(record: Dict[str, Any]) -> Dict[str, str]:
    """Decode Kinesis record → Validate → Normalize → Write to S3."""

    # Extract sequence number for idempotent S3 writes (prevents duplicates on retry)
    sequence_number = record['kinesis']['sequenceNumber']

    encoded_data = record['kinesis']['data']
    decoded_data = base64.b64decode(encoded_data).decode('utf-8')
    data = json.loads(decoded_data)
    # Base64 string → bytes → UTF-8 string → Python dict

    validated_data = validate_json(data)
    normalized_data = normalize_data(validated_data)


    timestamp_str = normalized_data.get('event_timestamp') or normalized_data.get('processed_at')
    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))

    s3_key = write_to_s3(normalized_data, timestamp, sequence_number)

    return {
        's3_key': s3_key,
        'status': 'success'
    }


def validate_json(data: Dict[str, Any]) -> Dict[str, Any]:
    """Check required fields: event_type and timestamp."""
    if 'event_type' not in data:
        raise ValueError("Missing required field: event_type")

    if 'event_timestamp' not in data and 'timestamp' not in data:
        raise ValueError("Missing required field: event_timestamp or timestamp")

    if not isinstance(data['event_type'], str):
        raise ValueError("event_type must be a string")

    return data


def normalize_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Standardize timestamps to ISO8601, add metadata."""
    normalized = data.copy()
    # Prevent mutation of original data

    if 'timestamp' in normalized and 'event_timestamp' not in normalized:
        normalized['event_timestamp'] = normalized.pop('timestamp')


    timestamp_value = normalized.get('event_timestamp')
    if timestamp_value:
        try:
            datetime.fromisoformat(str(timestamp_value).replace('Z', '+00:00'))
        except (ValueError, TypeError):
            logger.warning(f"Invalid timestamp '{timestamp_value}', using current time")
            normalized['event_timestamp'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

    normalized['processed_at'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    normalized['lambda_version'] = os.environ.get('AWS_LAMBDA_FUNCTION_VERSION', 'unknown')
    normalized['lambda_name'] = os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')

    return normalized


def write_to_s3(data: Dict[str, Any], timestamp: datetime, sequence_number: str) -> str:
    """Write to S3 with date partitions (raw/year=YYYY/month=MM/day=DD/) for Athena.

    Uses Kinesis sequence number for idempotent writes - retries overwrite same file.
    """
    config = get_config()
    bucket = config['bucket']
    raw_prefix = config['raw_prefix']

    year = timestamp.strftime('%Y')
    month = timestamp.strftime('%m')
    day = timestamp.strftime('%d')

    # Use sequence number instead of UUID for idempotent writes
    s3_key = f"{raw_prefix}year={year}/month={month}/day={day}/{sequence_number}.json"

    json_data = json.dumps(data, indent=2)

    try:
        s3_client.put_object(
            Bucket=bucket,
            Key=s3_key,
            Body=json_data,
            ContentType='application/json'
        )

        logger.info(f"Wrote to s3://{bucket}/{s3_key}")
        return s3_key

    except ClientError as e:
        logger.error(f"S3 write failed: {str(e)}", exc_info=True)
        raise
