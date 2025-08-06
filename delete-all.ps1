# cleanup.ps1 - A script to clean up resources from the AIOps project.
# WARNING: This script deletes resources and is not easily reversible. Use with caution.
# Version 2: Corrected for PowerShell syntax compatibility.

# --- Configuration ---
$ProjectName = "aiops-agent" # IMPORTANT: Make sure this matches your var.project_name
$Region = "us-east-1"        # IMPORTANT: Make sure this matches your AWS region

# --- Function to delete a resource and wait ---
function Remove-Resource ($ResourceType, $ResourceId, $DeleteCommand) {
    try {
        if ($ResourceId) {
            # Corrected Write-Host with curly braces
            Write-Host "Attempting to delete ${ResourceType}: ${ResourceId}..."
            Invoke-Expression $DeleteCommand
            Write-Host "${ResourceType}: ${ResourceId} deleted or termination initiated."
        }
    } catch {
        # Corrected Write-Warning with curly braces
        Write-Warning "Could not delete ${ResourceType}: ${ResourceId}. It might already be gone. Error: $_"
    }
}

Write-Host "--- Starting AIOps Project Cleanup for project '$ProjectName' in region '$Region' ---" -ForegroundColor Yellow

# 1. Terminate EC2 Instance
Write-Host "Finding EC2 instance..."
$instanceId = (aws ec2 describe-instances --region $Region --filters "Name=tag:Name,Values=$($ProjectName)-target-instance" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text)
Remove-Resource "EC2 Instance" $instanceId "aws ec2 terminate-instances --region $Region --instance-ids $instanceId | Out-Null"
if ($instanceId) {
    Write-Host "Waiting for EC2 instance to terminate..."
    aws ec2 wait instance-terminated --region $Region --instance-ids $instanceId
}

# 2. Delete App Runner Service
Write-Host "Finding App Runner service..."
$appRunnerArn = (aws apprunner list-services --region $Region --query "ServiceSummaryList[?ServiceName=='$($ProjectName)-dashboard'].ServiceArn" --output text)
Remove-Resource "App Runner Service" $appRunnerArn "aws apprunner delete-service --region $Region --service-identifier $appRunnerArn | Out-Null"

# 3. Delete Lambda Functions
Write-Host "Finding Lambda functions..."
$lambdaFunctions = aws lambda list-functions --region $Region --query "Functions[?starts_with(FunctionName, '$($ProjectName)-')].FunctionName" --output text
foreach ($func in $lambdaFunctions) {
    Remove-Resource "Lambda Function" $func "aws lambda delete-function --region $Region --function-name $func"
}

# 4. Delete Lambda Layer
Write-Host "Finding Lambda layer..."
$layerArn = (aws lambda list-layer-versions --layer-name "$($ProjectName)-scikit-learn-layer" --query "LayerVersions[0].LayerVersionArn" --output text 2>$null)
if ($layerArn) {
    $versionNumber = $layerArn.Split(':')[-1]
    Remove-Resource "Lambda Layer" "$($ProjectName)-scikit-learn-layer" "aws lambda delete-layer-version --region $Region --layer-name $($ProjectName)-scikit-learn-layer --version-number $versionNumber"
}

# 5. Delete ECR Repository (must be empty first)
Write-Host "Finding ECR repository..."
$repoUri = (aws ecr describe-repositories --repository-names "$($ProjectName)/frontend" --query "repositories[0].repositoryUri" --output text 2>$null)
if ($repoUri) {
    Write-Host "Emptying ECR repository: $($ProjectName)/frontend..."
    $images = aws ecr list-images --repository-name "$($ProjectName)/frontend" --query 'imageIds[*]' --output json
    if ($images -ne "[]" -and $images) {
        aws ecr batch-delete-image --repository-name "$($ProjectName)/frontend" --image-ids $images | Out-Null
    }
    Remove-Resource "ECR Repository" "$($ProjectName)/frontend" "aws ecr delete-repository --region $Region --repository-name $($ProjectName)/frontend --force"
}

# 6. Delete IAM Roles and Policies
Write-Host "Finding IAM roles and policies..."
$roles = aws iam list-roles --query "Roles[?starts_with(RoleName, '$($ProjectName)-')].RoleName" --output text
foreach ($role in $roles) {
    $attachedPolicies = aws iam list-attached-role-policies --role-name $role --query "AttachedPolicies[].PolicyArn" --output text
    foreach ($policyArn in $attachedPolicies) {
        Write-Host "Detaching policy $policyArn from role $role..."
        aws iam detach-role-policy --role-name $role --policy-arn $policyArn
    }
    Remove-Resource "IAM Role" $role "aws iam delete-role --role-name $role"
}
$policies = aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName, '$($ProjectName)-')].Arn" --output text
foreach ($policyArn in $policies) {
    Remove-Resource "IAM Policy" $policyArn "aws iam delete-policy --policy-arn $policyArn"
}

# 7. Delete DynamoDB Table
Write-Host "Finding DynamoDB table..."
Remove-Resource "DynamoDB Table" "$($ProjectName)-anomalies" "aws dynamodb delete-table --region $Region --table-name $($ProjectName)-anomalies | Out-Null"

# 8. Delete EventBridge Rule
Write-Host "Finding EventBridge rule..."
$ruleName = "$($ProjectName)-every-5-minutes"
# Check if the rule has targets before trying to remove them
$targets = aws events list-targets-by-rule --rule $ruleName --query "Targets[].Id" --output json 2>$null
if ($targets -ne "[]" -and $targets) {
    aws events remove-targets --rule $ruleName --ids $targets --force | Out-Null
}
Remove-Resource "EventBridge Rule" $ruleName "aws events delete-rule --name $ruleName"

# 9. Delete SNS Topics
Write-Host "Finding SNS topics..."
$snsTopics = aws sns list-topics --region $Region --query "Topics[?ends_with(TopicArn, ':$($ProjectName)-anomalies') || ends_with(TopicArn, ':$($ProjectName)-critical-alerts')].TopicArn" --output text
foreach ($topic in $snsTopics) {
    Remove-Resource "SNS Topic" $topic "aws sns delete-topic --region $Region --topic-arn $topic"
}

# 10. Delete the VPC (Manual Step Recommended)
Write-Host "Finding VPC..."
$vpcId = (aws ec2 describe-vpcs --region $Region --filters "Name=tag:Name,Values=$($ProjectName)-vpc" --query "Vpcs[].VpcId" --output text)
if ($vpcId) {
    Write-Host "IMPORTANT: The VPC ($vpcId) and its associated resources (Subnets, IGW, etc.) need to be deleted from the AWS Console." -ForegroundColor Magenta
    Write-Host "Go to the VPC service, select the VPC named '$($ProjectName)-vpc', click Actions -> Delete VPC, and confirm." -ForegroundColor Magenta
    Write-Host "Automating VPC deletion is complex; manual deletion is safer." -ForegroundColor Magenta
}

Write-Host "--- Cleanup script finished ---" -ForegroundColor Green