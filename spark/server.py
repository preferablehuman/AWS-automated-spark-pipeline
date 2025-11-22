# server.py
import os, json, asyncio, subprocess, shlex, time
from typing import Dict, Any
from fastapi import FastAPI, Request, HTTPException

app = FastAPI(title="S3A Spark Webhook")

WEBHOOK_TOKEN = os.getenv("WEBHOOK_TOKEN", "change-me")

# Spark params (env-first; fallbacks keep your local behavior)
SPARK_BIN   = os.getenv("SPARK_BIN", "/opt/spark/bin/spark-submit")
SPARK_JOB   = os.getenv("SPARK_JOB", "/app/NYUTaxiSparkJob.py")
SPARK_MAST  = os.getenv("SPARK_MASTER", "local[*]")
SPARK_DRV_M = os.getenv("SPARK_DRIVER_MEMORY", "6g")
SPARK_ARGS  = os.getenv("SPARK_EXTRA_ARGS", "")  # e.g.: '--conf spark.sql.shuffle.partitions=16'

# In-memory FIFO and a single worker task => strictly sequential processing
queue: "asyncio.Queue[Dict[str, Any]]" = asyncio.Queue()
worker_task: asyncio.Task | None = None

def _normalize_s3_event(evt: Dict[str, Any]) -> Dict[str, str]:
    """
    Accepts EventBridge S3 Object Created events and normalizes to {bucket, key}.
    Handles common shapes (detail.bucket.name, detail.object.key).
    """
    d = evt.get("detail") or {}
    # EventBridge "Object Created"
    b = (d.get("bucket") or {}).get("name")
    k = (d.get("object") or {}).get("key")
    # Some routes include 'requestParameters' or different casing; add fallbacks if needed
    if not b or not k:
        # Try top-level S3 Put event if routed differently
        recs = evt.get("Records")
        if recs and len(recs) > 0:
            b = recs[0]["s3"]["bucket"]["name"]
            k = recs[0]["s3"]["object"]["key"]
    if not b or not k:
        raise ValueError("missing bucket/key in event")
    return {"bucket": b, "key": k}

async def _worker():
    while True:
        item = await queue.get()
        bucket, key = item["bucket"], item["key"]
        s3a_path = f"s3a://{bucket}/{key}"

        # Build spark-submit command
        cmd = [
            SPARK_BIN,
            "--master", SPARK_MAST,
            "--driver-memory", SPARK_DRV_M,
        ]
        if SPARK_ARGS.strip():
            # split shell-like args safely
            cmd.extend(shlex.split(SPARK_ARGS))
        # hand file path to your job (add argparse in your job to read --input)
        cmd.extend([SPARK_JOB, "--input", s3a_path])

        print(f"[worker] submitting job for {s3a_path}")
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT
        )
        # Stream logs to container stdout
        assert proc.stdout is not None
        async for line in proc.stdout:
            print(line.decode("utf-8"), end="")
        rc = await proc.wait()
        print(f"[worker] job for {s3a_path} exited rc={rc}")
        queue.task_done()

@app.on_event("startup")
async def _on_startup():
    global worker_task
    print("[startup] worker started")
    worker_task = asyncio.create_task(_worker())
    # print("[startup] worker started")


@app.post("/eventbridge")
async def eventbridge(request: Request):
    # simple auth
    token = request.headers.get("x-webhook-token")
    if token != WEBHOOK_TOKEN:
        raise HTTPException(status_code=401, detail="unauthorized")

    try:
        evt = await request.json()
        norm = _normalize_s3_event(evt)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"bad event: {e}")

    # Enqueue and return immediately; worker processes sequentially
    await queue.put(norm)
    size = queue.qsize()
    return {"status": "accepted", "queued": size, "bucket": norm["bucket"], "key": norm["key"]}

@app.get("/healthz")
async def healthz():
    return {"ok": True, "queue": queue.qsize()}
