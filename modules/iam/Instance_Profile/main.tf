data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count              = local.create
  name               = var.role_name
  path               = var.path
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each  = local.create == 1 ? toset(var.managed_policy_arns) : toset([])
  role      = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = local.create
  name  = var.instance_profile_name
  path  = var.path
  role  = aws_iam_role.this[0].name
  tags  = local.tags
}
