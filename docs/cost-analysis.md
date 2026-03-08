# Cost Analysis Report

**Date:** March 8, 2026  
**Period:** Last 30 days (baseline)  
**Project:** enterprise-platform  
**Environment:** Development (eu-north-1)

**Status:** ✅ Security hardening complete, infrastructure optimized for cost

---

## Executive Summary

Current infrastructure costs approximately **€141/month** for a development environment. With proposed optimizations, security hardening is **fully deployed** (VPC endpoints, RDS SSL), reducing future costs. Additional cost savings of **€10-15/month** can be achieved by implementing **PATH A task scheduling** (stop tasks 6pm-9am), reducing total cost to **€126-131/month**. 

**Note:** Initial cost analysis predicted €50-70/month savings through memory reduction, but AWS Fargate constraints prevent reducing below 512 MB for 0.25 vCPU tasks. Security hardening is prioritized over aggressive cost cuts in this environment.

---

## Current Monthly Costs (Baseline)

### Infrastructure Cost Breakdown

| AWS Service | Resource | Monthly Cost | Usage | Notes |
|-------------|----------|--------------|-------|-------|
| **ECS Fargate** | 2 tasks × (0.25 vCPU, 512 MB) | €24.00 | Baseline 2 tasks, auto-scale 1-6 | $0.04048/vCPU/hr, $0.004445/GB/hr |
| **ALB** | 1 Application Load Balancer | €16.20 | Constant | €11.52 fixed + data processing |
| **NAT Gateway** | 1 NAT Gateway (single, eu-north-1a) | €32.40 | Always running | €32.40 per NAT, €0.032 per GB |
| **RDS** | db.t3.micro PostgreSQL (20GB gp3) | €28.00 | On-demand | €0.0384/hour + storage €0.11/GB |
| **EBS Storage** | RDS storage (20 GB gp3) | €2.20 | Auto-scales to 40 GB | €11/mo base, auto-scaling to 40 GB = €22 max |
| **CloudWatch** | Logs + Metrics + Alarms | €12.00 | 7-day retention | Estimated (logs €0.50/GB ingested) |
| **ECR** | Container registry (~500 MB) | €0.50 | Repository storage | €0.10/GB/month |
| **Data Transfer** | Outbound traffic | €5.00 | Low (dev environment) | ~50 GB/month at €0.10/GB |
| **VPC Endpoints** | 4 Interface endpoints | €14.40 | Secrets Manager, ECR API, ECR DKR, monitoring | €7.20/endpoint/month + data processing |
| **CloudWatch Enhanced Monitoring** | RDS Monitoring | €6.00 | High granularity | €0.5 per DB instance per hour (estimated) |
| **Secrets Manager** | Database secret | €0.40 | 1 secret, 1 rotation attempt | €0.40/secret/month |
| **AWS Budgets** | Cost monitoring | Free | - | - |
| **TOTAL** | | **€141.10/month** | | Projected monthly spend |

### Cost Breakdown by Category

| Category | Cost | Percentage |
|----------|------|-----------|
| **Compute (ECS)** | €24.00 | 17% |
| **Network (ALB, NAT, VPC, Data Transfer)** | €68.10 | 48% |
| **Database (RDS, Storage, Monitoring)** | €36.20 | 26% |
| **Logging & Secrets** | €12.90 | 9% |
| **TOTAL** | **€141.20** | 100% |

---

## Cost Optimization Opportunities

### Priority Matrix

#### **HIGH PRIORITY** - Save €10-20/month

| Optimization | Current | Optimized | Savings | Implementation |
|--------------|---------|-----------|---------|-----------------|
| **ECS Memory Optimization** | 0.25 vCPU, 512 MB | 0.25 vCPU, 512 MB | €0 | ⚠️ Fargate minimum for 0.25 vCPU is 512 MB |
| **ECS Task Scheduling** | Always running | Stop 6pm-9am (10 hrs/day) | €10-15/month | EventBridge + Lambda (Phase 4.5) |
| **VPC Endpoints** | Not deployed | Deployed ✓ | Critical security (no cost) | ✅ IMPLEMENTED |
| **RDS Hardening** | No SSL, minimal logging | RDS SSL enforced, DDL logging | Security benefit | ✅ IMPLEMENTED |
| **CloudWatch Log Retention** | 7 days → 30 days | 30 days retained | Security benefit | ✅ IMPLEMENTED |
| **REALISTIC SAVINGS** (PATH A) | **€141.10** | **€130-135** | **€10-15/month** | Task scheduling only |

#### **MEDIUM PRIORITY** - Save €5-15/month

| Optimization | Impact | Effort | Notes |
|--------------|--------|--------|-------|
| RDS Reserved Instance (1-year) | -€10/month | High commitment | Requires 1-year contract |
| CloudWatch Metrics Filtering | -€2-3/month | Low | Only monitor critical metrics |
| S3 Gateway Endpoint removal | -€0/month (included in route) | N/A | Already no S3 usage |
| Auto-scaling tuning | -€5/month | Medium | Reduce max tasks from 6 to 4 |

#### **LOW PRIORITY** - Minimal Impact

| Item | Savings | Notes |
|------|---------|-------|
| ECR image cleanup | <€1/month | Monthly baseline charge only |
| Elastic IP consolidation | €0 | Using single NAT already |
| Aurora Serverless (vs RDS) | N/A | Overkill for dev, more complex |

---

## Implementation Paths

### PATH A: Development-Optimized (⭐ RECOMMENDED FOR DEV)

**Target Budget:** €60-70/month  
**Cost Savings:** -€70-80/month from baseline  
**Trade-offs:** Acceptable downtime during off-hours, reduced memory headroom

#### Changes Required

```
1. ECS Task Scheduling (EventBridge)
   - Stop all ECS tasks at 6pm daily
   - Start all ECS tasks at 9am daily
   - Manually start outside these hours if needed
   - Savings: €10-15/month

2. Right-Size ECS Memory
   - Current: 0.25 vCPU, 512 MB
   - Proposed: 0.25 vCPU, 256 MB
   - Prerequisite: Verify load testing shows safe headroom
   - Savings: €12/month
   - Risk: Potential OOM errors under load (mitigated by aggressive scaling)

3. Reduce CloudWatch Retention (Optional)
   - Current: 30 days (after security hardening)
   - Optional: 7 days (compliance risk)
   - Savings: €2-3/month
   - Recommendation: SKIP (30 days is reasonable)

4. Consolidate Auto-Scaling Limits (Optional)
   - Current: min=1, max=6
   - Proposed: min=1, max=4
   - Savings: €5-10/month
   - Trade-off: Reduced burst capacity
```

#### PATH A Monthly Cost Estimate

| Service | Current | Optimized | Notes |
|---------|---------|-----------|-------|
| ECS (0.25 vCPU, 512 MB × 1-6 tasks) | €24 | €24 | ⚠️ Fargate min 512MB for 0.25vCPU; no memory reduction possible |
| ALB | €16.20 | €16.20 | No change |
| NAT Gateway | €32.40 | €32.40 | Keep (needed for outbound) |
| RDS + Storage | €36.20 | €36.20 | No change |
| CloudWatch + Logging | €12.90 | €12.90 | 30-day retention (security) |
| VPC Endpoints | €0 | €14.40 | ✅ Now enabled (mandatory for security) |
| **TOTAL (Before Task Scheduling)** | **€141.10** | **€141.10** | **No change yet** |
| ECS Task Scheduling (deferred) | - | -€10-15 | Stop 6pm-9am saves €10-15/month |
| **REALISTIC TOTAL (PATH A)** | | **€126-131** | **Save €10-15/month** |

---

### PATH B: Production-Ready (High Availability)

**Target Budget:** €100-120/month  
**Cost Savings:** -€20-40/month from baseline (optional RDS RI)  
**Trade-offs:** Maintain multi-AZ resilience, always-on

#### Changes Required

```
1. Keep Current Configuration
   - No NAT reduction (maintain HA across AZs)
   - Keep current ECS sizing (0.25 vCPU, 512 MB)
   - Keep 24/7 operation

2. Optional: RDS Reserved Instance (1-year)
   - On-demand: €28/month
   - Reserved (1-year): €18/month
   - Savings: €10/month
   - Trade-off: 1-year commitment (can't resize)

3. Optional: Optimize Auto-Scaling
   - Fine-tune scale-up/down thresholds
   - Reduce unnecessary task churn
   - Savings: €2-5/month
```

#### PATH B Monthly Cost Estimate

| Service | Current | Optimized | Notes |
|---------|---------|-----------|-------|
| ECS (2 tasks in AZs) | €24 | €24 | No change |
| ALB | €16.20 | €16.20 | No change |
| NAT Gateway | €32.40 | €32.40 | Keep for HA |
| RDS (on-demand vs RI) | €28 | €18 | -€10 (if RI purchased) |
| CloudWatch + Logging | €12.90 | €12.90 | No change |
| VPC Endpoints | €14.40 | €14.40 | Keep |
| **TOTAL (with RI)** | **€141.10** | **€117.10** | **Save €24/month** |

---

## Cost Monitoring & Control

### AWS Budgets Configuration

**Budget Name:** enterprise-platform-monthly  
**Budget Limit:** €150/month (20% buffer above anticipated)  
**Alert Threshold:** 80% (€120) - email alert  
**Alert Frequency:** Monthly

**Subscriber Email:** [to be configured]

### AWS Cost Anomaly Detection

| Metric | Threshold | Action |
|--------|-----------|--------|
| Daily cost anomaly | +€10 above baseline | Email alert |
| Service cost spike | > 2x normal | Immediate alert |
| Forecast exceeds budget | > €150 | Alert and review |

### CloudWatch Custom Dashboard

Monitor:
- ECS task count (via auto-scaling)
- NAT Gateway data transfer (baseline vs peak)
- RDS connections and storage growth
- CloudWatch log ingestion rate

---

## Recommendations

### For Development Environment (Current)

**RECOMMENDED: Implement PATH A**

**Rationale:**
- Enterprise-platform is development/learning environment
- Single-AZ acceptable for non-production
- Significant cost savings (€70/month)
- Off-hours shutdown appropriate for dev
- Can transition to PATH B if becomes production-like

**Action Items (Day 32):**
1. ✅ Create cost analysis (this document)
2. ✅ Approve PATH A optimization strategy
3. ⏳ Configure ECS task scheduling (EventBridge + Lambda)
4. ⏳ Verify load test results confirm 256 MB is safe
5. ⏳ Deploy budget monitoring (AWS Budgets + alerts)
6. ⏳ Document in runbooks

### If Transitioning to Production

**SWITCH TO PATH B**

**Prerequisite Changes:**
- [ ] Enable multi-AZ RDS (doubles RDS cost to €56/month)
- [ ] Deploy NAT Gateway in each AZ (doubles to €65/month)
- [ ] Maintain 24/7 operation (no task scheduling)
- [ ] Increase monitoring (add VPC Flow Logs, CloudTrail)
- [ ] Implement backup and DR strategy
- [ ] Purchase RDS Reserved Instance for 3-year commitment

**Estimated Production Cost:** €200-250/month (vs current €141)

---

## Financial Impact Summary

### 12-Month Projections

| Scenario | Monthly | Annual | 12-Month Savings |
|----------|---------|--------|-----------------|
| Baseline (No optimization) | €141 | €1,692 | - |
| PATH A Current (VPC endpoints deployed + security hardening) | €141 | €1,692 | €0 (security prioritized) |
| PATH A + Task Scheduling (Phase 4.5) | €130 | €1,560 | **€132/year** |
| PATH B (Production-Ready) | €117 | €1,404 | **€288/year** |

### Cost per Metric

| Metric | Cost/Unit | Status |
|--------|-----------|--------|
| Server hours (ECS) | €0.01/task-hour | Good |
| API requests | €0.00/request | Excellent (no per-request charge) |
| Network cost | €0.032/GB (NAT) | Acceptable |
| Database cost | €0.0384/RDS hour | Standard |

---

## Implementation Timeline

### Day 32 - Phase 4 (Cost Optimization)

**Step 1: Review and Approve (15 min)**
- [ ] Review this cost analysis
- [ ] Approve PATH A or PATH B
- [ ] Confirm budget threshold preference

**Step 2: Update Terraform (Terraform variables) (30 min)**
- [ ] Set `ecs_task_memory = 256` (PATH A only)
- [ ] Adjust `max_capacity` if needed
- [ ] Update `backup_retention_period = 7` (default already)

**Step 3: Configure Monitoring (30 min)**
- [ ] Create AWS Budgets configuration
- [ ] Enable Cost Anomaly Detection
- [ ] Set up email notifications

**Step 4: Document Changes (15 min)**
- [ ] Update runbooks
- [ ] Document PATH A/B decision rationale
- [ ] Create troubleshooting guide

### Day 32 - Phase 5 (Terraform & Commit)

**Step 1: Terraform Validation**
- [ ] Run `terraform plan`
- [ ] Verify no unexpected changes
- [ ] Review resource modifications

**Step 2: Git Commit**
- [ ] Stage all Terraform changes
- [ ] Include cost analysis in commit message
- [ ] Push to GitHub

**Step 3: GitHub Actions**
- [ ] Monitor workflow results
- [ ] Verify build succeeds
- [ ] (Optional) Manual terraform apply if approved

---

## Notes & Assumptions

1. **Region:** All costs in EUR for eu-north-1 (Northern Europe)
2. **Baseline Usage:** Minimal production traffic (dev environment)
3. **Data Transfer:** Assumes ~50 GB/month outbound (typical for dev)
4. **Retention:** CloudWatch log retention set to 30 days; RDS backup 1 day (AWS Free Tier maximum)
5. **Free Tier Constraint:** RDS backup retention limited to 1 day while on free tier. Upgrade to 7 days after account upgrade.
6. **Auto-Scaling:** Assumes 2-6 tasks average across day
7. **No RI:** Baseline costs are on-demand (no Reserved Instances)
8. **Compliance:** All costs include security hardening measures

---

## Appendix: AWS Pricing Reference

### eu-north-1 Pricing (as of March 2026)

- **ECS Fargate vCPU:** €0.04048/hour
- **ECS Fargate Memory:** €0.004445/GB/hour
- **ALB:** €11.52/month + €0.006/LCU
- **NAT Gateway:** €32.40/month + €0.032/GB
- **RDS db.t3.micro:** €0.0384/hour
- **RDS Storage (gp3):** €0.11/GB/month
- **CloudWatch Logs:** €0.50/GB ingested
- **VPC Endpoint (Interface):** €7.20/month + data processing
- **RDS Reserved Instance (1-year):** ~€210/year (~€17.50/month)

**Data last updated:** March 8, 2026

---

## Approval & Next Steps

### Decision Required

- [ ] Approve PATH A (Development-Optimized) - **RECOMMENDED**
- [ ] Approve PATH B (Production-Ready)
- [ ] Custom path (describe below)

**Chosen Path:** PATH A (Development-Optimized)  
**Rationale:** Development environment, cost optimization priority  
**Approval Date:** March 8, 2026

### Implementation Status

- [x] Cost analysis completed
- [ ] Budget configurations created (Phase 4C)
- [ ] Terraform changes applied
- [ ] AWS Budget deployed
- [ ] Email notifications configured
- [ ] Runbooks updated with cost tracking

**Owner:** Enterprise Platform Team  
**Review Frequency:** Monthly (first Friday)  
**Next Review Date:** April 5, 2026
