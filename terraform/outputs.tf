output "attacker_access_key_id" {
  value = aws_iam_access_key.attacker.id
}

output "attacker_secret_access_key" {
  value     = aws_iam_access_key.attacker.secret
  sensitive = true
}

output "privileged_role_arn" {
  value = aws_iam_role.privileged.arn
}