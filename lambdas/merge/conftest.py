"""Merge Lambda test fixtures."""

import pytest


@pytest.fixture
def valid_step_functions_event():
    """Create a valid Step Functions input event."""
    return {
        'source_object': {
            'bucket': 'test-data-lake-bucket',
            'key': 'raw/year=2026/month=01/day=25/12345.json'
        },
        'ai_enrichment': {
            'sentiment': {
                'Sentiment': 'POSITIVE',
                'SentimentScore': {
                    'Positive': 0.95,
                    'Negative': 0.01,
                    'Neutral': 0.03,
                    'Mixed': 0.01
                }
            },
            'entities': {
                'Entities': [
                    {
                        'Text': 'Amazon',
                        'Type': 'ORGANIZATION',
                        'Score': 0.99,
                        'BeginOffset': 0,
                        'EndOffset': 6
                    },
                    {
                        'Text': 'Seattle',
                        'Type': 'LOCATION',
                        'Score': 0.95,
                        'BeginOffset': 10,
                        'EndOffset': 17
                    }
                ]
            }
        },
        'processing_metadata': {
            'timestamp': '2026-01-25T12:00:00Z',
            'source': 'kinesis-stream'
        }
    }


@pytest.fixture
def raw_s3_object_content():
    """Content of raw S3 object for text preview extraction."""
    return {
        'event_type': 'user_feedback',
        'event_timestamp': '2026-01-25T12:00:00Z',
        'text': 'Amazon Web Services is a great cloud platform based in Seattle.',
        'user_id': 'user123'
    }


@pytest.fixture
def event_with_empty_enrichment():
    """Step Functions event with no AI enrichment results."""
    return {
        'source_object': {
            'bucket': 'test-data-lake-bucket',
            'key': 'raw/year=2026/month=01/day=25/12345.json'
        },
        'ai_enrichment': {
            'sentiment': {},
            'entities': {'Entities': []}
        },
        'processing_metadata': {
            'timestamp': '2026-01-25T12:00:00Z'
        }
    }


@pytest.fixture
def event_with_scientific_notation_scores():
    """Event with very small float values that trigger scientific notation."""
    return {
        'source_object': {
            'bucket': 'test-data-lake-bucket',
            'key': 'raw/year=2026/month=01/day=25/12345.json'
        },
        'ai_enrichment': {
            'sentiment': {
                'Sentiment': 'NEUTRAL',
                'SentimentScore': {
                    'Positive': 0.000001,
                    'Negative': 0.0000001,
                    'Neutral': 0.999998,
                    'Mixed': 0.0000009
                }
            },
            'entities': {
                'Entities': [
                    {
                        'Text': 'Test',
                        'Type': 'OTHER',
                        'Score': 0.00000123,
                        'BeginOffset': 0,
                        'EndOffset': 4
                    }
                ]
            }
        },
        'processing_metadata': {
            'timestamp': '2026-01-25T12:00:00Z'
        }
    }
