# Automated n8n Update and Testing System - Spec

## Overview

This spec defines an automated system for safely updating n8n in enterprise environments with comprehensive testing and automatic rollback capabilities.

## Problem Statement

- Security vulnerabilities in n8n require quick patching
- No automated way to verify n8n works after updates
- Manual daily health checks are not sustainable
- No defined rollback process when updates break functionality

## Solution

Three GitHub Actions pipelines that work together:

1. **Update Pipeline** (Daily 2 AM) - Detects new versions, tests in isolation, applies to production, auto-rolls back on failure
2. **Code Change Pipeline** (On Push/PR) - Validates workflow changes before merge
3. **Daily Health Check Pipeline** (Daily 8 AM) - Proactive monitoring without updates

## Key Features

- **65 Automated Tests** across 13 categories (Infrastructure, Network, Web, Auth, Database, API, Workflows, Credentials, Performance, Backup, Security, Notifications, Environment)
- **Automatic Rollback** triggered by:
  - Any critical test failure
  - >30% of tests failing
  - >50% response time increase
  - >100% memory usage increase
- **Complete Backup/Restore** (Docker image + PostgreSQL database + data volume)
- **Email Notifications** for all events
- **Multi-Instance Support** for managing multiple n8n deployments

## Architecture

```
GitHub Actions Workflows
    ↓
Test Runner (Bash)
    ↓
Test Scripts (65 tests)
    ↓
n8n Container + PostgreSQL
```

## Documents

- **requirements.md** - Complete requirements with EARS patterns and acceptance criteria
- **design.md** - System architecture, components, data models, correctness properties
- **tasks.md** - Implementation plan with 16 major tasks and 100+ sub-tasks

## Test Categories

1. **Infrastructure (INF)** - 6 tests - Container health, uptime, volumes, resources
2. **Network (NET)** - 4 tests - HTTP, webhooks, external connectivity, proxy
3. **Web (WEB)** - 5 tests - Editor, assets, healthcheck, version, WebSocket
4. **Authentication (AUTH)** - 5 tests - API keys, login, RBAC, SSO
5. **Database (DB)** - 6 tests - Connection, schema, data integrity, encryption, performance
6. **API (API)** - 6 tests - Workflows, CRUD, activation, executions, credentials
7. **Workflows (WF)** - 8 tests - Webhooks, transforms, HTTP, errors, cron, sub-workflows
8. **Credentials (CRED)** - 4 tests - Decryption, count, env vars, sharing
9. **Performance (PERF)** - 5 tests - Response times, execution times, memory, load, payloads
10. **Backup (BKP)** - 4 tests - Completeness, restorability, rollback capability, retention
11. **Security (SEC)** - 6 tests - TLS, headers, CVE scan, packages, container security
12. **Notifications (NOTIF)** - 3 tests - Email delivery, channels, error workflows
13. **Environment (ENV)** - 3 tests - Multi-instance consistency, parity, source control

## Test Workflows

8 n8n workflows deployed inside n8n for testing:

1. **Health Check** - Basic webhook response test
2. **Data Transform** - Expression engine and Code node test
3. **HTTP Request** - Outbound API call test
4. **Error Handling** - Error path and recovery test
5. **Cron Test** - Scheduled trigger test
6. **Parent/Child Workflows** - Sub-workflow execution test
7. **Credential Test** - Encryption key verification test

## Implementation Phases

### Phase 1: Mini Demo/MVP (1-2 weeks)

**Goal**: Get a working Update Pipeline with basic tests to prove the concept

**What you'll have:**
- ✅ Update Pipeline (manual trigger)
- ✅ Health Check Pipeline (manual trigger)
- ✅ 10 essential tests (INF, NET, WEB, DB, API, WF, CRED, PERF, BKP)
- ✅ 2 test workflows (health check, credential test)
- ✅ Backup and rollback scripts
- ✅ Email notifications
- ✅ Basic test runner

**What you can do:**
- Manually trigger an update
- See tests execute and pass/fail
- Automatic rollback on failure
- Get email notifications
- Verify the system works end-to-end

**Time**: 1-2 weeks, ~10 tasks

### Phase 2: Full Implementation (3-4 weeks)

**Goal**: Complete all 65 tests and add advanced features

**What you'll add:**
- ✅ All 65 tests across 13 categories
- ✅ All 8 test workflows
- ✅ Code Change Pipeline (on push/PR)
- ✅ Scheduled execution (daily 2 AM, 8 AM)
- ✅ Automatic version detection
- ✅ Enhanced backup (volume backup)
- ✅ Audit logging
- ✅ Multi-instance support
- ✅ Complete documentation

**Time**: 3-4 weeks, ~22 additional tasks

## Success Metrics

- **Test Coverage**: >90% of critical functionality
- **Test Execution Time**: <5 min for health checks, <15 min for full suite
- **False Positive Rate**: <5%
- **Automated Rollback**: Triggers within 2 minutes of failed tests
- **Update Frequency**: Daily checks, immediate security patch application
- **Downtime**: <5 minutes during updates

## Prerequisites

- n8n running in Docker (Docker Compose or standalone)
- PostgreSQL database
- GitHub repository with self-hosted runner
- SMTP server for notifications
- n8n API key with read/write access

## Configuration

All settings in `tests/config.yaml`:
- n8n connection details
- PostgreSQL credentials
- Rollback thresholds
- Backup retention
- Notification recipients
- Feature flags
- Test workflow definitions

## GitHub Secrets Required

- `N8N_TEST_API_KEY` - n8n API key
- `N8N_DB_PASSWORD` - PostgreSQL password
- `SMTP_HOST`, `SMTP_USER`, `SMTP_PASSWORD` - Email settings
- `NOTIFICATION_RECIPIENTS` - Email addresses

## Manual Commands

Via `workflow_dispatch` on Update Pipeline:

- **Check for update only** - Detect but don't apply
- **Apply specific version** - Force update to version X.Y.Z
- **Run tests only** - Test current deployment
- **Rollback to last backup** - Restore previous version
- **Rollback to specific point** - Restore specific backup
- **Deploy test workflows** - Import/update test workflows

## Rollback Process

1. Detect failure (critical test, >30% failures, performance degradation)
2. Stop updated container
3. Restore Docker image from backup tag
4. Restore PostgreSQL database from dump
5. Restore data volume from tarball
6. Start container with previous version
7. Verify health with subset of tests
8. Send notification

Total time: <2 minutes

## Notifications

Email notifications sent for:
- Update detected
- Update starting
- Update succeeded
- Rollback triggered (ALERT)
- Rollback completed
- Rollback failed (CRITICAL)
- Daily health check passed
- Daily health check failed (ALERT)

## Future Enhancements

- Blue-green deployment support
- Kubernetes migration
- Prometheus/Grafana integration
- Business workflow testing
- Third-party connector monitoring
- Slack/Teams/PagerDuty integration

## Getting Started

1. Read `requirements.md` for detailed specifications
2. Review `design.md` for architecture and implementation details
3. Follow `tasks.md` for step-by-step implementation
4. Start with Phase 1 tasks (Core Framework)

## Questions?

- Check requirements.md for "what" and "why"
- Check design.md for "how"
- Check tasks.md for "when" and "in what order"
