#!/bin/bash

# Seed workflows directly into n8n database using SQL
# This bypasses API key requirements and works for fresh instances

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🌱 Seeding Workflows into n8n Database${NC}"
echo "================================"
echo ""

WORKFLOW_DIR="../workflows"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-n8n-postgres-test}"
N8N_CONTAINER="${N8N_CONTAINER:-n8n-test}"

# Check if containers are running
if ! docker ps --format '{{.Names}}' | grep -q "^${POSTGRES_CONTAINER}$"; then
  echo -e "${RED}❌ PostgreSQL container ${POSTGRES_CONTAINER} is not running${NC}"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${N8N_CONTAINER}$"; then
  echo -e "${RED}❌ n8n container ${N8N_CONTAINER} is not running${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Containers are running${NC}"
echo ""

if [ ! -d "$WORKFLOW_DIR" ]; then
  echo -e "${RED}❌ Workflow directory not found: $WORKFLOW_DIR${NC}"
  exit 1
fi

# Get database credentials from n8n container environment
DB_NAME=$(docker exec "${N8N_CONTAINER}" printenv DB_POSTGRESDB_DATABASE 2>/dev/null || echo "n8n")
DB_USER=$(docker exec "${N8N_CONTAINER}" printenv DB_POSTGRESDB_USER 2>/dev/null || echo "n8n")

echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo ""

IMPORTED=0
FAILED=0

for workflow_file in "$WORKFLOW_DIR"/test-*.json; do
  if [ ! -f "$workflow_file" ]; then
    continue
  fi
  
  WORKFLOW_NAME=$(basename "$workflow_file" .json)
  echo -e "${YELLOW}Seeding: ${WORKFLOW_NAME}${NC}"
  
  # Read workflow JSON and escape for SQL
  WORKFLOW_JSON=$(cat "$workflow_file" | jq -c '.')
  WORKFLOW_NAME_CLEAN=$(echo "$WORKFLOW_JSON" | jq -r '.name')
  
  # Generate SQL to insert workflow
  SQL="INSERT INTO workflow_entity (name, active, nodes, connections, settings, staticData, tags, versionId, createdAt, updatedAt) 
       VALUES ('${WORKFLOW_NAME_CLEAN}', true, '${WORKFLOW_JSON}'::jsonb->'nodes', '${WORKFLOW_JSON}'::jsonb->'connections', 
               COALESCE('${WORKFLOW_JSON}'::jsonb->'settings', '{}'::jsonb), 
               COALESCE('${WORKFLOW_JSON}'::jsonb->'staticData', '{}'::jsonb), 
               '[]'::jsonb, '1', NOW(), NOW())
       ON CONFLICT (name) DO UPDATE SET 
         active = true,
         nodes = EXCLUDED.nodes,
         connections = EXCLUDED.connections,
         updatedAt = NOW();"
  
  # Execute SQL in PostgreSQL container
  if docker exec "${POSTGRES_CONTAINER}" psql -U "${DB_USER}" -d "${DB_NAME}" -c "$SQL" > /dev/null 2>&1; then
    echo -e "${GREEN}   ✅ Seeded successfully${NC}"
    ((IMPORTED++))
  else
    echo -e "${RED}   ❌ Seeding failed${NC}"
    ((FAILED++))
  fi
  echo ""
done

# Restart n8n to pick up new workflows
echo -e "${YELLOW}Restarting n8n to load workflows...${NC}"
docker restart "${N8N_CONTAINER}" > /dev/null
sleep 5

echo "================================"
echo -e "${BLUE}Seeding Summary${NC}"
echo "  Seeded:  ${IMPORTED}"
echo "  Failed:  ${FAILED}"
echo ""

if [ $IMPORTED -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully seeded ${IMPORTED} workflow(s)${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  No workflows seeded${NC}"
  exit 1
fi
