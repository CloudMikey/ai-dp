"""Unit tests for Merge Lambda function."""

import json
import pytest
from datetime import datetime, timezone
from moto import mock_aws
from unittest.mock import patch
from botocore.exceptions import ClientError
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
    def test_extracts_plain_text_body(self, set_env_vars):
        """Batch path: uploaded .txt files are not JSON, so the body IS the text."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/batch-test/positive-delta.txt'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        body = "Delta Airlines made our trip to Atlanta wonderful.\n"
        client.put_object(Bucket=bucket, Key=key, Body=body)

        result = merge_handler.get_text_preview(bucket, key)

        assert result == "Delta Airlines made our trip to Atlanta wonderful."

    @mock_aws
    def test_truncates_long_plain_text(self, set_env_vars):
        """Plain-text bodies honour the same max_length as the JSON path."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/batch-test/long.txt'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body='x' * 600)

        result = merge_handler.get_text_preview(bucket, key, max_length=500)

        assert result == 'x' * 500 + '...'
        assert len(result) == 503

    @mock_aws
    def test_returns_none_for_empty_plain_text(self, set_env_vars):
        """An empty or whitespace-only file yields None, not an empty string."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/batch-test/blank.txt'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body='   \n  ')

        result = merge_handler.get_text_preview(bucket, key)

        assert result is None

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

    @mock_aws
    def test_filters_noise_entity_types(self, set_env_vars):
        """DATE/QUANTITY entities are dropped from entities; entityDetails keeps all."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket = 'test-data-lake-bucket'
        key = 'raw/test.json'
        client.create_bucket(
            Bucket=bucket,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )
        client.put_object(Bucket=bucket, Key=key, Body=json.dumps({'text': 'test'}))

        ai_enrichment = {
            'sentiment': {'Sentiment': 'NEUTRAL', 'SentimentScore': {'Neutral': 0.9}},
            'entities': {'Entities': [
                {'Text': 'Amazon', 'Type': 'ORGANIZATION', 'Score': 0.99},
                {'Text': '00:00', 'Type': 'DATE', 'Score': 0.9},
                {'Text': '3770', 'Type': 'QUANTITY', 'Score': 0.9},
            ]}
        }

        result = merge_handler.merge_ai_results(
            {'bucket': bucket, 'key': key},
            ai_enrichment,
            {'timestamp': '2026-01-25T12:00:00Z'}
        )

        assert result['entities'] == ['Amazon']
        assert {d['Text'] for d in result['entityDetails']} == {'Amazon', '00:00', '3770'}

    @mock_aws
    def test_merged_at_is_valid_iso8601(self, set_env_vars):
        """mergedAt is a single UTC 'Z' timestamp, not '+00:00Z'."""
        result = merge_handler.merge_ai_results(
            {'bucket': 'test-data-lake-bucket', 'key': 'raw/test.txt'},
            {},
            {'timestamp': '2026-01-25T12:00:00Z'}
        )

        merged_at = result['mergedAt']
        assert merged_at.endswith('Z')
        assert '+00:00' not in merged_at
        datetime.fromisoformat(merged_at)  # raises on '+00:00Z'


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

        # Inspect only number literals: a regex over the raw text also matched hex like
        # '19e0' inside the random recordId, so this test failed by chance
        float_literals = []
        json.loads(content, parse_float=lambda s: float_literals.append(s) or float(s))
        assert float_literals, "expected sentiment scores in the output"
        scientific = [s for s in float_literals if 'e' in s.lower()]
        assert not scientific, f"Found scientific notation: {scientific}"


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

    @mock_aws
    def test_retries_on_precondition_failure(self, set_env_vars):
        """A losing writer re-reads and reapplies rather than clobbering the winner."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'sentiment': 'POSITIVE',
            'sentimentScore': 0.95,
            'entities': ['Amazon'],
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': 'Sample text'
        }

        # Seed a summary so the first attempt takes the IfMatch path
        merge_handler.update_curated_summary(enriched_data)

        real_put = merge_handler.s3_client.put_object
        calls = {'n': 0}

        def flaky_put(**kwargs):
            calls['n'] += 1
            if calls['n'] == 1:
                raise ClientError(
                    {'Error': {'Code': 'PreconditionFailed', 'Message': 'stale etag'}},
                    'PutObject'
                )
            return real_put(**kwargs)

        with patch.object(merge_handler.s3_client, 'put_object', side_effect=flaky_put):
            key = merge_handler.update_curated_summary(enriched_data)

        assert key == 'curated/latest_summary.json'
        assert calls['n'] == 2, 'should have retried exactly once'

        response = client.get_object(Bucket='test-data-lake-bucket', Key=key)
        summary = json.loads(response['Body'].read().decode('utf-8'))
        # Both the seed and the retried write counted - nothing was lost
        assert summary['total_records'] == 2
        assert summary['sentiment_counts']['POSITIVE'] == 2

    @mock_aws
    def test_gives_up_after_max_retries(self, set_env_vars):
        """Sustained contention returns None instead of raising - summary is non-critical."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'sentiment': 'NEGATIVE',
            'sentimentScore': 0.9,
            'entities': [],
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': ''
        }

        always_conflict = ClientError(
            {'Error': {'Code': 'PreconditionFailed', 'Message': 'stale etag'}},
            'PutObject'
        )

        with patch.object(merge_handler.s3_client, 'put_object', side_effect=always_conflict):
            with patch.object(merge_handler.time, 'sleep'):  # keep the test fast
                key = merge_handler.update_curated_summary(enriched_data)

        assert key is None

    @mock_aws
    def test_create_path_uses_if_none_match(self, set_env_vars):
        """First write guards with IfNoneMatch so two creators cannot both win."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'sentiment': 'NEUTRAL',
            'sentimentScore': 0.8,
            'entities': [],
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': ''
        }

        real_put = merge_handler.s3_client.put_object
        seen = {}

        def capture(**kwargs):
            seen.update(kwargs)
            return real_put(**kwargs)

        with patch.object(merge_handler.s3_client, 'put_object', side_effect=capture):
            merge_handler.update_curated_summary(enriched_data)

        assert seen.get('IfNoneMatch') == '*'
        assert 'IfMatch' not in seen

    @mock_aws
    def test_update_path_uses_if_match(self, set_env_vars):
        """Subsequent writes pin the ETag that was read."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        enriched_data = {
            'sentiment': 'POSITIVE',
            'sentimentScore': 0.95,
            'entities': [],
            'mergedAt': '2026-01-25T12:00:00Z',
            'textPreview': ''
        }

        merge_handler.update_curated_summary(enriched_data)

        real_put = merge_handler.s3_client.put_object
        seen = {}

        def capture(**kwargs):
            seen.update(kwargs)
            return real_put(**kwargs)

        with patch.object(merge_handler.s3_client, 'put_object', side_effect=capture):
            merge_handler.update_curated_summary(enriched_data)

        assert 'IfMatch' in seen
        assert 'IfNoneMatch' not in seen

    @mock_aws
    def test_eight_merges_all_counted(self, set_env_vars):
        """The batch-upload scenario from errorlog #6: every record must be tallied."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        sentiments = ['POSITIVE'] * 3 + ['NEGATIVE'] * 3 + ['MIXED'] * 2
        for i, sentiment in enumerate(sentiments):
            merge_handler.update_curated_summary({
                'sentiment': sentiment,
                'sentimentScore': 0.9,
                'entities': [f'Entity{i}'],
                'mergedAt': '2026-01-25T12:00:00Z',
                'textPreview': ''
            })

        response = client.get_object(Bucket='test-data-lake-bucket', Key='curated/latest_summary.json')
        summary = json.loads(response['Body'].read().decode('utf-8'))

        assert summary['total_records'] == 8
        assert summary['sentiment_counts']['POSITIVE'] == 3
        assert summary['sentiment_counts']['NEGATIVE'] == 3
        assert summary['sentiment_counts']['MIXED'] == 2
        # Counts must be self-consistent - this is what broke in production
        assert sum(summary['sentiment_counts'].values()) == summary['total_records']


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
