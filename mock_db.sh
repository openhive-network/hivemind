#!/bin/bash

set -euo pipefail

URL=postgresql://postgres:devdevdev@localhost:5432

MOCK_DB_NAME=haf_block_log_5m
BACKUP_DB_NAME=haf_block_log_5m_backup

MOCK_DB_URL=$URL/$MOCK_DB_NAME
BACKUP_DB_URL=$URL/$BACKUP_DB_NAME


# PREPARE FRESH DB
psql $BACKUP_DB_URL -c "DROP DATABASE IF EXISTS $MOCK_DB_NAME;"
psql $BACKUP_DB_URL -c "CREATE DATABASE $MOCK_DB_NAME WITH TEMPLATE $BACKUP_DB_NAME"
psql $MOCK_DB_URL -c "CREATE EXTENSION IF NOT EXISTS intarray;"


# WRAPPER FUNCTION
psql $MOCK_DB_URL -f scripts/ci/wrapper_for_app_next_block.sql


# PUSH MOCKED DATA
export DATABASE_URL=postgresql://hivemind_app:devdevdev@192.168.6.253:5432/haf_block_log_5m
export MOCK_BLOCK_DATA_PATH=mock_data/block_data/
export MOCK_VOPS_DATA_PATH=mock_data/vops_data/

mocker
