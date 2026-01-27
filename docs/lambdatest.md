# Lambda Unit Tests Documentation

## Overview

Unit tests for the ETL and Merge Lambda functions using `pytest` and `moto` for AWS mocking.

**Results:** 33 tests, 96% code coverage

## Test Structure

```
lambdas/
├── conftest.py           # Shared fixtures (AWS credentials, env vars, sys.path setup)
├── pytest.ini            # Pytest configuration
├── requirements-dev.txt  # Test dependencies
├── etl/
│   ├── etl_handler.py    # ETL Lambda (renamed from app.py)
│   ├── conftest.py       # ETL-specific fixtures (Kinesis events)
│   └── test_etl.py       # 17 tests
└── merge/
    ├── merge_handler.py  # Merge Lambda (renamed from app.py)
    ├── conftest.py       # Merge-specific fixtures (Step Functions events)
    └── test_merge.py     # 16 tests
```

## Key Design Decisions

### 1. Renamed Lambda Files

**Problem:** Both `etl/` and `merge/` directories had files named `app.py`. When pytest runs from the `lambdas/` directory, Python imports the first `app` module it finds and caches it. This caused tests to import the wrong handler.

**Solution:** Renamed to unique names:
- `etl/app.py` → `etl/etl_handler.py`
- `merge/app.py` → `merge/merge_handler.py`

**Impact:** Updated Terraform handler references in:
- `modules/ingestion_stream/main.tf` → `handler = "etl_handler.lambda_handler"`
- `modules/orchestration/main.tf` → `handler = "merge_handler.lambda_handler"`

### 2. Lazy Configuration Loading

**Problem:** Original Lambda code read environment variables at import time:

```python
# Original - runs when file is imported
DATA_LAKE_BUCKET = os.environ.get('DATA_LAKE_BUCKET')
```

Tests set env vars *after* importing the module, so variables were always `None`.

**Solution:** Added `get_config()` function that reads env vars at runtime:

```python
# Fixed - runs when function is called
def get_config():
    return {
        'bucket': os.environ.get('DATA_LAKE_BUCKET'),
        'raw_prefix': os.environ.get('RAW_PREFIX', 'raw/')
    }
```

Functions now call `get_config()` when they need configuration values.

### 3. Python Path Setup

**Problem:** Pytest runs from `lambdas/` but handler files live in subdirectories. Python couldn't find `etl_handler` or `merge_handler` modules.

**Solution:** Added path setup in `lambdas/conftest.py`:

```python
lambdas_dir = Path(__file__).parent
sys.path.insert(0, str(lambdas_dir / 'etl'))
sys.path.insert(0, str(lambdas_dir / 'merge'))
```

### 4. AWS Credentials Before Import

**Problem:** Lambda handlers create boto3 clients at module level:

```python
s3_client = boto3.client('s3')
dynamodb_client = boto3.client('dynamodb')
```

Boto3 requires a region to create a client, even for mocked tests. Import failed with `NoRegionError`.

**Solution:** Set AWS environment variables before importing handlers:

```python
# In conftest.py, before sys.path setup
os.environ['AWS_DEFAULT_REGION'] = 'us-west-2'
os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
```

## Errors Encountered

### Error 1: Import File Mismatch

```
ImportError: test_app.py found in multiple locations
```

**Cause:** Both test files were originally named `test_app.py`.

**Fix:** Renamed to `test_etl.py` and `test_merge.py`.

### Error 2: Module Not Found

```
ModuleNotFoundError: No module named 'etl_handler'
```

**Cause:** Python path didn't include the Lambda subdirectories.

**Fix:** Added `sys.path.insert()` calls in root `conftest.py`.

### Error 3: No Region Error

```
botocore.exceptions.NoRegionError: You must specify a region.
```

**Cause:** Boto3 clients created at module level need a region, even for mocked tests.

**Fix:** Set `AWS_DEFAULT_REGION` environment variable before imports in `conftest.py`.

### Error 4: Environment Variables Not Set

```
ValueError: DATA_LAKE_BUCKET environment variable is not set
```

**Cause:** Lambda code read env vars at import time, before test fixtures could set them.

**Fix:** Changed to lazy loading pattern with `get_config()` function.

### Error 5: Scientific Notation False Positive

```
AssertionError: assert 'e-' not in content
# Failed because timestamp contained '+00:00'
```

**Cause:** Test checked for `'e-'` substring to detect scientific notation, but ISO timestamps contain similar patterns.

**Fix:** Changed to regex pattern: `r'\d+\.?\d*[eE][+-]?\d+'`

## Test Coverage

| File | Coverage |
|------|----------|
| etl_handler.py | 95% |
| merge_handler.py | 91% |
| **Total** | **96%** |

Uncovered lines are primarily error handling paths (missing env vars, S3 errors).

## Running Tests

```powershell
# Install dependencies
cd lambdas
pip install -r requirements-dev.txt

# Run all tests
pytest -v

# Run with coverage report
pytest --cov=etl --cov=merge --cov-report=term-missing

# Run specific Lambda tests
pytest etl/test_etl.py -v
pytest merge/test_merge.py -v
```

## Test Categories

### ETL Lambda Tests (17 tests)

| Class | Tests |
|-------|-------|
| TestLambdaHandler | Single record, multiple records, invalid record handling |
| TestProcessRecord | S3 key generation, idempotency via sequence number |
| TestValidateJson | Required fields, type validation, legacy timestamp support |
| TestNormalizeData | Metadata addition, timestamp conversion, immutability |
| TestWriteToS3 | Date partitioning, JSON validity, error handling |

### Merge Lambda Tests (16 tests)

| Class | Tests |
|-------|-------|
| TestDecimalEncoder | Scientific notation prevention, nested objects, standard types |
| TestValidateEnvironment | Required env var validation |
| TestGetTextPreview | Text extraction, truncation, error handling |
| TestMergeAiResults | Record creation, empty enrichment handling |
| TestWriteToS3Processed | Date partitioning, no scientific notation |
| TestWriteToDynamodb | Record creation, TTL inclusion |
| TestUpdateCuratedSummary | Summary creation and updates |
| TestLambdaHandler | Full end-to-end integration |

## Moto Usage Pattern

Tests use the `@mock_aws` decorator from moto to mock AWS services:

```python
from moto import mock_aws

@mock_aws
def test_example(self, set_env_vars):
    # Create mock resources
    client = boto3.client('s3', region_name='us-west-2')
    client.create_bucket(
        Bucket='test-bucket',
        CreateBucketConfiguration={'LocationConstraint': 'us-west-2'}
    )

    # Test Lambda function
    result = etl_handler.lambda_handler(event, None)
    assert result['successful'] == 1
```

Resources must be created inside each test because moto resets between tests.
