"""Unit tests for Merge Lambda function."""

import json
import re
import pytest
from datetime import datetime, timezone
from moto import mock_aws
import boto3

import merge_handler


class TestDecimalEncoder:
    """Tests for the DecimalEncoder JSON class."""

    def test_prevents_scientific_notation(self, set_env_vars):
        """Float values should not use scientific notation."""
        data = {'score': 0.000001}
        result = merge_handler.DecimalEncoder().encode(data)

        assert 'e-' not in result
        assert 'E-' not in result
        assert '0.000001' in result

    def test_handles_nested_objects(self, set_env_vars):
        """Nested dicts and lists should be properly encoded."""
        data = {'outer': {'inner': [0.000001, 0.000002]}}
        result = merge_handler.DecimalEncoder().encode(data)
        parsed = json.loads(result)

        assert parsed['outer']['inner'][0] == 0.000001
        assert parsed['outer']['inner'][1] == 0.000002

    def test_handles_standard_types(self, set_env_vars):
        """Standard JSON types should be handled correctly."""
        data = {
            'string': 'hello',
            'integer': 42,
            'boolean': True,
            'null': None,
            'list': [1, 2, 3]
        }
        result = merge_handler.DecimalEncoder().encode(data)
        parsed = json.loads(result)

        assert parsed['string'] == 'hello'
        assert parsed['integer'] == 42
        assert parsed['boolean'] is True
        assert parsed['null'] is None


class TestValidateEnvironment:
    """Tests for environment validation."""

    def test_success(self, set_env_vars):
        """Pass when all required env vars are set."""
        merge_handler.validate_environment()  # Should not raise


class TestGetTextPreview:
    """Tests for text preview extraction from S3."""

    @mock_aws
    def test_extracts_text_field(self, set_env_vars, raw_s3_object_content):
        """Extract text from 'text' field in raw S3 object."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/test.json'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body=json.dumps(raw_s3_object_content))

        result = merge_handler.get_text_preview(bucket, key)

        assert result == raw_s3_object_content['text']

    @mock_aws
    def test_truncates_long_text(self, set_env_vars):
        """Text longer than max_length should be truncated."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/test.json'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body=json.dumps({'text': 'A' * 1000}))

        result = merge_handler.get_text_preview(bucket, key, max_length=100)

        assert len(result) == 103  # 100 + "..."
        assert result.endswith('...')

    @mock_aws
    def test_returns_none_for_missing_text(self, set_env_vars):
        """Return None when no text field exists."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/test.json'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body=json.dumps({'event_type': 'test'}))

        result = merge_handler.get_text_preview(bucket, key)

        assert result is None

    @mock_aws
    def test_handles_s3_error(self, set_env_vars):
        """Return None when S3 object doesn't exist."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        result = merge_handler.get_text_preview('test-data-lake-bucket', 'nonexistent.json')

        assert result is None


class TestMergeAiResults:
    """Tests for AI result merging logic."""

    @mock_aws
    def test_creates_enriched_record(self, set_env_vars, valid_step_functions_event, raw_s3_object_content):
        """Create enriched record with sentiment and entities."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = valid_step_functions_event['source_object']['bucket']
        key = valid_step_functions_event['source_object']['key']
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body=json.dumps(raw_s3_object_content))

        result = merge_handler.merge_ai_results(
            valid_step_functions_event['source_object'],
            valid_step_functions_event['ai_enrichment'],
            valid_step_functions_event['processing_metadata']
        )

        assert result['sentiment'] == 'POSITIVE'
        assert result['sentimentScore'] == 0.95
        assert 'Amazon' in result['entities']
        assert 'Seattle' in result['entities']

    @mock_aws
    def test_handles_empty_enrichment(self, set_env_vars, event_with_empty_enrichment):
        """Handle missing/empty AI enrichment gracefully."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = event_with_empty_enrichment['source_object']['bucket']
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(
            Bucket=bucket,
            Key=event_with_empty_enrichment['source_object']['key'],
            Body=json.dumps({'text': 'test'})
        )

        result = merge_handler.merge_ai_results(
            event_with_empty_enrichment['source_object'],
            event_with_empty_enrichment['ai_enrichment'],
            event_with_empty_enrichment['processing_metadata']
        )

        assert result['sentiment'] == 'UNKNOWN'
        assert result['sentimentScore'] == 0.0
        assert result['entities'] == []


class TestWriteToS3Processed:
    """Tests for S3 processed layer writes."""

    @mock_aws
    def test_creates_partitioned_path(self, set_env_vars):
        """S3 key should use date partitioning."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'recordId': 'test-123',
            'sentiment': 'POSITIVE',
            'sentimentScore': 0.95,
            'sentimentScores': {'Positive': 0.95, 'Negative': 0.01}
        }

        s3_key = merge_handler.write_to_s3_processed(enriched_data)

        assert s3_key.startswith('processed/')
        assert 'year=' in s3_key
        assert 'month=' in s3_key
        assert 'day=' in s3_key

    @mock_aws
    def test_no_scientific_notation_in_output(self, set_env_vars, event_with_scientific_notation_scores):
        """Written JSON should not contain scientific notation."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(
            Bucket=bucket,
            Key=event_with_scientific_notation_scores['source_object']['key'],
            Body=json.dumps({'text': 'test'})
        )

        enriched = merge_handler.merge_ai_results(
            event_with_scientific_notation_scores['source_object'],
            event_with_scientific_notation_scores['ai_enrichment'],
            event_with_scientific_notation_scores['processing_metadata']
        )
        s3_key = merge_handler.write_to_s3_processed(enriched)

        response = client.get_object(Bucket=bucket, Key=s3_key)
        content = response['Body'].read().decode('utf-8')

        # Check for scientific notation patterns (e.g., 1e-06)
        scientific_pattern = r'\d+\.?\d*[eE][+-]?\d+'
        matches = re.findall(scientific_pattern, content)
        assert len(matches) == 0, f"Found scientific notation: {matches}"


class TestWriteToDynamodb:
    """Tests for DynamoDB hot store writes."""

    @mock_aws
    def test_creates_record(self, set_env_vars):
        """Write enriched record to DynamoDB."""
        client = boto3.client('dynamodb', region_name='us-west-2')
        client.create_table(
            TableName='test-enriched-data',
            KeySchema=[{'AttributeName': 'recordId', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'recordId', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )

        enriched_data = {
            'recordId': 'test-record-123',
            'timestamp': 1706184000000,
            'recordType': 'text',
            'sentiment': 'POSITIVE',
            'sentimentScore': 0.95,
            'entities': ['Amazon', 'Seattle'],
            'rawDataLocation': 's3://bucket/raw/test.json',
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': 'Sample text'
        }

        record_id = merge_handler.write_to_dynamodb(enriched_data, 'processed/test.json')

        assert record_id == 'test-record-123'

        response = client.get_item(
            TableName='test-enriched-data',
            Key={'recordId': {'S': 'test-record-123'}}
        )
        assert response['Item']['sentiment']['S'] == 'POSITIVE'

    @mock_aws
    def test_includes_ttl(self, set_env_vars):
        """DynamoDB record should include TTL expiration."""
        client = boto3.client('dynamodb', region_name='us-west-2')
        client.create_table(
            TableName='test-enriched-data',
            KeySchema=[{'AttributeName': 'recordId', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'recordId', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )

        enriched_data = {
            'recordId': 'test-record-456',
            'timestamp': 1706184000000,
            'recordType': 'text',
            'sentiment': 'NEUTRAL',
            'sentimentScore': 0.5,
            'entities': [],
            'rawDataLocation': 's3://bucket/raw/test.json',
            'mergedAt': '2026-01-25T12:00:00Z'
        }

        merge_handler.write_to_dynamodb(enriched_data, 'processed/test.json')

        response = client.get_item(
            TableName='test-enriched-data',
            Key={'recordId': {'S': 'test-record-456'}}
        )
        assert 'expiresAt' in response['Item']


class TestUpdateCuratedSummary:
    """Tests for curated layer summary updates."""

    @mock_aws
    def test_creates_new_summary(self, set_env_vars):
        """Create new summary when none exists."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'sentiment': 'POSITIVE',
            'sentimentScore': 0.95,
            'entities': ['Amazon', 'AWS'],
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': 'Sample text'
        }

        summary_key = merge_handler.update_curated_summary(enriched_data)

        assert summary_key == 'curated/latest_summary.json'

        response = client.get_object(Bucket='test-data-lake-bucket', Key=summary_key)
        summary = json.loads(response['Body'].read().decode('utf-8'))
        assert summary['total_records'] == 1
        assert summary['sentiment_counts']['POSITIVE'] == 1


class TestLambdaHandler:
    """Integration tests for the main lambda_handler."""

    @mock_aws
    def test_full_success(self, set_env_vars, valid_step_functions_event, raw_s3_object_content):
        """Full happy path: S3 + DynamoDB + Curated."""
        s3_client = boto3.client('s3', region_name='us-west-2')
        dynamodb_client = boto3.client('dynamodb', region_name='us-west-2')

        s3_client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        s3_client.put_object(
            Bucket='test-data-lake-bucket',
            Key=valid_step_functions_event['source_object']['key'],
            Body=json.dumps(raw_s3_object_content)
        )

        dynamodb_client.create_table(
            TableName='test-enriched-data',
            KeySchema=[{'AttributeName': 'recordId', 'KeyType': 'HASH'}],
            AttributeDefinitions=[{'AttributeName': 'recordId', 'AttributeType': 'S'}],
            BillingMode='PAY_PER_REQUEST'
        )

        result = merge_handler.lambda_handler(valid_step_functions_event, None)

        assert result['statusCode'] == 200
        assert 'processed_s3_key' in result
        assert 'dynamodb_record_id' in result
        assert result['message'] == 'Full merge complete'
