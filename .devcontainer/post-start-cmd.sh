

echo "[post-start-cmd.sh] Starting modelrelay in the background..."
if command -v modelrelay &>/dev/null; then
  setsid /usr/local/bin/modelrelay >> /tmp/modelrelay.log 2>&1 &
else
  echo "[post-start-cmd.sh] modelrelay not found, skipping start"
fi