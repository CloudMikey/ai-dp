"""ETL Lambda test fixtures."""

import base64
import json
import pytest


@pytest.fixture
def valid_kinesis_data():
    """Valid payload with all required fields."""
    return {
        'event_type': 'user_action',
        'event_timestamp': '2026-01-25T12:00:00Z',
        'user_id': 'user123',
        'action': 'click'
    }


@pytest.fixture
def valid_kinesis_record(valid_kinesis_data):
    """Create a valid Kinesis record with all required fields."""
    encoded = base64.b64encode(json.dumps(valid_kinesis_data).encode('utf-8')).decode('utf-8')
    return {
        'kinesis': {
            'sequenceNumber': '49670192848271239842602659163669398716174920392225325058',
            'data': encoded
        },
        'eventSource': 'aws:kinesis',
        'eventID': 'shardId-000000000000:49670192848271239842602659163669398716174920392225325058'
    }


@pytest.fixture
def kinesis_event(valid_kinesis_record):
    """Create a complete Kinesis event with one record."""
    return {'Records': [valid_kinesis_record]}


@pytest.fixture
def kinesis_record_missing_event_type():
    """Kinesis record missing required event_type field."""
    data = {
        'event_timestamp': '2026-01-25T12:00:00Z',
        'user_id': 'user123'
    }
    encoded = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')
    return {
        'kinesis': {
            'sequenceNumber': '49670192848271239842602659163669398716174920392225325059',
            'data': encoded
        }
    }


@pytest.fixture
def kinesis_record_missing_timestamp():
    """Kinesis record missing required timestamp field."""
    data = {
        'event_type': 'user_action',
        'user_id': 'user123'
    }
    encoded = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')
    return {
        'kinesis': {
            'sequenceNumber': '49670192848271239842602659163669398716174920392225325060',
            'data': encoded
        }
    }


@pytest.fixture
def kinesis_record_with_legacy_timestamp():
    """Kinesis record using 'timestamp' instead of 'event_timestamp'."""
    data = {
        'event_type': 'legacy_event',
        'timestamp': '2026-01-25T12:00:00Z',
        'user_id': 'user456'
    }
    encoded = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')
    return {
        'kinesis': {
            'sequenceNumber': '49670192848271239842602659163669398716174920392225325061',
            'data': encoded
        }
    }
