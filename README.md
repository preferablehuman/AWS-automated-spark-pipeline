
---

# NYU Taxi Big Data Processing Pipeline

### Apache Spark Structured Streaming on AWS with Terraform Infrastructure as Code

## Introduction

This repository presents a fully automated, event-driven big data processing pipeline constructed for large-scale NYC/NYU Taxi datasets. The system is designed to ingest multi-gigabyte CSV files uploaded to Amazon S3, deliver them reliably into Amazon Elastic File System (EFS), process them continuously using Apache Spark Structured Streaming deployed on Amazon ECS, and persist the transformed outputs into an Amazon RDS PostgreSQL database. All infrastructure components—networking, compute, storage, security, and execution roles—are provisioned and managed entirely through Terraform, ensuring reproducibility, consistency, and operational transparency.

The design philosophy behind this system merges long-standing principles of reliable data engineering—atomic file delivery, deterministic schema interpretation, durable checkpointing, and append-only persistence—with modern cloud-native architectural practices such as containerized compute, serverless event routing, and declarative infrastructure provisioning. The pipeline operates in a continuous manner, requiring no manual triggers or oversight once deployed.

The sections that follow describe the architecture, operational flow, infrastructure behavior, and deployment steps in detail.

---

## System Architecture

The architecture is composed of five primary subsystems, each performing a specific role in the overall data flow. Together, they form a coherent pipeline capable of processing large datasets safely and continuously.

### Storage and Event Source: Amazon S3

An Amazon S3 bucket functions as the ingestion point for raw taxi CSV files. Each file upload generates an `ObjectCreated` event, which acts as the authoritative signal that new data has arrived. The system does not rely on polling or periodic scans; instead, it reacts immediately to S3 events.

### File Delivery Layer: AWS Lambda and Amazon EFS

An AWS Lambda function responds to each S3 event. It streams the uploaded CSV file from S3 into a mounted EFS file system. To guarantee consistency, the Lambda function writes data into a temporary `.part` file before performing an atomic rename to its final `.csv` form. This ensures that downstream components, particularly Spark Structured Streaming, never encounter partially written files.

### Compute & Processing Layer: Apache Spark Structured Streaming on ECS

A continuously running Spark Structured Streaming job is deployed as a containerized service on Amazon ECS. The ECS task mounts the same EFS file system, allowing Spark to detect each finalized CSV as it appears. Spark processes each file as a micro-batch, enforces a predefined schema, derives additional features (such as trip duration and day-of-week indicators), and prepares the dataset for persistence. Checkpoints stored on EFS ensure exactly-once processing semantics across task restarts.

### Persistence Layer: Amazon RDS for PostgreSQL

Processed data is appended into the `NYU_TAXI` table within an Amazon RDS PostgreSQL instance. JDBC connection parameters are provided through ECS task environment variables, enabling the same container image to operate across varied environments without modification.

### Provisioning Layer: Terraform

The entire infrastructure is defined declaratively through Terraform, including VPC networking, subnets, routing, security groups, IAM roles, S3 buckets, Lambda functions, EFS resources, ECS clusters and services, and RDS databases. This ensures that the pipeline can be reproduced exactly, deployed consistently, and destroyed cleanly as required.

---

## Integrated Architecture Diagram

The following conceptual diagram illustrates the full movement of data through the pipeline and the relationships among its components:

```
          ┌──────────────────────────────┐
          │          Amazon S3           │
          │ Incoming Taxi CSV Dataset    │
          └───────────────┬──────────────┘
                          │  ObjectCreated Event
                          ▼
               ┌───────────────────────────┐
               │        AWS Lambda         │
               │  Data-Ingestion Function  │
               │ Streams Object → EFS      │
               └──────────────┬────────────┘
                              │ Atomic Rename (.part → .csv)
                              ▼
                  ┌────────────────────────┐
                  │        Amazon EFS      │
                  │  /incoming, /checkpoints │
                  └──────────────┬───────────┘
                                 │ Mounted by ECS
                                 ▼
                      ┌────────────────────────┐
                      │        Amazon ECS       │
                      │   Spark Structured      │
                      │   Streaming Service     │
                      │ Processes Micro-Batches │
                      └─────────────┬──────────┘
                                    │ JDBC Append
                                    ▼
                         ┌────────────────────────┐
                         │  Amazon RDS Postgres   │
                         │  NYU_TAXI Table        │
                         └────────────────────────┘
                                        |
                                        │ 
                                        ▼
                Connection to BI tool and for other analysis
```

---

## Execution Flow

### File Arrival in S3

A CSV dataset is uploaded to the designated S3 bucket. AWS immediately generates an event notification containing the file’s key and metadata. No polling or scheduled processes are involved; the pipeline is driven purely by event signals.

### Controlled Delivery Through Lambda

The Lambda ingestion function retrieves the object from S3 and streams it into EFS. A temporary `.part` file is used during writing, ensuring Spark never sees incomplete files. Once the download completes successfully, the file is atomically renamed to its final `.csv` extension.

### Streaming Ingestion by Spark

The Spark Structured Streaming job monitors the EFS `/incoming` directory for new files. Each detected file forms a micro-batch. Spark enforces a fixed schema for stable interpretation and derives additional features such as trip duration and temporal attributes. Checkpoints stored on EFS preserve Spark’s streaming state and allow exact recovery after task restarts.

### Persistence to RDS

Each micro-batch is appended to the RDS PostgreSQL database through a JDBC connection. The use of `foreachBatch` ensures explicit failure visibility and transactional micro-batch boundaries. Batch identifiers are included to support traceability.

### Fault Tolerance and Continuity

Because Spark’s checkpointing and Lambda’s atomic file delivery guarantee safe ingestion boundaries, the system remains consistent and resilient across restarts, interruptions, or partial failures.

---

## Deployment and Execution Steps

The following steps outline the complete lifecycle for deploying and operating this system.

### Prerequisites

Ensure the following tools are installed and configured:

* Terraform (v1.5 or later)
* AWS CLI configured with valid credentials
* Docker (required only for local testing or image rebuilds)
* An AWS account with sufficient permissions

You may configure credentials using the AWS CLI:

```bash
aws configure
```

---

### Step 1: Configure Terraform Variables

Navigate to the Terraform directory:

```bash
cd terraform
```

Open `terraform.tfvars` and verify the following values:

* AWS region
* project name prefix
* database username and password
* allowed IP for RDS connection

Example:

```hcl
aws_region       = "us-east-1"
project_name     = "nyu-taxi"
db_username      = "postgres"
db_password      = "your_password"
db_name          = "nyutaxi"
allowed_ip_cidr  = "YOUR_PUBLIC_IP/32"
ecs_spark_image = "ECS repo url to the docker image latest tag"
```

---

### Step 2: Initialize Terraform

```bash
terraform init
```

---

### Step 3: Generate and Review the Plan

```bash
terraform plan -out tfplan
```

Ensure that the resources to be created align with expectations, including VPC components, S3 bucket, Lambda function, EFS configuration, ECS service, and RDS instance.

---

### Step 4: Apply Terraform and Deploy the Stack

```bash
terraform apply tfplan
```

Retrieve deployment outputs:

```bash
terraform output
```

Record the S3 bucket name and the RDS endpoint for later use.

---

### Step 5: Verify ECS Deployment

Within the AWS Console or via CLI, confirm that the ECS cluster contains a running task and that the task has successfully mounted EFS.

---

### Step 6: Upload a Dataset File to S3

Upload a taxi CSV into the incoming bucket:

```bash
aws s3 cp <yourfile>.csv s3://<incoming_bucket_name>/incoming/
```

---

### Step 7: Confirm Lambda Ingestion

Navigate to CloudWatch → Lambda Logs.
Confirm that the function has:

* detected the S3 event
* downloaded the file
* written a `.part` file
* performed an atomic rename to `.csv`

---

### Step 8: Confirm Spark Micro-Batch Processing

Check CloudWatch logs for the ECS Spark task.
Expected log entries include:

* detection of new input files
* micro-batch execution
* database write completion

---

### Step 9: Validate Database Output

Connect to the RDS instance:

```bash
psql "postgresql://<db_username>:<db_password>@<rds_endpoint>:5432/<db_name>"
```

Run queries such as:

```sql
SELECT COUNT(*) FROM NYU_TAXI;
SELECT * FROM NYU_TAXI LIMIT 10;
```

A growing row count indicates successful ingestion.

---

### Step 10: Destroy Infrastructure (Optional)

When the environment is no longer needed:

```bash
terraform destroy
```

This command removes all resources created by the Terraform stack.

---

## Extensibility and Future Enhancements

The architecture supports several natural extensions, including:

* migration of ECS and RDS into private subnets
* addition of Parquet or analytical lakehouse outputs
* integration of real-time streaming services (Kinesis or MSK)
* ECS autoscaling policies
* enhanced BI layer connectivity

These enhancements can be adopted as requirements evolve.

---

## Repository Structure Overview

* **spark/**: Contains Spark Structured Streaming jobs, JDBC drivers, configuration files, and Dockerfile.
* **terraform/**: Contains all Infrastructure-as-Code modules defining AWS components.
* **docker-compose.yml**: Supports local testing of the Spark container.

---

## Conclusion

This project stands as a complete, reproducible, and formally engineered big-data ingestion pipeline. Its design combines classical data engineering principles with modern cloud-native execution models, resulting in a system that operates continuously, reliably, and transparently. With structured event ingestion, deterministic processing semantics, robust checkpointing, and declarative infrastructure provisioning, the pipeline is well suited both for real-world data workloads and for academic or professional demonstration.

---