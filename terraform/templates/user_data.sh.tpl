#!/bin/bash
# EC2 bootstrap script — runs once on first launch
# Installs Java 17, downloads JARs from S3, sets up systemd services
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Chatrix bootstrap starting ==="

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
dnf update -y --security
dnf install -y \
  java-17-amazon-corretto-headless \
  amazon-cloudwatch-agent \
  awscli

# ---------------------------------------------------------------------------
# App user and directories
# ---------------------------------------------------------------------------
useradd -r -s /sbin/nologin chatrix
mkdir -p /opt/chatrix /var/log/chatrix /var/chatrix/uploads
chown -R chatrix:chatrix /opt/chatrix /var/log/chatrix /var/chatrix

# ---------------------------------------------------------------------------
# Pull secrets from SSM (only what Spring Boot can't read itself — JWT for Netty)
# ---------------------------------------------------------------------------
JWT_SECRET=$(aws ssm get-parameter \
  --region "${aws_region}" \
  --name "/chatrix/chatrix.jwt.secret" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

# ---------------------------------------------------------------------------
# Download application JARs from S3
# ---------------------------------------------------------------------------
echo "Downloading JARs from s3://${artifacts_bucket}/ ..."
aws s3 cp "s3://${artifacts_bucket}/chatrix-api.jar"       /opt/chatrix/chatrix-api.jar
aws s3 cp "s3://${artifacts_bucket}/chatrix-websocket.jar" /opt/chatrix/chatrix-websocket.jar
chown chatrix:chatrix /opt/chatrix/*.jar
chmod 550 /opt/chatrix/*.jar

# ---------------------------------------------------------------------------
# chatrix-api systemd service
# Spring Boot reads /chatrix/* from SSM Parameter Store automatically.
# No secrets in the command line.
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/chatrix-api.service << 'UNIT'
[Unit]
Description=Chatrix REST API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=chatrix
WorkingDirectory=/opt/chatrix
ExecStart=/usr/bin/java \
  -Xms256m -Xmx512m \
  -XX:+UseG1GC \
  -XX:MaxGCPauseMillis=200 \
  -jar /opt/chatrix/chatrix-api.jar \
  --spring.profiles.active=prod
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=120
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=chatrix-api

[Install]
WantedBy=multi-user.target
UNIT

# ---------------------------------------------------------------------------
# chatrix-websocket systemd service
# Netty server has no Spring — inject JWT_SECRET from SSM via EnvironmentFile
# ---------------------------------------------------------------------------
cat > /opt/chatrix/.env.websocket << EOF
WS_PORT=8081
JWT_SECRET=${JWT_SECRET}
EOF
chmod 600 /opt/chatrix/.env.websocket
chown chatrix:chatrix /opt/chatrix/.env.websocket

cat > /etc/systemd/system/chatrix-websocket.service << 'UNIT'
[Unit]
Description=Chatrix WebSocket Server (Netty)
After=network-online.target chatrix-api.service
Wants=network-online.target

[Service]
Type=simple
User=chatrix
WorkingDirectory=/opt/chatrix
EnvironmentFile=/opt/chatrix/.env.websocket
ExecStart=/usr/bin/java \
  -Xms128m -Xmx256m \
  -XX:+UseG1GC \
  -jar /opt/chatrix/chatrix-websocket.jar
Restart=on-failure
RestartSec=15
StartLimitIntervalSec=120
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=chatrix-websocket

[Install]
WantedBy=multi-user.target
UNIT

# ---------------------------------------------------------------------------
# Enable and start services
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable chatrix-api chatrix-websocket
systemctl start chatrix-api chatrix-websocket

# ---------------------------------------------------------------------------
# CloudWatch Agent — ship journald logs and collect memory/disk metrics
# ---------------------------------------------------------------------------
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWA'
{
  "agent": {
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}/user-data",
            "retention_in_days": 30
          }
        ]
      },
      "journald": {
        "collect_list": [
          {
            "unit": "chatrix-api",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}/chatrix-api"
          },
          {
            "unit": "chatrix-websocket",
            "log_group_name": "${log_group}",
            "log_stream_name": "{instance_id}/chatrix-websocket"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Chatrix/EC2",
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      }
    }
  }
}
CWA

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

echo "=== Chatrix bootstrap complete ==="
