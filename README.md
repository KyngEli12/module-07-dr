# Module 07 — Disaster Recovery on AWS

Hands-on lab demonstrating AWS disaster recovery strategies using a multi-region active/passive architecture with automated failover.

## What This Lab Covers

- **DR Strategy**: Warm Standby across two AWS regions (us-east-1 primary, us-west-2 secondary)
- **RTO/RPO**: Minimized recovery time and data loss using continuous replication
- **Route 53**: Health checks and DNS failover routing policies
- **RDS**: Cross-region read replica promotion for database failover
- **S3**: Cross-region replication for object storage redundancy
- **Infrastructure as Code**: All resources provisioned with Terraform

## Architecture

```
us-east-1 (Primary)          us-west-2 (Secondary)
├── VPC + Subnets             ├── VPC + Subnets
├── EC2 Application Layer     ├── EC2 Standby Layer
├── RDS MySQL (Primary)  ───► ├── RDS Read Replica
└── S3 Bucket            ───► └── S3 Replica Bucket
         │                              │
         └──── Route 53 Health Check ───┘
                  (auto-failover)
```

## Key Concepts Demonstrated

| Concept | Implementation |
|---|---|
| Warm Standby | Secondary region pre-provisioned at reduced capacity |
| DNS Failover | Route 53 health checks trigger automatic rerouting |
| Data Replication | RDS cross-region read replica + S3 CRR |
| IaC | Terraform manages both regions from one codebase |

## Technologies Used

- AWS Route 53 (health checks, failover routing)
- Amazon RDS MySQL (cross-region read replica)
- Amazon S3 (cross-region replication)
- EC2, VPC, Security Groups
- Terraform

## Portfolio

Part of [Eli's AWS Cloud Architecture Portfolio](https://d2xgifno1trxs4.cloudfront.net) — a 9-module hands-on lab series covering core cloud architecture domains.
