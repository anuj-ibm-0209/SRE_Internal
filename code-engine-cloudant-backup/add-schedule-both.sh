#!/bin/bash

# Script to add cron schedules to both stage and prod backup jobs
# Stage runs 15 minutes before prod to avoid conflicts

set -e

echo "================================================"
echo "Adding Cron Schedules for Cloudant Backups"
echo "================================================"
echo ""

# Stage: Every Friday at 5:45 PM IST (12:15 PM UTC)
echo "1️⃣  Creating cron subscription for STAGE environment..."
echo "   Job: cloudant-backup"
echo "   Schedule: Every Friday at 5:45 PM IST (12:15 PM UTC)"
echo ""

ibmcloud ce subscription cron create \
  --name cloudant-backup-cron-stage \
  --destination cloudant-backup \
  --schedule "15 12 * * 5" \
  --time-zone "UTC" \
  --destination-type job \
  --force

echo "   ✅ Stage cron subscription created!"
echo ""

# Wait a moment
sleep 2

# Prod: Every Friday at 6:00 PM IST (12:30 PM UTC)
echo "2️⃣  Creating cron subscription for PROD environment..."
echo "   Job: cloudant-backup-prod"
echo "   Schedule: Every Friday at 6:00 PM IST (12:30 PM UTC)"
echo ""

ibmcloud ce subscription cron create \
  --name cloudant-backup-cron-prod \
  --destination cloudant-backup-prod \
  --schedule "30 12 * * 5" \
  --time-zone "UTC" \
  --destination-type job \
  --force

echo "   ✅ Prod cron subscription created!"
echo ""

echo "================================================"
echo "✅ Both cron subscriptions configured successfully!"
echo "================================================"
echo ""
echo "📅 Schedule Summary:"
echo "   Stage: Fridays at 5:45 PM IST (12:15 PM UTC)"
echo "   Prod:  Fridays at 6:00 PM IST (12:30 PM UTC)"
echo "   Gap:   15 minutes between stage and prod"
echo ""
echo "🔍 To verify subscriptions:"
echo "   ibmcloud ce subscription cron list"
echo "   ibmcloud ce subscription cron get --name cloudant-backup-cron-stage"
echo "   ibmcloud ce subscription cron get --name cloudant-backup-cron-prod"
echo ""
echo "📊 To view job runs:"
echo "   ibmcloud ce jobrun list --job cloudant-backup"
echo "   ibmcloud ce jobrun list --job cloudant-backup-prod"
echo ""
echo "🗑️  To remove subscriptions later:"
echo "   ibmcloud ce subscription cron delete --name cloudant-backup-cron-stage"
echo "   ibmcloud ce subscription cron delete --name cloudant-backup-cron-prod"
echo ""

# Made with Bob
