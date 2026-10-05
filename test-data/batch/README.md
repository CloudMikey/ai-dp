# Sample batch files

Synthetic reviews written for testing the batch path. They are not real customer reviews; real company, place, and person names are used only so Comprehend's entity detection has something to find.

Each file is plain text, one review, under 5,000 bytes. Upload them all at once to exercise concurrent executions:

```bash
aws s3 cp test-data/batch/ "s3://$(terraform -chdir=envs/dev output -raw data_lake_bucket_name)/raw/batch-test/" \n  --recursive --exclude README.md --region us-west-2
```
