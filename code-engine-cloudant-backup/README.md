# Cloudant Backup for IBM Code Engine

This directory contains a complete setup for running Cloudant database backups as an IBM Code Engine job. The solution is containerized and can run on-demand or on a schedule.

## 📋 Contents

- `manage_cloudant.sh` - Modified backup/restore script (works without .env file)
- `Dockerfile` - Container image definition
- `job-definition.yaml` - Code Engine job configuration with secrets and configmaps
- `env-vars-example.yaml` - Example environment variable configuration
- `secrets-example.yaml` - Example secrets configuration (template only)

## 🚀 Quick Start

### Prerequisites

1. **IBM Cloud CLI** with Code Engine plugin
   ```bash
   ibmcloud plugin install code-engine
   ```

2. **Docker** or **Podman** for building container images

3. **IBM Container Registry** or another container registry

4. **IBM Code Engine project** created
   ```bash
   ibmcloud ce project create --name cloudant-backup-project
   ibmcloud ce project select --name cloudant-backup-project
   ```

## 📦 Step 1: Build and Push Container Image

### Option A: Using IBM Container Registry

```bash
# Login to IBM Cloud
ibmcloud login

# Set your region and resource group
ibmcloud target -r us-south -g default

# Login to IBM Container Registry
ibmcloud cr login

# Create a namespace (if you don't have one)
ibmcloud cr namespace-add cloudant-backup

# Build and push the image
cd code-engine-cloudant-backup
docker build -t us.icr.io/cloudant-backup/cloudant-backup:latest .
docker push us.icr.io/cloudant-backup/cloudant-backup:latest
```

### Option B: Using Docker Hub

```bash
cd code-engine-cloudant-backup
docker build -t your-dockerhub-username/cloudant-backup:latest .
docker push your-dockerhub-username/cloudant-backup:latest
```

## 🔐 Step 2: Create Secrets

### Create Cloudant Credentials Secret

```bash
# Replace with your actual Cloudant URL
ibmcloud ce secret create \
  --name cloudant-credentials \
  --from-literal couch-url="https://username:password@account.cloudant.com"
```

### Create AWS Credentials Secret (Optional - only if using S3 upload)

```bash
ibmcloud ce secret create \
  --name aws-credentials \
  --from-literal access-key-id="YOUR_AWS_ACCESS_KEY_ID" \
  --from-literal secret-access-key="YOUR_AWS_SECRET_ACCESS_KEY"
```

## ⚙️ Step 3: Create ConfigMap

```bash
ibmcloud ce configmap create \
  --name cloudant-backup-config \
  --from-literal ENV="prod" \
  --from-literal DATABASES="github_actions_jobs github_app_repos_allowlist github_app_users" \
  --from-literal LOCAL_BACKUP_ROOT="backup" \
  --from-literal UPLOAD_TO_S3="true" \
  --from-literal S3_BUCKET="gha-cloudant-db-backup" \
  --from-literal S3_ENDPOINT_URL="http://s3.us-east.cloud-object-storage.appdomain.cloud"
```

## 🎯 Step 4: Create Code Engine Job

### Option A: Using CLI

```bash
ibmcloud ce job create \
  --name cloudant-backup-job \
  --image us.icr.io/cloudant-backup/cloudant-backup:latest \
  --cpu 0.5 \
  --memory 1G \
  --ephemeral-storage 2G \
  --max-execution-time 3600 \
  --retry-limit 2 \
  --env-from-configmap cloudant-backup-config \
  --env-from-secret cloudant-credentials \
  --env-from-secret aws-credentials
```

### Option B: Using YAML

```bash
# Update the image reference in job-definition.yaml first
# Then apply the configuration
kubectl apply -f job-definition.yaml
```

## ▶️ Step 5: Run the Job

### Run Manually

```bash
# Run the job immediately
ibmcloud ce jobrun submit --job cloudant-backup-job

# Check job run status
ibmcloud ce jobrun list

# View logs
ibmcloud ce jobrun logs --jobrun cloudant-backup-job-xxxxx-0
```

### Schedule the Job (Cron)

```bash
# Run daily at 2 AM UTC
ibmcloud ce subscription cron create \
  --name cloudant-backup-schedule \
  --destination cloudant-backup-job \
  --schedule "0 2 * * *" \
  --data '{"command": "backup"}'

# Run every 6 hours
ibmcloud ce subscription cron create \
  --name cloudant-backup-schedule \
  --destination cloudant-backup-job \
  --schedule "0 */6 * * *"
```

## 📊 Monitoring and Logs

### View Job Runs

```bash
# List all job runs
ibmcloud ce jobrun list

# Get details of a specific job run
ibmcloud ce jobrun get --name cloudant-backup-job-xxxxx-0
```

### View Logs

```bash
# View logs for the latest job run
ibmcloud ce jobrun logs --job cloudant-backup-job

# View logs for a specific job run
ibmcloud ce jobrun logs --jobrun cloudant-backup-job-xxxxx-0

# Follow logs in real-time
ibmcloud ce jobrun logs --follow --job cloudant-backup-job
```

### Check Job Events

```bash
# View job events
ibmcloud ce jobrun events --jobrun cloudant-backup-job-xxxxx-0
```

## 🔄 Updating the Job

### Update Configuration

```bash
# Update ConfigMap
ibmcloud ce configmap update \
  --name cloudant-backup-config \
  --from-literal DATABASES="new_db1 new_db2"

# Update Secret
ibmcloud ce secret update \
  --name cloudant-credentials \
  --from-literal couch-url="https://newuser:newpass@account.cloudant.com"
```

### Update Container Image

```bash
# Build and push new image
docker build -t us.icr.io/cloudant-backup/cloudant-backup:v2 .
docker push us.icr.io/cloudant-backup/cloudant-backup:v2

# Update job to use new image
ibmcloud ce job update \
  --name cloudant-backup-job \
  --image us.icr.io/cloudant-backup/cloudant-backup:v2
```

## 🛠️ Configuration Options

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `COUCH_URL` | Yes | - | Cloudant URL with credentials |
| `DATABASES` | No | See script | Space-separated list of databases |
| `ENV` | No | `prod` | Environment name |
| `LOCAL_BACKUP_ROOT` | No | `backup` | Local backup directory |
| `UPLOAD_TO_S3` | No | `false` | Enable S3 upload |
| `S3_BUCKET` | No | - | S3 bucket name |
| `S3_ENDPOINT_URL` | No | - | S3 endpoint URL |
| `AWS_ACCESS_KEY_ID` | Conditional | - | Required if UPLOAD_TO_S3=true |
| `AWS_SECRET_ACCESS_KEY` | Conditional | - | Required if UPLOAD_TO_S3=true |

### Resource Limits

Adjust based on your database size and backup requirements:

```bash
ibmcloud ce job update \
  --name cloudant-backup-job \
  --cpu 1 \
  --memory 2G \
  --ephemeral-storage 4G
```

## 🧪 Testing Locally

You can test the container locally before deploying to Code Engine:

```bash
# Build the image
docker build -t cloudant-backup:test .

# Run with environment variables
docker run --rm \
  -e COUCH_URL="https://user:pass@account.cloudant.com" \
  -e DATABASES="test_db" \
  -e ENV="dev" \
  -e UPLOAD_TO_S3="false" \
  cloudant-backup:test
```

## 🔒 Security Best Practices

1. **Never commit secrets** to version control
2. **Use Code Engine Secrets** for sensitive data (COUCH_URL, AWS credentials)
3. **Use ConfigMaps** for non-sensitive configuration
4. **Rotate credentials** regularly
5. **Use least-privilege** IAM policies for S3 access
6. **Enable audit logging** in Code Engine
7. **Review job logs** regularly for security events

## 📝 Troubleshooting

### Job Fails to Start

```bash
# Check job configuration
ibmcloud ce job get --name cloudant-backup-job

# Check if secrets exist
ibmcloud ce secret get --name cloudant-credentials

# Check if configmap exists
ibmcloud ce configmap get --name cloudant-backup-config
```

### Backup Fails

```bash
# View detailed logs
ibmcloud ce jobrun logs --jobrun cloudant-backup-job-xxxxx-0

# Common issues:
# - Invalid COUCH_URL
# - Network connectivity issues
# - Insufficient permissions
# - Disk space issues
```

### S3 Upload Fails

```bash
# Verify AWS credentials
ibmcloud ce secret get --name aws-credentials

# Test S3 connectivity from a debug pod
ibmcloud ce job create --name debug-job --image alpine --command sh --argument "-c" --argument "apk add aws-cli && aws s3 ls"
```

## 🔄 Restore Process

To restore from a backup, you'll need to:

1. Download the backup files from S3 (if uploaded)
2. Run a restore job with the backup directory mounted
3. Or run the restore command interactively

```bash
# Create a one-time restore job
ibmcloud ce job create \
  --name cloudant-restore-job \
  --image us.icr.io/cloudant-backup/cloudant-backup:latest \
  --command "/app/manage_cloudant.sh" \
  --argument "restore" \
  --env-from-configmap cloudant-backup-config \
  --env-from-secret cloudant-credentials
```

## 📚 Additional Resources

- [IBM Code Engine Documentation](https://cloud.ibm.com/docs/codeengine)
- [Cloudant Documentation](https://cloud.ibm.com/docs/Cloudant)
- [@cloudant/couchbackup](https://github.com/cloudant/couchbackup)
- [IBM Cloud Object Storage](https://cloud.ibm.com/docs/cloud-object-storage)

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Code Engine job logs
3. Consult IBM Cloud documentation
4. Contact your cloud administrator

## 📄 License

This script is provided as-is for use with IBM Cloud services.