# Running Cloudant Backup Locally with Docker

This guide shows you how to build and run the Cloudant backup container locally using Docker.

## Prerequisites

- Docker Desktop installed and running
- `.env` file with your credentials (see below)

## Step 1: Create .env File

Create a `.env` file in the `code-engine-cloudant-backup` directory with your actual credentials:

```bash
# Cloudant Configuration
CLOUDANT_URL=https://username:password@your-cloudant-instance.cloudantnosqldb.appdomain.cloud
DATABASES=github_actions_jobs,github_app_repos_allowlist,github_app_users

# AWS S3 Configuration
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
S3_BUCKET=gha-cloudant-db-backup
S3_ENDPOINT=https://s3.us-south.cloud-object-storage.appdomain.cloud
UPLOAD_TO_S3=true
```

## Step 2: Build the Docker Image

```bash
cd code-engine-cloudant-backup
docker build -t cloudant-backup:local .
```

This will:
- Install Node.js 18
- Install AWS CLI
- Install @cloudant/couchbackup
- Copy the backup script
- Set up proper permissions

## Step 3: Run the Container

```bash
docker run --rm \
  --env-file .env \
  -v $(pwd)/backup:/app/backup \
  cloudant-backup:local
```

### What This Does:
- `--rm`: Automatically remove container when it exits
- `--env-file .env`: Load environment variables from .env file
- `-v $(pwd)/backup:/app/backup`: Mount local backup directory to see output files
- `cloudant-backup:local`: The image we just built

## Step 4: Check the Results

After the container runs, check:

1. **Local backup files**: `backup/stage/` directory
2. **S3 bucket**: Check your S3 bucket for uploaded files
3. **Console output**: See the backup progress and any errors

## Troubleshooting

### Permission Denied
If you get permission errors, ensure Docker has access to the backup directory:
```bash
mkdir -p backup/stage
chmod -R 755 backup
```

### Connection Errors
- Verify your Cloudant URL is correct
- Check that your credentials are valid
- Ensure you can reach the Cloudant instance from your network

### S3 Upload Fails
- Verify AWS credentials are correct
- Check S3 endpoint URL matches your region
- Ensure the bucket exists and you have write permissions

## Quick Test Run

To quickly test without S3 upload:

1. Edit `.env` and set `UPLOAD_TO_S3=false`
2. Run the container
3. Check `backup/stage/` for backup files

## Viewing Logs

All output is shown in your terminal. To save logs:

```bash
docker run --rm \
  --env-file .env \
  -v $(pwd)/backup:/app/backup \
  cloudant-backup:local 2>&1 | tee backup.log
```

## Cleaning Up

Remove the Docker image when done:
```bash
docker rmi cloudant-backup:local
```

Remove backup files:
```bash
rm -rf backup/