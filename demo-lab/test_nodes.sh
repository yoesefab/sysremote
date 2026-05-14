#!/bin/bash
echo "Testing all nodes..."
echo ""

for port in 2222 2223 2224; do
  echo "=== localhost:$port ==="
  ssh -i ssh/sysremote_demo -p $port -o StrictHostKeyChecking=no -o ConnectTimeout=3 demo@localhost "hostname && whoami" 2>/dev/null
  if [ $? -eq 0 ]; then
    echo "✅ Node on port $port is reachable"
  else
    echo "❌ Node on port $port is NOT reachable"
  fi
  echo ""
done
