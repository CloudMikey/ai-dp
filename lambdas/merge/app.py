import json
import logging
import os
import uuid
from datetime import datetime, timezone
import boto3

# Environment variables (read once at cold start)
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

DATA_LAKE_BUCKET = os.environ.get('DATA_LAKE_BUCKET')
PROCESSED_PREFIX = os.environ.get('PROCESSED_PREFIX', 'processed/')
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE')
TTL_DAYS = int(os.environ.get('TTL_DAYS', '30'))

# AWS clients (initialized outside handler for connection reuse)
s3_client = boto3.client('s3')
dynamodb_client = boto3.client('dynamodb')


def lambda_handler(event, context):
    """
    Merge AI enrichment results and write to S3 processed/ + DynamoDB

    Args:
        event (dict): Step Functions output with source_object, ai_enrichment, processing_metadata
        context: Lambda context object (provides request ID, function name, etc.)

    Returns:
        dict: Status with written S3 key and DynamoDB recordId
    """
    logger.info(f"Received event: {json.dumps(event)}")

    validate_environment()

    source_object = event.get('source_object', {})
    ai_enrichment = event.get('ai_enrichment', {})
    processing_metadata = event.get('processing_metadata', {})

    enriched_data = merge_ai_results(source_object, ai_enrichment, processing_metadata)

    # Write to S3 first (MUST succeed)
    s3_key = write_to_s3_processed(enriched_data)

    # Write to DynamoDB (best effort - partial success allowed)
    try:
        record_id = write_to_dynamodb(enriched_data, s3_key)
        logger.info(f"✅ Full success: S3={s3_key}, DynamoDB={record_id}")
        return {
            'statusCode': 200,
            'processed_s3_key': s3_key,
            'dynamodb_record_id': record_id,
            'message': 'Full merge complete'
        }
    except Exception as dynamodb_error:
        logger.error(f"⚠️ DynamoDB write failed (data in S3): {str(dynamodb_error)}", exc_info=True)
        raise


def validate_environment():
    """Validate required environment variables are set"""
    if not DATA_LAKE_BUCKET:
        raise ValueError("DATA_LAKE_BUCKET environment variable not set")
    if not DYNAMODB_TABLE:
        raise ValueError("DYNAMODB_TABLE environment variable not set")

    logger.info(f"✅ Environment validated: bucket={DATA_LAKE_BUCKET}, table={DYNAMODB_TABLE}, ttl={TTL_DAYS}d")


def merge_ai_results(source_object, ai_enrichment, processing_metadata):
    """
    Combine Step Functions input into enriched data structure

    Args:
        source_object (dict): S3 location of raw data
        ai_enrichment (dict): Comprehend sentiment + entities
        processing_metadata (dict): Step Functions context

    Returns:
        dict: Merged record with all AI enrichments and metadata
    """
    sentiment = ai_enrichment.get('sentiment', {})
    entities = ai_enrichment.get('entities', {}).get('Entities', [])

    # Extract top sentiment and confidence
    top_sentiment = sentiment.get('Sentiment', 'UNKNOWN')
    sentiment_scores = sentiment.get('SentimentScore', {})
    top_sentiment_score = sentiment_scores.get(top_sentiment.capitalize(), 0.0)

    # Extract entity texts for simplified DynamoDB attribute
    entity_texts = [entity['Text'] for entity in entities if 'Text' in entity]

    # Generate unique record ID
    timestamp_str = processing_metadata.get('timestamp', datetime.now(timezone.utc).isoformat())
    record_id = f"{timestamp_str}-{uuid.uuid4().hex[:8]}"

    enriched = {
        'recordId': record_id,
        'timestamp': int(datetime.now(timezone.utc).timestamp() * 1000),
        'recordType': 'text',
        'sentiment': top_sentiment,
        'sentimentScore': round(top_sentiment_score, 4),
        'sentimentScores': sentiment_scores,
        'entities': entity_texts,
        'entityDetails': entities,
        'rawDataLocation': f"s3://{source_object.get('bucket')}/{source_object.get('key')}",
        'processingMetadata': processing_metadata,
        'mergedAt': datetime.now(timezone.utc).isoformat() + 'Z',
        'lambdaVersion': os.environ.get('AWS_LAMBDA_FUNCTION_VERSION', 'unknown'),
        'lambdaName': os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'unknown')
    }

    logger.info(f"📊 Merged record: {record_id}, sentiment={top_sentiment}({top_sentiment_score:.2f}), entities={len(entity_texts)}")
    return enriched


def write_to_s3_processed(enriched_data):
    """
    Write enriched data to S3 processed/ layer with date partitioning

    Args:
        enriched_data (dict): Merged record with AI enrichments

    Returns:
        str: S3 key where data was written
    """
    now = datetime.now(timezone.utc)
    partition = f"year={now.year}/month={now.month:02d}/day={now.day:02d}"
    object_key = f"{PROCESSED_PREFIX}{partition}/{uuid.uuid4()}.json"

    s3_client.put_object(
        Bucket=DATA_LAKE_BUCKET,
        Key=object_key,
        Body=json.dumps(enriched_data, indent=2),
        ContentType='application/json'
    )

    logger.info(f"💾 Wrote to S3: s3://{DATA_LAKE_BUCKET}/{object_key}")
    return object_key


def write_to_dynamodb(enriched_data, s3_key):
    """
    Write enriched record to DynamoDB hot store with TTL

    Args:
        enriched_data (dict): Merged record with AI enrichments
        s3_key (str): S3 key where enriched data was written

    Returns:
        str: recordId of written item
    """
    record_id = enriched_data['recordId']
    timestamp = enriched_data['timestamp']

    # Calculate TTL expiration (Unix epoch SECONDS)
    ttl_expiration = int(datetime.now(timezone.utc).timestamp()) + (TTL_DAYS * 86400)

    item = {
        'recordId': {'S': record_id},
        'timestamp': {'N': str(timestamp)},
        'recordType': {'S': enriched_data['recordType']},
        'sentiment': {'S': enriched_data['sentiment']},
        'sentimentScore': {'N': str(enriched_data['sentimentScore'])},
        'entities': {'L': [{'S': e} for e in enriched_data['entities']]},
        'rawDataLocation': {'S': enriched_data['rawDataLocation']},
        'processedDataLocation': {'S': f"s3://{DATA_LAKE_BUCKET}/{s3_key}"},
        'mergedAt': {'S': enriched_data['mergedAt']},
        'expiresAt': {'N': str(ttl_expiration)}
    }

    dynamodb_client.put_item(
        TableName=DYNAMODB_TABLE,
        Item=item
    )

    logger.info(f"🗄️ Wrote to DynamoDB: recordId={record_id}, TTL expires at {ttl_expiration} ({TTL_DAYS}d)")
    return record_id