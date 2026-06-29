#!/usr/bin/env python3
"""
Parse terraform plan JSON and identify IAM actions missing from a policy file.

Usage:
    parse_new_resources.py <plan.json> <policy.json>

Exits 0 always; outputs JSON to stdout:
    {
      "missing": {"aws_vpc": ["ec2:CreateVpc", ...]},
      "all_missing": ["ec2:CreateVpc", ...],
      "affected_types": ["aws_vpc", ...]
    }
"""

import json
import sys
from pathlib import Path

RESOURCE_IAM_MAP = {
    "aws_vpc": [
        "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
    ],
    "aws_subnet": [
        "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
    ],
    "aws_internet_gateway": [
        "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
    ],
    "aws_route_table": [
        "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
        "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:CreateRoute", "ec2:DeleteRoute",
    ],
    "aws_route_table_association": [
        "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
        "ec2:DescribeRouteTables",
    ],
    "aws_security_group": [
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
    ],
    "aws_security_group_rule": [
        "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
        "ec2:DescribeSecurityGroupRules",
    ],
    "aws_vpc_endpoint": [
        "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints",
        "ec2:DescribeVpcEndpoints", "ec2:ModifyVpcEndpoint",
    ],
    "aws_lb": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:AddTags", "elasticloadbalancing:DescribeTags",
    ],
    "aws_alb": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:DescribeLoadBalancerAttributes",
        "elasticloadbalancing:AddTags", "elasticloadbalancing:DescribeTags",
    ],
    "aws_lb_target_group": [
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:AddTags",
    ],
    "aws_alb_target_group": [
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes",
        "elasticloadbalancing:DescribeTargetGroupAttributes",
        "elasticloadbalancing:AddTags",
    ],
    "aws_lb_listener": [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:ModifyListener",
    ],
    "aws_alb_listener": [
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:ModifyListener",
    ],
    "aws_lb_listener_rule": [
        "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        "elasticloadbalancing:DescribeRules", "elasticloadbalancing:ModifyRule",
    ],
    "aws_ecr_repository": [
        "ecr:CreateRepository", "ecr:DeleteRepository",
        "ecr:DescribeRepositories", "ecr:GetRepositoryPolicy",
        "ecr:SetRepositoryPolicy", "ecr:DeleteRepositoryPolicy",
        "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy", "ecr:ListTagsForResource",
        "ecr:TagResource", "ecr:UntagResource",
    ],
    "aws_ecr_lifecycle_policy": [
        "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy",
    ],
    "aws_ecs_cluster": [
        "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
        "ecs:UpdateCluster", "ecs:PutClusterCapacityProviders",
        "ecs:TagResource",
    ],
    "aws_ecs_cluster_capacity_providers": [
        "ecs:PutClusterCapacityProviders", "ecs:DescribeClusters",
    ],
    "aws_ecs_service": [
        "ecs:CreateService", "ecs:DeleteService",
        "ecs:DescribeServices", "ecs:UpdateService",
        "ecs:TagResource",
    ],
    "aws_ecs_task_definition": [
        "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
        "ecs:DescribeTaskDefinition", "ecs:TagResource",
    ],
    "aws_db_instance": [
        "rds:CreateDBInstance", "rds:DeleteDBInstance",
        "rds:DescribeDBInstances", "rds:ModifyDBInstance",
        "rds:AddTagsToResource", "rds:ListTagsForResource",
    ],
    "aws_db_subnet_group": [
        "rds:CreateDBSubnetGroup", "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups", "rds:ModifyDBSubnetGroup",
        "rds:AddTagsToResource", "rds:ListTagsForResource",
    ],
    "aws_db_parameter_group": [
        "rds:CreateDBParameterGroup", "rds:DeleteDBParameterGroup",
        "rds:DescribeDBParameterGroups", "rds:ModifyDBParameterGroup",
        "rds:AddTagsToResource", "rds:ListTagsForResource",
    ],
    "aws_elasticache_cluster": [
        "elasticache:CreateCacheCluster", "elasticache:DeleteCacheCluster",
        "elasticache:DescribeCacheClusters",
        "elasticache:AddTagsToResource", "elasticache:ListTagsForResource",
    ],
    "aws_elasticache_replication_group": [
        "elasticache:CreateReplicationGroup", "elasticache:DeleteReplicationGroup",
        "elasticache:DescribeReplicationGroups", "elasticache:ModifyReplicationGroup",
        "elasticache:AddTagsToResource", "elasticache:ListTagsForResource",
    ],
    "aws_elasticache_subnet_group": [
        "elasticache:CreateCacheSubnetGroup", "elasticache:DeleteCacheSubnetGroup",
        "elasticache:DescribeCacheSubnetGroups", "elasticache:ModifyCacheSubnetGroup",
    ],
    "aws_s3_bucket": [
        "s3:CreateBucket", "s3:DeleteBucket",
        "s3:GetBucketLocation", "s3:GetBucketPolicy",
        "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
        "s3:GetBucketAcl", "s3:PutBucketAcl",
        "s3:GetBucketVersioning", "s3:PutBucketVersioning",
        "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketLogging", "s3:PutBucketLogging",
        "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
        "s3:GetBucketTagging", "s3:PutBucketTagging",
        "s3:GetBucketCORS", "s3:PutBucketCORS",
        "s3:GetBucketObjectLockConfiguration",
    ],
    "aws_s3_bucket_versioning": [
        "s3:GetBucketVersioning", "s3:PutBucketVersioning",
    ],
    "aws_s3_bucket_server_side_encryption_configuration": [
        "s3:GetEncryptionConfiguration", "s3:PutEncryptionConfiguration",
    ],
    "aws_s3_bucket_public_access_block": [
        "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
    ],
    "aws_s3_bucket_lifecycle_configuration": [
        "s3:GetLifecycleConfiguration", "s3:PutLifecycleConfiguration",
    ],
    "aws_iam_role": [
        "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
        "iam:UpdateAssumeRolePolicy", "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies", "iam:PassRole",
        "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
    ],
    "aws_iam_role_policy": [
        "iam:PutRolePolicy", "iam:GetRolePolicy",
        "iam:DeleteRolePolicy", "iam:ListRolePolicies",
    ],
    "aws_iam_role_policy_attachment": [
        "iam:AttachRolePolicy", "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
    ],
    "aws_iam_policy": [
        "iam:CreatePolicy", "iam:DeletePolicy",
        "iam:GetPolicy", "iam:GetPolicyVersion",
        "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
        "iam:ListPolicyVersions",
    ],
    "aws_ssm_parameter": [
        "ssm:PutParameter", "ssm:GetParameter",
        "ssm:GetParameters", "ssm:DeleteParameter",
        "ssm:DescribeParameters", "ssm:AddTagsToResource",
        "ssm:ListTagsForResource",
    ],
    "aws_lambda_function": [
        "lambda:CreateFunction", "lambda:DeleteFunction",
        "lambda:GetFunction", "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration", "lambda:AddPermission",
        "lambda:RemovePermission", "lambda:GetPolicy",
        "lambda:ListVersionsByFunction", "lambda:TagResource",
        "lambda:GetFunctionConfiguration",
    ],
    "aws_lambda_permission": [
        "lambda:AddPermission", "lambda:RemovePermission",
        "lambda:GetPolicy",
    ],
    "aws_scheduler_schedule": [
        "scheduler:CreateSchedule", "scheduler:DeleteSchedule",
        "scheduler:GetSchedule", "scheduler:UpdateSchedule",
        "scheduler:TagResource",
    ],
    "aws_scheduler_schedule_group": [
        "scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup",
        "scheduler:GetScheduleGroup",
    ],
    "aws_cloudwatch_log_group": [
        "logs:CreateLogGroup", "logs:DeleteLogGroup",
        "logs:DescribeLogGroups", "logs:PutRetentionPolicy",
        "logs:TagLogGroup", "logs:ListTagsLogGroup",
    ],
    "aws_cloudwatch_metric_alarm": [
        "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
    ],
    "aws_appautoscaling_target": [
        "application-autoscaling:RegisterScalableTarget",
        "application-autoscaling:DeregisterScalableTarget",
        "application-autoscaling:DescribeScalableTargets",
    ],
    "aws_appautoscaling_policy": [
        "application-autoscaling:PutScalingPolicy",
        "application-autoscaling:DeleteScalingPolicy",
        "application-autoscaling:DescribeScalingPolicies",
    ],
}


def get_existing_actions(policy_path: Path) -> set:
    with open(policy_path) as f:
        policy = json.load(f)
    actions: set = set()
    for statement in policy.get("Statement", []):
        if statement.get("Effect") != "Allow":
            continue
        raw = statement.get("Action", [])
        if isinstance(raw, str):
            raw = [raw]
        for a in raw:
            if a == "*":
                return {"*"}
            actions.add(a)
    return actions


def is_covered(action: str, existing: set) -> bool:
    """Return True if action is granted by the existing action set.

    Handles three levels:
      "*"           — full wildcard (all services)
      "ec2:*"       — service-level wildcard
      "ec2:CreateVpc" — exact action
    """
    if "*" in existing or action in existing:
        return True
    # service-level wildcard: "ec2:*" covers "ec2:CreateVpc"
    if ":" in action:
        service = action.split(":")[0]
        if f"{service}:*" in existing:
            return True
    return False


def get_affected_resource_types(plan_path: Path) -> set:
    with open(plan_path) as f:
        plan = json.load(f)
    affected: set = set()
    for change in plan.get("resource_changes", []):
        actions = change.get("change", {}).get("actions", [])
        if any(a in actions for a in ("create", "update")):
            rtype = change.get("type", "")
            if rtype:
                affected.add(rtype)
    return affected


def main() -> None:
    if len(sys.argv) != 3:
        print("Usage: parse_new_resources.py <plan.json> <policy.json>", file=sys.stderr)
        sys.exit(1)

    plan_path = Path(sys.argv[1])
    policy_path = Path(sys.argv[2])

    existing = get_existing_actions(policy_path)
    if "*" in existing:
        result = {"missing": {}, "all_missing": [], "affected_types": []}
        print(json.dumps(result))
        return

    affected_types = get_affected_resource_types(plan_path)
    missing_by_type: dict = {}
    for rtype in sorted(affected_types):
        required = RESOURCE_IAM_MAP.get(rtype, [])
        missing = [a for a in required if not is_covered(a, existing)]
        if missing:
            missing_by_type[rtype] = missing

    all_missing = sorted({a for acts in missing_by_type.values() for a in acts})
    result = {
        "missing": missing_by_type,
        "all_missing": all_missing,
        "affected_types": sorted(affected_types),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()