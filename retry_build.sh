#!/bin/bash
# macos-26 runner 池暂不可用时的自动重试：
# 每 15s dispatch 一次；job steps==0 且 failure = 没拿到 runner → 重试；
# 拿到 runner 后轮询直到构建结束。
TOKEN="$GITHUB_TOKEN"
REPO="zhuof723-sudo/legado-ios"
MAX=240
RUN_ID=""
for i in $(seq 1 $MAX); do
  curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    -d '{"ref":"main"}' \
    "https://api.github.com/repos/$REPO/actions/workflows/build-ipa.yml/dispatches" >/dev/null
  sleep 15
  RUN_ID=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/runs?event=workflow_dispatch&per_page=1" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin).get("workflow_runs",[{}])[0]; print(r.get("id",""))')
  [ -z "$RUN_ID" ] && { echo "attempt $i: no run id"; continue; }
  STATE=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status"), d.get("conclusion"))')
  set -- $STATE
  STATUS=$1; CONCLUSION=$2
  echo "attempt $i: run=$RUN_ID status=$STATUS conclusion=$CONCLUSION"
  if [ "$STATUS" != "completed" ]; then
    echo "runner assigned, build in progress ($STATUS) — waiting"
    # 拿到 runner 了：轮询到结束
    for w in $(seq 1 40); do
      sleep 20
      STATE=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID" \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status"), d.get("conclusion"))')
      set -- $STATE
      if [ "$1" = "completed" ]; then echo "build finished: $2"; break; fi
    done
    break
  fi
  if [ "$CONCLUSION" = "success" ]; then
    echo "build succeeded"
    break
  fi
  # completed + failure：区分"没 runner" 与真实编译失败
  JOB=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/jobs" \
    | python3 -c 'import json,sys; js=json.load(sys.stdin).get("jobs",[{}]); j=js[0] if js else {}; print(j.get("conclusion",""), len(j.get("steps",[])))')
  set -- $JOB
  STEPS=$2
  if [ "$STEPS" != "0" ]; then
    echo "build failed with real errors (steps=$STEPS)"
    break
  fi
  echo "attempt $i: no runner assigned, retrying..."
done
echo "RESULT run=$RUN_ID"