############################################
# 1) Generate private/public key (in memory)
############################################
resource "tls_private_key" "this" {
  count     = var.enabled ? 1 : 0
  algorithm = var.algorithm
  rsa_bits  = var.algorithm == "RSA" ? var.rsa_bits : null
}

############################################
# 2) Register EC2 Key Pair
############################################
resource "aws_key_pair" "this" {
  count      = var.enabled ? 1 : 0
  key_name   = local.key_name
  public_key = tls_private_key.this[0].public_key_openssh
  tags       = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

############################################
# 3) Secrets Manager secret == key name
############################################
resource "aws_secretsmanager_secret" "pk" {
  count                   = var.enabled ? 1 : 0
  name                    = "${local.key_name}-demo2"
  recovery_window_in_days = 30
  tags                    = local.common_tags
}

############################################
# 4) Store PEM in the secret
############################################
resource "aws_secretsmanager_secret_version" "pkv" {
  count         = var.enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.pk[0].id
  secret_string = tls_private_key.this[0].private_key_pem
}
