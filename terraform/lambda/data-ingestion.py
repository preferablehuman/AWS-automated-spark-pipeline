# import json

# def lambda_handler(event, context):
#     # TODO implement
#     return {
#         'statusCode': 200,
#         'body': json.dumps('Hello from Lambda!')
#     }


import os
import boto3
import pathlib

s3 = boto3.client("s3")

EFS_MOUNT = os.environ.get("EFS_MOUNT", "/mnt/efs")
EFS_PREFIX = os.environ.get("EFS_PREFIX", "incoming")  # relative inside EFS

def lambda_handler(event, context):
    try:
        
        print(f"event: {event}")
        records = event.get("Records", [])
        if not records:
            print("No records in event")
            return

        for rec in records:
            bucket = rec["s3"]["bucket"]["name"]
            key    = rec["s3"]["object"]["key"]

            # Only handle the prefix you care about (defensive)
            if not key.lower().endswith(".csv"):
                print(f"Skipping non-CSV object: {key}")
                continue

            # EFS target path – mirror S3 key under /incoming
            rel_path = key  # or strip leading "incoming/" if you want
            final_path = pathlib.Path(EFS_MOUNT) / EFS_PREFIX / rel_path
            tmp_path   = final_path.with_suffix(final_path.suffix + ".part")

            print(f"Copying s3://{bucket}/{key} -> {final_path}")

            # Ensure directories exist
            tmp_path.parent.mkdir(parents=True, exist_ok=True)

            # Stream S3 object into EFS file
            with open(tmp_path, "wb") as f:
                s3.download_fileobj(bucket, key, f)

            # Atomic rename so Spark only sees complete files
            os.rename(tmp_path, final_path)

            print(f"Finished writing {final_path}")
    except Exception as e:
        print(f"ERROR caught : {e}")
        print(f"event: {event}")
