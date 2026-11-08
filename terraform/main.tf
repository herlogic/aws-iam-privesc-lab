# ---------------------------------------------------------------------
# 1. The low-privileged "attacker" user
# ---------------------------------------------------------------------
resource "aws_iam_user" "attacker" {
  name          = "privesc-lab-lowpriv"
  force_destroy = true
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

# The deliberately dangerous permissions. On their own these look harmless:
# "can pass a role" and "can run a Lambda." Together they are the problem.
resource "aws_iam_user_policy" "attacker" {
  name = "lowpriv-dangerous-permissions"
  user = aws_iam_user.attacker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PassRoleAndRunLambda"
      Effect = "Allow"
      Action = [
        "iam:PassRole",
        "iam:ListRoles",
        "lambda:CreateFunction",
        "lambda:InvokeFunction",
        "lambda:GetFunction"
      ]
      Resource = "*"
    }]
  })
}

# ---------------------------------------------------------------------
# 2. The privileged role Lambda can assume (the misconfiguration)
# ---------------------------------------------------------------------
resource "aws_iam_role" "privileged" {
  name = "privesc-lab-admin-role"

  # Trust policy: the Lambda service is allowed to assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# This role is full administrator — massively over-privileged.
resource "aws_iam_role_policy_attachment" "privileged_admin" {
  role       = aws_iam_role.privileged.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}