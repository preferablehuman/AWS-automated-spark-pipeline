"""
NYU Taxi Spark Structured Streaming Job
- Reads CSV files from a directory (config['input.csv.path'])
- Transforms data (trip length, day of week)
- Writes micro-batches to PostgreSQL using foreachBatch in APPEND mode
- Designed to be deployed as an always-on service (ECS/EC2/K8s, etc.)
"""

import json
import pyspark
from pyspark.sql import SparkSession
from pyspark.sql.types import *
from pyspark.sql.functions import *
from pyspark.sql.utils import AnalysisException
import os


# ---------- Load config ----------
CONFIG_PATH = "/app/config.json"

try:
    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
except Exception as e:
    raise RuntimeError(f"Failed to load config from {CONFIG_PATH}: {e}")


# ---------- DB config ----------
# postgresql_url = config.get("db.url")
postgresql_url = os.environ.get("DB_URL")
table_name = "NYU_TAXI"
db_properties = {
    "user": config.get("db.user"),
    "password": config.get("db.password"),
    "driver": config.get("db.driver"),
}


# ---------- Spark session ----------
def getSparkSession():
    spark = (
        SparkSession.builder.master("local")
        .appName("NYUTaxiData")
        .config("spark.executor.memory", config.get("spark.executor.memory"))
        .config("spark.driver.memory", config.get("spark.driver.memory"))
        .config("spark.executor.cores", config.get("spark.executor.cores"))
        .config("spark.sql.shuffle.partitions", config.get("spark.sql.shuffle.partitions"))
        .config("spark.jars", config.get("spark.jars"))
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("INFO")
    print("=== SparkSession created ===")
    print(f"Config: {config}")
    print(f"DB URL: {postgresql_url}, table: {table_name}")
    return spark


# ---------- Schema ----------
def getSchema():
    NYUschema = StructType(
        [
            StructField("VendorID", IntegerType(), True),
            StructField("tpep_pickup_datetime", TimestampType(), True),
            StructField("tpep_dropoff_datetime", TimestampType(), True),
            StructField("passenger_count", IntegerType(), True),
            StructField("trip_distance", FloatType(), True),
            StructField("pickup_longitude", StringType(), True),
            StructField("pickup_latitude", StringType(), True),
            StructField("RateCodeID", IntegerType(), True),
            StructField("store_and_fwd_flag", BooleanType(), True),
            StructField("dropoff_longitude", StringType(), True),
            StructField("dropoff_latitude", StringType(), True),
            StructField("payment_type", IntegerType(), True),
            StructField("fare_amount", FloatType(), True),
            StructField("extra", FloatType(), True),
            StructField("mta_tax", FloatType(), True),
            StructField("tip_amount", FloatType(), True),
            StructField("tolls_amount", FloatType(), True),
            StructField("improvement_surcharge", FloatType(), True),
            StructField("total_amount", FloatType(), True),
        ]
    )
    return NYUschema


# ---------- foreachBatch sink ----------
def write_to_postgres(batch_df, batch_id: int):
    """
    Called for each micro-batch by Structured Streaming.
    We ALWAYS use .mode("append") so:
    - Table existing is fine (no ErrorIfExists)
    - Stream is safe to redeploy/restart automatically
    """
    if batch_df.rdd.isEmpty():
        # No data in this batch; nothing to write
        print(f"[BATCH {batch_id}] Empty batch, skipping write.")
        return

    print(f"[BATCH {batch_id}] Starting write of {batch_df.count()} rows to PostgreSQL...")

    try:
        (
            batch_df.withColumn("Id", lit(batch_id))
            .write
            .mode("append")  # <<< IMPORTANT: APPEND, not default ErrorIfExists
            .jdbc(url=postgresql_url, table=table_name, properties=db_properties)
        )

        print(f"[BATCH {batch_id}] Successfully written to table {table_name}.")

    except AnalysisException as ae:
        # This should NOT happen with .mode('append') for "table exists",
        # but if something weird does happen, log it clearly.
        print(f"[BATCH {batch_id}] AnalysisException during JDBC write: {ae}")
        # In a real prod setup, you might send this to CloudWatch/Datadog and then:
        raise

    except Exception as e:
        # Generic DB failure (network, credentials, timeout, etc.)
        print(f"[BATCH {batch_id}] ERROR writing to PostgreSQL: {e}")
        # Re-raise so the stream fails fast and your orchestration can restart it
        raise


# ---------- Main job ----------
def sparkJob(spark: SparkSession, NYUschema: StructType):
    input_path = config.get("input.csv.path")       # "/mnt/efs/incoming"
    checkpoint_dir = config.get("checkpoint.dir")   # "/mnt/efs/checkpoints"

    # --- Ensure directories exist on the mounted EFS ---
    os.makedirs(input_path, exist_ok=True)
    os.makedirs(checkpoint_dir, exist_ok=True)

    trigger_time = config.get("trigger.processing.time")
    output_mode = config.get("output.mode", "append")

    print("=== Starting Structured Streaming job ===")
    print(f"Input path: {input_path}")
    print(f"Checkpoint dir: {checkpoint_dir}")
    print(f"Trigger: {trigger_time}, output mode: {output_mode}")

    NYU_data = (
        spark.readStream
        .option("header", "True")
        .option("maxFilesPerTrigger", 1)
        .schema(NYUschema)
        .csv(input_path)
    )

    NYU_data = NYU_data.withColumn(
        "trip_Length",
        (unix_timestamp(col("tpep_dropoff_datetime")) - unix_timestamp(col("tpep_pickup_datetime"))) / 60,
    )
    NYU_data = NYU_data.withColumn("day_of_week", date_format(col("tpep_pickup_datetime"), "E"))

    query = (
        NYU_data.writeStream
        .foreachBatch(write_to_postgres)
        .trigger(processingTime=trigger_time)
        .option("checkpointLocation", checkpoint_dir)
        .outputMode(output_mode)  # should be "append" for this pattern
        .start()
    )

    print("=== Stream started, awaiting termination ===")
    query.awaitTermination()


if __name__ == "__main__":
    spark = getSparkSession()
    schema = getSchema()
    sparkJob(spark, schema)
