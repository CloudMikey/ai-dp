"""Shared pytest fixtures for Lambda unit tests."""

import os
import sys
from pathlib import Path

# Set AWS region before importing Lambda handlers (they create clients at module level)
os.environ['AWS_DEFAULT_REGION'] = 'us-west-2'
os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'

# Add Lambda directories to Python path so tests can import handlers
lambdas_dir = Path(__file__).parent
sys.path.insert(0, str(lambdas_dir / 'etl'))
sys.path.insert(0, str(lambdas_dir / 'merge'))

import pytest
import boto3
from moto import mock_aws


#-------------------- Environment Setup --------------------#

@pytest.fixture(autouse=True)
def aws_credentials():
    """Mock AWS credentials for moto (prevents accidental real AWS calls)."""
    os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
    os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
    os.environ['AWS_SECURITY_TOKEN'] = 'testing'
    os.environ['AWS_SESSION_TOKEN'] = 'testing'
    os.environ['AWS_DEFAULT_REGION'] = 'us-west-2'


@pytest.fixture
def env_vars():
    """Standard environment variables for Lambda functions."""
    return {
        'DATA_LAKE_BUCKET': 'test-data-lake-bucket',
        'RAW_PREFIX': 'raw/',
        'PROCESSED_PREFIX': 'processed/',
        'CURATED_PREFIX': 'curated/',
        'DYNAMODB_TABLE': 'test-enriched-data',
        'TTL_DAYS': '30',
        'LOG_LEVEL': 'DEBUG',
        'AWS_LAMBDA_FUNCTION_NAME': 'test-lambda',
        'AWS_LAMBDA_FUNCTION_VERSION': '$LATEST'
    }


@pytest.fixture
def set_env_vars(env_vars, monkeypatch):
    """Apply environment variables to the test environment."""
    for key, value in env_vars.items():
        monkeypatch.setenv(key, value)
    return env_vars


#-------------------- S3 Fixtures --------------------#

@pytest.fixture
def s3_client():
    """Create mocked S3 client."""
    with mock_aws():
        client = boto3.client('s3', region_name='us-west-2')
        yield client


@pytest.fixture
def s3_bucket(s3_client, env_vars):
    """Create test S3 bucket."""
    bucket_name = env_vars['DATA_LAKE_BUCKET']
    s3_client.create_bucket(
        Bucket=bucket_name,
        CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
    )
    return bucket_name


#-------------------- DynamoDB Fixtures --------------------#

@pytest.fixture
def dynamodb_client():
    """Create mocked DynamoDB client."""
    with mock_aws():
        client = boto3.client('dynamodb', region_name='us-west-2')
        yield client


@pytest.fixture
def dynamodb_table(dynamodb_client, env_vars):
    """Create test DynamoDB table matching production schema."""
    table_name = env_vars['DYNAMODB_TABLE']
    dynamodb_client.create_table(
        TableName=table_name,
        KeySchema=[
            {'AttributeName': 'recordId', 'KeyType': 'HASH'}
        ],
        AttributeDefinitions=[
            {'AttributeName': 'recordId', 'AttributeType': 'S'}
        ],
        BillingMode='PAY_PER_REQUEST'
    )
    return table_name
