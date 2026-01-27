"""Unit tests for ETL Lambda function."""

import json
import base64
import pytest
from datetime import datetime, timezone
from moto import mock_aws
import boto3

import etl_handler


#-------------------- Test lambda_handler --------------------#

class TestLambdaHandler:
    """Tests for the main lambda_handler function."""

    @mock_aws
    def test_single_record_success(self, set_env_vars, kinesis_event):
        """Happy path: Process single valid Kinesis record."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        result = etl_handler.lambda_handler(kinesis_event, None)

        assert result['successful'] == 1
        assert result['failed'] == 0
        assert result['total'] == 1

    @mock_aws
    def test_multiple_records_success(self, set_env_vars):
        """Process multiple valid records in single batch."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        records = []
        for i in range(3):
            data = {
                'event_type': f'event_{i}',
                'event_timestamp': '2026-01-25T12:00:00Z'
            }
            encoded = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')
            records.append({
                'kinesis': {
                    'sequenceNumber': f'4967019284827123984260265916366939871617492039222532505{i}',
                    'data': encoded
                }
            })

        result = etl_handler.lambda_handler({'Records': records}, None)

        assert result['successful'] == 3
        assert result['total'] == 3

    @mock_aws
    def test_invalid_record_raises_exception(self, set_env_vars, kinesis_record_missing_event_type):
        """Fail-fast: Invalid record raises exception."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        event = {'Records': [kinesis_record_missing_event_type]}

        with pytest.raises(ValueError, match="event_type"):
            etl_handler.lambda_handler(event, None)


#-------------------- Test process_record --------------------#

class TestProcessRecord:
    """Tests for the process_record function."""

    @mock_aws
    def test_returns_s3_key(self, set_env_vars, valid_kinesis_record):
        """Verify process_record returns S3 key on success."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        result = etl_handler.process_record(valid_kinesis_record)

        assert result['status'] == 'success'
        assert 's3_key' in result
        assert result['s3_key'].startswith('raw/')

    @mock_aws
    def test_uses_sequence_number_for_idempotency(self, set_env_vars, valid_kinesis_record):
        """S3 key should use Kinesis sequence number for idempotent writes."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        seq_num = valid_kinesis_record['kinesis']['sequenceNumber']
        result = etl_handler.process_record(valid_kinesis_record)

        assert seq_num in result['s3_key']


#-------------------- Test validate_json --------------------#

class TestValidateJson:
    """Tests for input validation."""

    def test_valid_data(self, set_env_vars):
        """Accept data with event_type and event_timestamp."""
        data = {'event_type': 'test', 'event_timestamp': '2026-01-25T12:00:00Z'}
        result = etl_handler.validate_json(data)
        assert result == data

    def test_missing_event_type(self, set_env_vars):
        """Reject data missing event_type."""
        data = {'event_timestamp': '2026-01-25T12:00:00Z'}
        with pytest.raises(ValueError, match="Missing required field: event_type"):
            etl_handler.validate_json(data)

    def test_missing_timestamp(self, set_env_vars):
        """Reject data missing both timestamp fields."""
        data = {'event_type': 'test'}
        with pytest.raises(ValueError, match="Missing required field: event_timestamp"):
            etl_handler.validate_json(data)

    def test_accepts_legacy_timestamp(self, set_env_vars):
        """Accept data with 'timestamp' instead of 'event_timestamp'."""
        data = {'event_type': 'test', 'timestamp': '2026-01-25T12:00:00Z'}
        result = etl_handler.validate_json(data)
        assert result == data

    def test_event_type_must_be_string(self, set_env_vars):
        """Reject non-string event_type."""
        data = {'event_type': 123, 'event_timestamp': '2026-01-25T12:00:00Z'}
        with pytest.raises(ValueError, match="event_type must be a string"):
            etl_handler.validate_json(data)


#-------------------- Test normalize_data --------------------#

class TestNormalizeData:
    """Tests for data normalization."""

    def test_adds_processed_at(self, set_env_vars):
        """Normalized data should include processed_at timestamp."""
        data = {'event_type': 'test', 'event_timestamp': '2026-01-25T12:00:00Z'}
        result = etl_handler.normalize_data(data)
        assert 'processed_at' in result
        assert result['processed_at'].endswith('Z')

    def test_converts_legacy_timestamp(self, set_env_vars):
        """Convert 'timestamp' to 'event_timestamp'."""
        data = {'event_type': 'test', 'timestamp': '2026-01-25T12:00:00Z'}
        result = etl_handler.normalize_data(data)
        assert 'event_timestamp' in result
        assert 'timestamp' not in result

    def test_adds_lambda_metadata(self, set_env_vars):
        """Normalized data should include Lambda function metadata."""
        data = {'event_type': 'test', 'event_timestamp': '2026-01-25T12:00:00Z'}
        result = etl_handler.normalize_data(data)
        assert result['lambda_name'] == 'test-lambda'
        assert result['lambda_version'] == '$LATEST'

    def test_does_not_mutate_original(self, set_env_vars):
        """Original data dict should not be modified."""
        data = {'event_type': 'test', 'event_timestamp': '2026-01-25T12:00:00Z'}
        original_keys = set(data.keys())
        etl_handler.normalize_data(data)
        assert set(data.keys()) == original_keys


#-------------------- Test write_to_s3 --------------------#

class TestWriteToS3:
    """Tests for S3 write operations."""

    @mock_aws
    def test_creates_date_partitioned_path(self, set_env_vars):
        """S3 key should use year/month/day partitioning."""
        client = boto3.client('s3', region_name='us-west-2')
        client.create_bucket(
            Bucket='test-data-lake-bucket',
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        data = {'event_type': 'test', 'event_timestamp': '2026-01-25T12:00:00Z'}
        timestamp = datetime(2026, 1, 25, 12, 0, 0, tzinfo=timezone.utc)
        seq_num = '12345678901234567890'

        s3_key = etl_handler.write_to_s3(data, timestamp, seq_num)

        assert 'year=2026' in s3_key
        assert 'month=01' in s3_key
        assert 'day=25' in s3_key

    @mock_aws
    def test_content_is_valid_json(self, set_env_vars):
        """Written S3 object should be valid JSON."""
        client = boto3.client('s3', region_name='us-west-2')
        bucket_name = 'test-data-lake-bucket'
        client.create_bucket(
            Bucket=bucket_name,
            CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
        )

        data = {'event_type': 'test', 'value': 123}
        timestamp = datetime(2026, 1, 25, 12, 0, 0, tzinfo=timezone.utc)
        seq_num = '12345678901234567890'

        s3_key = etl_handler.write_to_s3(data, timestamp, seq_num)

        response = client.get_object(Bucket=bucket_name, Key=s3_key)
        content = json.loads(response['Body'].read().decode('utf-8'))
        assert content['event_type'] == 'test'
        assert content['value'] == 123

    @mock_aws
    def test_handles_client_error(self, set_env_vars):
        """Raise exception on S3 write failure (bucket doesn't exist)."""
        from botocore.exceptions import ClientError

        data = {'event_type': 'test'}
        timestamp = datetime(2026, 1, 25, 12, 0, 0, tzinfo=timezone.utc)
        seq_num = '12345678901234567890'

        with pytest.raises(ClientError):
            etl_handler.write_to_s3(data, timestamp, seq_num)
