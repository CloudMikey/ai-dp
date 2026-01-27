import json
import logging
import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal
import boto3

LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')


class DecimalEncoder(json.JSONEncoder):
    """Custom JSON encoder that formats floats without scientific notation.

    This fixes Athena HIVE_CURSOR_ERROR caused by OpenX JsonSerDe not parsing
    scientific notation (e.g., 3.683771e-06) in nested structs.
    """
    def encode(self, obj):
        
        if isinstance(obj, dict):
            parts = []

            for key, value in obj.items():
                key_text = json.dumps(key)          # make key JSON-safe
                value_text = self.encode(value)     # encode value (recursive)
                parts.append(f"{key_text}: {value_text}")

            body = ", ".join(parts)
            return "{" + body + "}"
        
        elif isinstance(obj, list):
            items = []

            for item in obj:
                items.append(self.encode(item))     # encode each item

            body = ", ".join(items)
            return "[" + body + "]"
        
        elif isinstance(obj, float):
            # Convert to decimal (no scientific notation)
            text = f"{obj:.10f}"
            text = text.rstrip("0").rstrip(".")
            return text
        
        elif isinstance(obj, (int, bool)) or obj is None:
            return json.dumps(obj)
        elif isinstance(obj, str):
            return json.dumps(obj)
        else:
            return json.dumps(obj)


logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

s3_client = boto3.client('s3')
dynamodb_client = boto3.client('dynamodb')


def get_config():
    """Get configuration from environment variables."""
    bucket = os.environ.get('DATA_LAKE_BUCKET')
    table = os.environ.get('DYNAMODB_TABLE')
    return {
        'bucket': bucket,
        'table': table,
        'processed_prefix': os.environ.get('PROCESSED_PREFIX', 'processed/'),
        'curated_prefix': os.environ.get('CURATED_PREFIX', 'curated/'),
        'ttl_days': int(os.environ.get('TTL_DAYS', '30'))
    }


def lambda_handler(event, context):
    """Merge AI enrichment results and write to S3 processed/ + DynamoDB."""
    logger.info(f"Received event: {json.dumps(event)}")

    validate_environment()

    source_object = event.get('source_object', {})
    ai_enrichment = event.get('ai_enrichment', {})
    processing_metadata = event.get('processing_metadata', {})

    enriched_data = merge_ai_results(source_object, ai_enrichment, processing_metadata)


    s3_key = write_to_s3_processed(enriched_data)


    try:
        record_id = write_to_dynamodb(enriched_data, s3_key)

        # Update curated layer summary (non-critical, don't fail if this errors)
        try:
            curated_key = update_curated_summary(enriched_data)
        except Exception as curated_error:
            logger.warning(f"⚠️ Curated summary update failed (non-critical): {str(curated_error)}")
            curated_key = None

        logger.info(f"✅ Full success: S3={s3_key}, DynamoDB={record_id}, Curated={curated_key}")
        return {
            'statusCode': 200,
            'processed_s3_key': s3_key,
            'dynamodb_record_id': record_id,
            'curated_summary_key': curated_key,
            'message': 'Full merge complete'
        }
    except Exception as dynamodb_error:
        logger.error(f"⚠️ DynamoDB write failed (data in S3): {str(dynamodb_error)}", exc_info=True)
        raise


def validate_environment():
    """Validate required environment variables."""
    config = get_config()
    if not config['bucket']:
        raise ValueError("DATA_LAKE_BUCKET environment variable not set")
    if not config['table']:
        raise ValueError("DYNAMODB_TABLE environment variable not set")

    logger.info(f"✅ Environment validated: bucket={config['bucket']}, table={config['table']}, ttl={config['ttl_days']}d")


def get_text_preview(bucket, key, max_length=500):
    """Fetch original text from S3 raw file for dashboard preview.

    Args:
        bucket: S3 bucket name
        key: S3 object key
        max_length: Maximum characters to store (default 500)

    Returns:
        Truncated text preview string, or None if extraction fails
    """
    try:
        response = s3_client.get_object(Bucket=bucket, Key=key)
        raw_data = json.loads(response['Body'].read().decode('utf-8'))

        # Extract text from common field names
        text = (
            raw_data.get('text') or
            raw_data.get('content') or
            raw_data.get('message') or
            raw_data.get('body') or
            None
        )

        if not text:
            logger.debug("No text field found in raw data")
            return None

        # Truncate for DynamoDB storage efficiency
        if len(text) > max_length:
            return text[:max_length] + "..."
        return text

    except Exception as e:
        logger.warning(f"Could not fetch text preview from s3://{bucket}/{key}: {e}")
        return None


def merge_ai_results(source_object, ai_enrichment, processing_metadata):
    """Combine Step Functions input into enriched data structure."""
    # Fetch text preview from raw S3 file for dashboard display
    text_preview = get_text_preview(
        source_object.get('bucket'),
        source_object.get('key')
    )

    sentiment = ai_enrichment.get('sentiment', {})
    entities = ai_enrichment.get('entities', {}).get('Entities', [])

    top_sentiment = sentiment.get('Sentiment', 'UNKNOWN')
    raw_scores = sentiment.get('SentimentScore', {})
    top_sentiment_score = raw_scores.get(top_sentiment.capitalize(), 0.0)

    # Format sentiment scores without scientific notation (fixes Athena HIVE_CURSOR_ERROR)
    # Python's default JSON serialization uses scientific notation for very small floats
    # which the OpenX JsonSerDe in Athena/Glue cannot parse correctly
    sentiment_scores = {
        'Positive': float(f"{raw_scores.get('Positive', 0.0):.10f}"),
        'Negative': float(f"{raw_scores.get('Negative', 0.0):.10f}"),
        'Neutral': float(f"{raw_scores.get('Neutral', 0.0):.10f}"),
        'Mixed': float(f"{raw_scores.get('Mixed', 0.0):.10f}")
    }


    entity_texts = [entity['Text'] for entity in entities if 'Text' in entity]

    # Format entity details without scientific notation in Score field
    entity_details = []
    for entity in entities:
        entity_details.append({
            'BeginOffset': entity.get('BeginOffset', 0),
            'EndOffset': entity.get('EndOffset', 0),
            'Score': float(f"{entity.get('Score', 0.0):.10f}"),
            'Text': entity.get('Text', ''),
            'Type': entity.get('Type', '')
        })

    timestamp_str = processing_metadata.get('timestamp', datetime.now(timezone.utc).isoformat())
    record_id = f"{timestamp_str}-{uuid.uuid4().hex[:8]}"

    enriched = {
        'recordId': record_id,
        'timestamp': int(datetime.now(timezone.utc).timestamp() * 1000),
        'recordType': 'text',
        'textPreview': text_preview,
        'sentiment': top_sentiment,
        'sentimentScore': round(top_sentiment_score, 4),
        'sentimentScores': sentiment_scores,
        'entities': entity_texts,
        'entityDetails': entity_details,
        'rawDataLocation': f"s3://{source_object.get('bucket')}/{source_object.get('key')}",
        'processingMetadata': processing_metadata,
        'mergedAt': datetime.now(timezone.utc).isoformat() + 'Z',
        'lambdaVersion': os.environ.get('AWS_LAMBDA_FUNCTION_VERSION', 'unknown'),
        'lambdaName': os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')
    }

    logger.info(f"📊 Merged record: {record_id}, sentiment={top_sentiment}({top_sentiment_score:.2f}), entities={len(entity_texts)}")
    return enriched


def write_to_s3_processed(enriched_data):
    """Write enriched data to S3 processed/ with date partitioning."""
    config = get_config()
    now = datetime.now(timezone.utc)
    partition = f"year={now.year}/month={now.month:02d}/day={now.day:02d}"
    object_key = f"{config['processed_prefix']}{partition}/{uuid.uuid4()}.json"

    # Use custom encoder to avoid scientific notation in floats
    json_body = DecimalEncoder().encode(enriched_data)

    s3_client.put_object(
        Bucket=config['bucket'],
        Key=object_key,
        Body=json_body,
        ContentType='application/json'
    )

    logger.info(f"💾 Wrote to S3: s3://{config['bucket']}/{object_key}")
    return object_key


def write_to_dynamodb(enriched_data, s3_key):
    """Write enriched record to DynamoDB hot store with TTL."""
    config = get_config()
    record_id = enriched_data['recordId']
    timestamp = enriched_data['timestamp']

    ttl_expiration = int(datetime.now(timezone.utc).timestamp()) + (config['ttl_days'] * 86400)

    item = {
        'recordId': {'S': record_id},
        'timestamp': {'N': str(timestamp)},
        'recordType': {'S': enriched_data['recordType']},
        'sentiment': {'S': enriched_data['sentiment']},
        'sentimentScore': {'N': str(enriched_data['sentimentScore'])},
        'entities': {'L': [{'S': e} for e in enriched_data['entities']]},
        'rawDataLocation': {'S': enriched_data['rawDataLocation']},
        'processedDataLocation': {'S': f"s3://{config['bucket']}/{s3_key}"},
        'mergedAt': {'S': enriched_data['mergedAt']},
        'expiresAt': {'N': str(ttl_expiration)}
    }

    # Add textPreview if available (optional field for dashboard display)
    if enriched_data.get('textPreview'):
        item['textPreview'] = {'S': enriched_data['textPreview']}

    dynamodb_client.put_item(
        TableName=config['table'],
        Item=item
    )

    logger.info(f"🗄️ Wrote to DynamoDB: recordId={record_id}, TTL expires at {ttl_expiration} ({config['ttl_days']}d)")
    return record_id


def update_curated_summary(enriched_data):
    """Update the curated layer with a running summary for fast dashboard access.

    This demonstrates the 3-tier data lake pattern:
    - Raw: Original ingested data
    - Processed: AI-enriched data
    - Curated: Business-ready aggregated summaries
    """
    config = get_config()
    summary_key = f"{config['curated_prefix']}latest_summary.json"

    # Try to read existing summary, or create new one
    try:
        response = s3_client.get_object(Bucket=config['bucket'], Key=summary_key)
        summary = json.loads(response['Body'].read().decode('utf-8'))
    except s3_client.exceptions.NoSuchKey:
        # First record - initialize summary
        summary = {
            'sentiment_counts': {'POSITIVE': 0, 'NEGATIVE': 0, 'NEUTRAL': 0, 'MIXED': 0},
            'total_records': 0,
            'top_entities': {},
            'first_record_at': enriched_data['mergedAt']
        }
    except Exception as e:
        logger.warning(f"Could not read existing summary, creating new: {e}")
        summary = {
            'sentiment_counts': {'POSITIVE': 0, 'NEGATIVE': 0, 'NEUTRAL': 0, 'MIXED': 0},
            'total_records': 0,
            'top_entities': {},
            'first_record_at': enriched_data['mergedAt']
        }

    # Update counts
    sentiment = enriched_data.get('sentiment', 'UNKNOWN')
    if sentiment in summary['sentiment_counts']:
        summary['sentiment_counts'][sentiment] += 1
    summary['total_records'] += 1

    # Track top entities (keep top 10 by count)
    for entity in enriched_data.get('entities', []):
        if entity and len(entity) > 2:  # Skip very short strings
            summary['top_entities'][entity] = summary['top_entities'].get(entity, 0) + 1

    # Sort and keep only top 10 entities
    sorted_entities = sorted(summary['top_entities'].items(), key=lambda x: x[1], reverse=True)[:10]
    summary['top_entities'] = dict(sorted_entities)

    # Update metadata
    summary['last_updated'] = enriched_data['mergedAt']
    summary['latest_sentiment'] = sentiment
    summary['latest_confidence'] = enriched_data.get('sentimentScore', 0)
    summary['latest_text_preview'] = enriched_data.get('textPreview', '')[:100] if enriched_data.get('textPreview') else ''

    # Write updated summary
    s3_client.put_object(
        Bucket=config['bucket'],
        Key=summary_key,
        Body=json.dumps(summary, indent=2),
        ContentType='application/json'
    )

    logger.info(f"📈 Updated curated summary: total={summary['total_records']}, sentiment={sentiment}")
    return summary_key