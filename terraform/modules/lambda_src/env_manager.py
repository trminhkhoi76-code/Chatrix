"""
Chatrix Environment Manager Lambda
====================================
Actions  : start | stop | status | override
Trigger  : EventBridge Scheduler (scheduled) or Lambda Function URL / CLI (manual)

Manual usage (AWS CLI):
  aws lambda invoke --function-name chatrix-prod-env-manager \
    --payload '{"action":"start"}' /dev/null

  aws lambda invoke --function-name chatrix-prod-env-manager \
    --payload '{"action":"stop","include_redis":true}' /dev/null

  aws lambda invoke --function-name chatrix-prod-env-manager \
    --payload '{"action":"override","value":"force_on"}' /dev/null
    # value: force_on | force_off | none

Override behaviour:
  force_on  — scheduled stop is skipped; if called via override action, triggers start
  force_off — scheduled start is skipped; if called via override action, triggers stop
  none      — normal schedule resumes
"""

import boto3
import json
import logging
import os
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Environment variables (injected by Terraform) ────────────────────────────
REGION              = os.environ["REGION"]
EC2_ID              = os.environ["EC2_INSTANCE_ID"]
RDS_ID              = os.environ["RDS_IDENTIFIER"]
REDIS_GROUP_ID      = os.environ["REDIS_GROUP_ID"]
REDIS_NODE_TYPE     = os.environ["REDIS_NODE_TYPE"]
REDIS_SUBNET_GROUP  = os.environ["REDIS_SUBNET_GROUP"]
REDIS_SG_ID         = os.environ["REDIS_SECURITY_GROUP_ID"]
REDIS_PARAM_GROUP   = os.environ["REDIS_PARAM_GROUP"]
REDIS_AUTH_PARAM    = os.environ["REDIS_AUTH_TOKEN_PARAM"]   # SSM name for auth token
REDIS_HOST_PARAM    = os.environ["REDIS_HOST_PARAM"]         # SSM name to update on recreate
ENABLE_REDIS_STOP   = os.environ.get("ENABLE_REDIS_STOP", "false").lower() == "true"
OVERRIDE_PARAM      = "/chatrix/schedule/override"

# ── AWS clients ───────────────────────────────────────────────────────────────
ec2         = boto3.client("ec2",         region_name=REGION)
rds         = boto3.client("rds",         region_name=REGION)
elasticache = boto3.client("elasticache", region_name=REGION)
ssm         = boto3.client("ssm",         region_name=REGION)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_override() -> str:
    try:
        return ssm.get_parameter(Name=OVERRIDE_PARAM)["Parameter"]["Value"]
    except Exception:
        return "none"


def set_override(value: str):
    ssm.put_parameter(Name=OVERRIDE_PARAM, Value=value, Overwrite=True, Type="String")


def get_ec2_state() -> str:
    resp = ec2.describe_instances(InstanceIds=[EC2_ID])
    return resp["Reservations"][0]["Instances"][0]["State"]["Name"]


def get_rds_state() -> str:
    resp = rds.describe_db_instances(DBInstanceIdentifier=RDS_ID)
    return resp["DBInstances"][0]["DBInstanceStatus"]


def get_redis_state() -> str:
    try:
        resp = elasticache.describe_replication_groups(ReplicationGroupId=REDIS_GROUP_ID)
        return resp["ReplicationGroups"][0]["Status"]
    except elasticache.exceptions.ReplicationGroupNotFoundFault:
        return "deleted"
    except Exception as e:
        return f"unknown ({e})"


def get_status() -> dict:
    return {
        "ec2":      get_ec2_state(),
        "rds":      get_rds_state(),
        "redis":    get_redis_state(),
        "override": get_override(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Stop
# ─────────────────────────────────────────────────────────────────────────────

def do_stop(include_redis: bool) -> dict:
    results = {}

    # ── EC2 ──
    ec2_state = get_ec2_state()
    if ec2_state in ("running", "pending"):
        try:
            ec2.stop_instances(InstanceIds=[EC2_ID])
            results["ec2"] = "stopping"
        except Exception as e:
            results["ec2"] = f"error: {e}"
    else:
        results["ec2"] = f"already {ec2_state}"

    # ── RDS ──
    rds_state = get_rds_state()
    if rds_state == "available":
        try:
            rds.stop_db_instance(DBInstanceIdentifier=RDS_ID)
            results["rds"] = "stopping"
        except Exception as e:
            results["rds"] = f"error: {e}"
    else:
        results["rds"] = f"already {rds_state}"

    # ── ElastiCache (optional) ──
    if include_redis and ENABLE_REDIS_STOP:
        redis_state = get_redis_state()
        if redis_state not in ("deleted", "deleting"):
            try:
                elasticache.delete_replication_group(
                    ReplicationGroupId=REDIS_GROUP_ID,
                    RetainPrimaryCluster=False,
                )
                results["redis"] = "deleting"
            except Exception as e:
                results["redis"] = f"error: {e}"
        else:
            results["redis"] = f"already {redis_state}"
    else:
        results["redis"] = "skipped (enable_redis_stop=false or not requested)"

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Start
# ─────────────────────────────────────────────────────────────────────────────

def do_start() -> dict:
    results = {}

    # ── EC2 ──
    ec2_state = get_ec2_state()
    if ec2_state in ("stopped", "stopping"):
        try:
            ec2.start_instances(InstanceIds=[EC2_ID])
            results["ec2"] = "starting"
        except Exception as e:
            results["ec2"] = f"error: {e}"
    else:
        results["ec2"] = f"already {ec2_state}"

    # ── RDS ──
    rds_state = get_rds_state()
    if rds_state == "stopped":
        try:
            rds.start_db_instance(DBInstanceIdentifier=RDS_ID)
            results["rds"] = "starting"
        except Exception as e:
            results["rds"] = f"error: {e}"
    else:
        results["rds"] = f"already {rds_state}"

    # ── ElastiCache — recreate if deleted ──
    if ENABLE_REDIS_STOP:
        redis_state = get_redis_state()
        if redis_state == "deleted":
            results["redis"] = _recreate_redis()
        else:
            results["redis"] = f"already {redis_state}"
    else:
        results["redis"] = "skipped (enable_redis_stop=false)"

    return results


def _recreate_redis() -> str:
    """Recreate ElastiCache replication group and update SSM endpoint."""
    try:
        auth_token = ssm.get_parameter(
            Name=REDIS_AUTH_PARAM, WithDecryption=True
        )["Parameter"]["Value"]

        elasticache.create_replication_group(
            ReplicationGroupId=REDIS_GROUP_ID,
            Description="Chatrix Redis cache",
            NumCacheClusters=1,
            CacheNodeType=REDIS_NODE_TYPE,
            Engine="redis",
            EngineVersion="7.1",
            CacheSubnetGroupName=REDIS_SUBNET_GROUP,
            SecurityGroupIds=[REDIS_SG_ID],
            CacheParameterGroupName=REDIS_PARAM_GROUP,
            AtRestEncryptionEnabled=True,
            TransitEncryptionEnabled=True,
            AuthToken=auth_token,
            AutomaticFailoverEnabled=False,
            MultiAZEnabled=False,
            SnapshotRetentionLimit=1,
            SnapshotWindow="17:00-18:00",
            Tags=[{"Key": "ManagedBy", "Value": "terraform"}],
        )
        logger.info("ElastiCache creation initiated — polling for availability...")

        # Poll up to 10 minutes (Lambda timeout set to 600s)
        for attempt in range(60):
            time.sleep(10)
            state = get_redis_state()
            logger.info(f"Redis state [{attempt+1}/60]: {state}")
            if state == "available":
                # Fetch the new primary endpoint and update SSM
                resp = elasticache.describe_replication_groups(
                    ReplicationGroupId=REDIS_GROUP_ID
                )
                new_endpoint = resp["ReplicationGroups"][0]["NodeGroups"][0][
                    "PrimaryEndpoint"
                ]["Address"]
                ssm.put_parameter(
                    Name=REDIS_HOST_PARAM,
                    Value=new_endpoint,
                    Overwrite=True,
                    Type="String",
                )
                logger.info(f"SSM updated: {REDIS_HOST_PARAM} = {new_endpoint}")
                return f"created (endpoint: {new_endpoint})"

        return "timeout waiting for redis (check CloudWatch logs)"

    except Exception as e:
        logger.exception("Failed to recreate ElastiCache")
        return f"error: {e}"


# ─────────────────────────────────────────────────────────────────────────────
# Lambda handler
# ─────────────────────────────────────────────────────────────────────────────

def lambda_handler(event, context):
    logger.info("Event: %s", json.dumps(event))

    # ── Parse action ──
    # EventBridge sends: {"action": "stop", "include_redis": true}
    # Function URL sends HTTP request with JSON body or query params
    if "requestContext" in event:
        # HTTP invocation via Function URL
        body = {}
        if event.get("body"):
            raw = event["body"]
            body = json.loads(raw) if isinstance(raw, str) else raw
        qs   = event.get("queryStringParameters") or {}
        action        = body.get("action")        or qs.get("action",        "status")
        include_redis = body.get("include_redis", False) or qs.get("include_redis") == "true"
        override_val  = body.get("value")         or qs.get("value",         "none")
    else:
        # Direct invoke / EventBridge
        action        = event.get("action", "status")
        include_redis = event.get("include_redis", False)
        override_val  = event.get("value", "none")

    override = get_override()
    logger.info("action=%s include_redis=%s current_override=%s", action, include_redis, override)

    # ── Route ──
    if action == "status":
        return _http(200, get_status())

    elif action == "stop":
        if override == "force_on":
            return _http(200, {"skipped": True, "reason": "force_on override is active — clear it first with action=override&value=none"})
        result = do_stop(include_redis=include_redis)
        return _http(200, {"action": "stop", "results": result, "include_redis": include_redis})

    elif action == "start":
        if override == "force_off":
            return _http(200, {"skipped": True, "reason": "force_off override is active — clear it first with action=override&value=none"})
        result = do_start()
        return _http(200, {"action": "start", "results": result})

    elif action == "override":
        if override_val not in ("none", "force_on", "force_off"):
            return _http(400, {"error": "value must be: none | force_on | force_off"})
        set_override(override_val)
        # Immediately act on the override
        op_result = {}
        if override_val == "force_on":
            op_result = do_start()
        elif override_val == "force_off":
            op_result = do_stop(include_redis=False)  # Don't delete Redis on manual force-off
        return _http(200, {"override": override_val, "immediate_action": op_result, "status": get_status()})

    else:
        return _http(400, {"error": f"Unknown action '{action}'. Valid: start | stop | status | override"})


def _http(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str),
    }
