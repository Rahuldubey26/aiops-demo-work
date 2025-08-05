# Production-Grade AIOps Agent on AWS

This project provides a complete, end-to-end AIOps agent built on AWS using a serverless architecture. It monitors AWS resources, detects anomalies using Machine Learning, performs root-cause analysis, and triggers self-healing actions.

## Architecture Overview

The system follows an event-driven, serverless architecture:

1.  **Monitor**: An EventBridge rule triggers the `anomaly-detector` Lambda every 5 minutes.
2.  **Detect**: This Lambda fetches `CPUUtilization` metrics from tagged EC2 instances, uses a pre-trained Isolation Forest model to detect anomalies, and publishes findings to an SNS topic (`aiops-anomalies`).
3.  **Analyze (RCA)**: The `log-analyzer-rca` Lambda is triggered by the SNS topic. It queries CloudWatch Logs for error messages around the anomaly's timestamp. This enriches the alert and reduces noise.
4.  **Store & Escalate**: The analysis results are stored in DynamoDB for the frontend. If critical log entries are found, a new alert is published to a second SNS topic (`aiops-critical-alerts`).
5.  **Alert**: The critical SNS topic sends an email notification.
6.  **Remediate**: The `remediation-engine` Lambda is triggered by the critical SNS topic and performs a self-healing action (e.g., rebooting the EC2 instance).
7.  **Visualize**: A React frontend queries an API Gateway endpoint to display all detected events from the DynamoDB table in near real-time.

![Architecture Diagram](https://your-image-url/architecture.png) <!-- It's highly recommended to create and link a diagram -->

## Prerequisites

-   AWS Account and AWS CLI configured with credentials.
-   [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) installed.
-   [Python 3.9+](https://www.python.org/downloads/) and `pip` installed.
-   [Node.js and npm](https://nodejs.org/en/download/) installed (for frontend).
-   A GitHub account for the CI/CD pipeline.
-   An EC2 Key Pair to be used for the target instance.

## How to Deploy

### 1. Initial Setup

1.  **Clone the repository:**
    ```bash
    git clone <your-repo-url>
    cd aiops-agent-on-aws
    ```

2.  **Set up CI/CD (Recommended):**
    -   In your AWS account, create an IAM Role for GitHub Actions (OIDC).
    -   Add `AWS_ACCOUNT_ID`, `IAM_ROLE_NAME`, and `ALERT_EMAIL` as secrets to your GitHub repository.
    -   Pushing to the `main` branch will trigger the `cicd_pipeline.yml` workflow to deploy everything.

### 2. Manual Deployment Steps

1.  **Deploy Infrastructure with Terraform:**
    -   Navigate to the `infrastructure` directory.
    -   Create a `terraform.tfvars` file:
        ```hcl
        alert_email = "your-email@example.com"
        ```
    -   Initialize and apply Terraform:
        ```bash
        cd infrastructure
        terraform init
        terraform apply
        ```
    -   Note the outputs, especially `target_ec2_instance_id` and `api_endpoint`.

2.  **Train and Package the Model:**
    -   You need the `instance_id` from the Terraform output.
    -   Install dependencies: `pip install -r scripts/requirements.txt`
    -   Run the training script:
        ```bash
        python scripts/train_model.py --instance-id <your_ec2_instance_id_from_output>
        ```
    -   This will create `src/anomaly_detector/model.joblib`.

3.  **Package and Deploy Lambdas (if not using CI/CD):**
    -   For each function in `src/`, install dependencies locally: `pip install -r requirements.txt -t .`
    -   Zip the contents and upload manually or update the Terraform `aws_lambda_function` resources to point to local zip files. *This is complex, the CI/CD pipeline is highly recommended.*

4.  **Configure and Run Frontend:**
    -   Update `frontend/src/App.js` with the `api_endpoint` from the Terraform output.
    -   Navigate to the `frontend` directory and run:
        ```bash
        npm install
        npm start
        ```

## How to Test the Agent

1.  **Install Stress Utility on EC2:**
    -   SSH into the target EC2 instance. You will need its public IP and your `.pem` key.
        ```bash
        ssh -i /path/to/your-key.pem ec2-user@<instance_public_ip>
        ```
    -   Install the `stress` tool:
        ```bash
        sudo amazon-linux-extras install epel -y
        sudo yum install stress -y
        ```

2.  **Trigger a CPU Anomaly:**
    -   From your local machine, run the test script:
        ```bash
        pip install -r scripts/requirements.txt
        python scripts/test_trigger.py --instance-id <your_ec2_id> --region <your_aws_region> --key-file /path/to/your-key.pem
        ```
    -   This will spike the CPU for 10 minutes. Within the next 5-10 minutes, you should see an event appear on the dashboard and receive an email alert if logs were found. The instance will then be rebooted.

## ML Model Explanation

The anomaly detection model uses `sklearn.ensemble.IsolationForest`. This is an unsupervised learning algorithm that is effective for anomaly detection.

-   **How it Works**: It "isolates" observations by randomly selecting a feature and then randomly selecting a split value between the maximum and minimum values of that feature. The number of splits required to isolate a sample is equivalent to the path length from the root node to the terminating node in a tree. Anomalies are "few and different," which means they are easier to isolate and thus have shorter average path lengths across a forest of random trees.
-   **Why it was Chosen**: It does not require a labeled dataset, is computationally efficient, and does not assume the data is normally distributed, which is often true for system metrics.
-   **Training**: The `scripts/train_model.py` script fetches 14 days of historical CPU data to build a baseline of "normal" behavior. The `contamination` parameter is set to 'auto', allowing the algorithm to determine the threshold for what constitutes an anomaly.