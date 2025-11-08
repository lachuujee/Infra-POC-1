# names and tags
locals {
  base_name      = replace(var.name, "_cdn", "")
  waf_name       = "${local.base_name}-cdn-waf"
  metric_prefix  = replace(local.waf_name, "_", "-")
  log_group_name = "aws-waf-logs-${local.waf_name}"
}

# log group
resource "aws_cloudwatch_log_group" "this" {
  count             = var.enabled ? 1 : 0
  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

# webacl for cloudfront
resource "aws_wafv2_web_acl" "this" {
  count       = var.enabled ? 1 : 0
  name        = local.waf_name
  description = "CLOUDFRONT WebACL default block"
  scope       = "CLOUDFRONT"

  default_action {
    block {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.metric_prefix}-acl"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWS-AWSManagedRulesAdminProtectionRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAdminProtectionRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-admin"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"

        # allow selected sub-rules, block DDoS list
        rule_action_override {
          name = "AWSManagedIPReputationList"
          action_to_use {
            allow {}
          }
        }
        rule_action_override {
          name = "AWSManagedReconnaissanceList"
          action_to_use {
            allow {}
          }
        }
        rule_action_override {
          name = "AWSManagedIPDDoSList"
          action_to_use {
            block {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-ip-rep"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 50

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesLinuxRuleSet"
    priority = 60

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-linux"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesUnixRuleSet"
    priority = 70

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesUnixRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-unix"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesWindowsRuleSet"
    priority = 80

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesWindowsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-windows"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 90

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric_prefix}-crs"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(var.common_tags, { Name = local.waf_name })
}

# logging config
resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count        = var.enabled ? 1 : 0
  resource_arn = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [
    aws_cloudwatch_log_group.this[0].arn
  ]
}
