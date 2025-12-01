# NextLean Scan: Subscription-Based Feature Access Architecture

**Document Version:** 1.0
**Date:** 2025-11-30
**Author:** NextLean Architect Agent

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Analysis](#2-current-state-analysis)
3. [Subscription Tiers](#3-subscription-tiers)
4. [Database Schema Changes](#4-database-schema-changes)
5. [Feature Gating Strategy](#5-feature-gating-strategy)
6. [Frontend Implementation](#6-frontend-implementation)
7. [Backend Implementation](#7-backend-implementation)
8. [Upgrade/Downgrade Flows](#8-upgradedowngrade-flows)
9. [Usage Tracking & Warnings](#9-usage-tracking--warnings)
10. [Implementation Order](#10-implementation-order)

---

## 1. Executive Summary

This document defines the comprehensive architecture for implementing subscription-based feature access in NextLean Scan. The system will:

- Gate features based on subscription tier (Free Trial, Basic, Pro, Enterprise)
- Enforce usage limits (projects, storage, team members)
- Provide real-time usage tracking and warnings
- Support graceful upgrade/downgrade flows
- Handle trial expiration and grace periods

### Key Design Decisions

1. **Database-Driven Configuration**: All plan features are stored in `subscription_plans` table, not hardcoded
2. **Multi-Layer Enforcement**: Features are gated at RLS, Edge Function, and UI levels
3. **Soft Limits**: Warnings before hard limits are reached
4. **Grace Periods**: Allow continued access briefly after subscription issues

---

## 2. Current State Analysis

### Existing Infrastructure

The platform already has a solid subscription foundation:

**Database Tables:**
- `subscription_plans` - Defines plan tiers with features and limits
- `showrooms.subscription_status` - Enum: trial, active, past_due, canceled, suspended
- `showrooms.subscription_plan_id` - FK to current plan
- `showrooms.project_count_this_period` - Usage tracking
- `invoices` - Billing history
- `subscription_history` - Plan change audit log

**Existing Helper Functions:**
- `check_plan_feature(showroom_id, feature)` - Boolean feature check
- `check_project_limit(showroom_id)` - Project limit enforcement

**Frontend Utilities (dashboard/src/lib/subscription.ts):**
- `getPlanFeatures()`, `hasFeature()`, `canCreateProject()`
- Plan feature definitions (currently hardcoded, should sync with DB)

### Gaps Identified

1. **No frontend context/provider** for subscription state
2. **Edge Functions don't check limits** before allowing actions
3. **No usage warning system** (soft limits)
4. **No grace period handling** for trial/payment issues
5. **iOS app doesn't receive limit info** in config
6. **Products limit not tracked** (only projects)
7. **Storage usage not tracked**
8. **Team member count not enforced**

---

## 3. Subscription Tiers

### 3.1 Tier Definitions

| Feature | Free Trial | Basic ($99/mo) | Pro ($249/mo) | Enterprise (Custom) |
|---------|------------|----------------|---------------|---------------------|
| **Duration** | **7 days (FULL Pro features)** | Monthly/Yearly | Monthly/Yearly | Annual contract |
| **Projects/month** | **Unlimited** | 25 | Unlimited | Unlimited |
| **Products** | **500** | 100 | 500 | Unlimited |
| **Storage** | **100 GB** | 10 GB | 100 GB | Unlimited |
| **Team members** | **10** | 3 | 10 | Unlimited |
| **Custom branding** | **Full** | Full | Full | Full + White-label |
| **Webhook integration** | **Yes** | No | Yes | Yes |
| **API access** | **Yes** | No | Yes | Yes |
| **AutoCAD export** | **Yes** | No | Yes | Yes |
| **Priority support** | **Yes** | No | Yes | Yes |
| **CRM integration** | No | No | No | Yes |
| **AI processing** | No | No | No | Yes |
| **Scan quality** | **HD** | Standard | HD | HD + Custom |

### 3.2 Pricing Rationale

- **Trial**: **7-day trial with FULL Pro features** - Let users experience everything the platform offers. This approach maximizes conversion by showing the full value upfront. After 7 days, users must subscribe to continue.
- **Basic**: Entry-level for small showrooms, covers operational costs
- **Pro**: Growth tier with automation features (webhooks, API), best margins
- **Enterprise**: Custom for large chains, includes dedicated support

### 3.3 Feature Tiers Visual

```
Enterprise: All Features + CRM + AI + Dedicated Support
     |
    Pro: Unlimited Projects + Webhooks + API + AutoCAD + Priority
     |
   Basic: Reasonable Limits + Full Branding + Email Support

  Trial: FULL Pro Features for 7 days (then must subscribe)
         ^-- Same as Pro tier, just time-limited
```

### 3.4 Trial Strategy

The trial strategy is designed to maximize conversions:

1. **Full Access**: Trial users get 100% of Pro features for 7 days
2. **No Feature Restrictions**: Users can test webhooks, API, AutoCAD export, etc.
3. **Clear Value**: Users experience the full platform value before committing
4. **Simple Choice**: After trial, choose Basic ($99), Pro ($249), or Enterprise
5. **Grace Period**: 3-day grace period after trial expires before account suspension

---

## 4. Database Schema Changes

### 4.1 Migration: Update subscription_plans Table

```sql
-- ============================================
-- Migration: 016_enhanced_subscription_limits
-- ============================================

-- Add new limit columns to subscription_plans
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS product_limit INT,
ADD COLUMN IF NOT EXISTS scan_quality TEXT DEFAULT 'standard', -- 'standard', 'hd', 'custom'
ADD COLUMN IF NOT EXISTS has_white_label BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS trial_duration_days INT DEFAULT 14,
ADD COLUMN IF NOT EXISTS grace_period_days INT DEFAULT 3;

-- Add soft limit thresholds (percentage)
ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS soft_limit_threshold DECIMAL(3,2) DEFAULT 0.80; -- Warn at 80%

-- Update Trial plan - FULL PRO FEATURES FOR 7 DAYS
UPDATE subscription_plans SET
    product_limit = 500,                -- Same as Pro
    storage_limit_gb = 100,             -- Same as Pro
    project_limit = NULL,               -- Unlimited like Pro
    team_member_limit = 10,             -- Same as Pro
    trial_duration_days = 7,            -- 7-day trial
    grace_period_days = 3,
    soft_limit_threshold = 0.90,        -- Same as Pro
    scan_quality = 'hd',                -- HD scans like Pro
    has_webhook_access = true,          -- Webhooks enabled
    has_api_access = true,              -- API access enabled
    has_autocad_export = true,          -- AutoCAD export enabled
    has_priority_support = true         -- Priority support during trial
WHERE slug = 'trial';

UPDATE subscription_plans SET
    product_limit = 100,
    storage_limit_gb = 10,
    project_limit = 25,
    team_member_limit = 3,
    price_monthly = 99.00,
    price_yearly = 990.00,
    soft_limit_threshold = 0.80
WHERE slug = 'basic';

UPDATE subscription_plans SET
    product_limit = 500,
    storage_limit_gb = 100,
    project_limit = NULL, -- Unlimited
    team_member_limit = 10,
    price_monthly = 249.00,
    price_yearly = 2490.00,
    scan_quality = 'hd',
    soft_limit_threshold = 0.90
WHERE slug = 'pro';

UPDATE subscription_plans SET
    product_limit = NULL, -- Unlimited
    storage_limit_gb = NULL, -- Unlimited
    project_limit = NULL,
    team_member_limit = NULL,
    scan_quality = 'hd',
    has_white_label = true,
    soft_limit_threshold = 0.95
WHERE slug = 'enterprise';
```

### 4.2 Migration: Add Usage Tracking to Showrooms

```sql
-- ============================================
-- Migration: 017_showroom_usage_tracking
-- ============================================

-- Add comprehensive usage tracking
ALTER TABLE showrooms
ADD COLUMN IF NOT EXISTS product_count INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS storage_used_bytes BIGINT DEFAULT 0,
ADD COLUMN IF NOT EXISTS team_member_count INT DEFAULT 1,
ADD COLUMN IF NOT EXISTS period_start_date DATE,
ADD COLUMN IF NOT EXISTS grace_period_ends_at TIMESTAMPTZ;

-- Create usage tracking table for historical data
CREATE TABLE IF NOT EXISTS usage_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    -- Snapshot date
    snapshot_date DATE NOT NULL,

    -- Usage metrics
    project_count INT NOT NULL DEFAULT 0,
    product_count INT NOT NULL DEFAULT 0,
    storage_bytes BIGINT NOT NULL DEFAULT 0,
    team_member_count INT NOT NULL DEFAULT 0,

    -- Computed from plan
    project_limit INT,
    product_limit INT,
    storage_limit_gb INT,
    team_member_limit INT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT usage_snapshots_unique UNIQUE (showroom_id, snapshot_date)
);

-- Index for fast lookups
CREATE INDEX idx_usage_snapshots_showroom_date
ON usage_snapshots(showroom_id, snapshot_date DESC);

-- RLS
ALTER TABLE usage_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Showroom users can view their usage"
    ON usage_snapshots FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "Super admins can manage all usage"
    ON usage_snapshots FOR ALL
    USING (is_super_admin());
```

### 4.3 Migration: Create Feature Access Log

```sql
-- ============================================
-- Migration: 018_feature_access_log
-- ============================================

-- Log when features are accessed (for analytics)
CREATE TABLE IF NOT EXISTS feature_access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    showroom_id UUID NOT NULL REFERENCES showrooms(id) ON DELETE CASCADE,

    feature_name TEXT NOT NULL,
    was_allowed BOOLEAN NOT NULL,
    denial_reason TEXT, -- 'limit_reached', 'feature_not_available', 'subscription_expired'

    -- Context
    user_id UUID REFERENCES auth.users(id),
    request_path TEXT,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partition by month for performance
CREATE INDEX idx_feature_access_log_showroom
ON feature_access_log(showroom_id, created_at DESC);

CREATE INDEX idx_feature_access_log_feature
ON feature_access_log(feature_name, created_at DESC);

-- Auto-cleanup old logs (keep 90 days)
CREATE OR REPLACE FUNCTION cleanup_old_feature_logs()
RETURNS void AS $$
BEGIN
    DELETE FROM feature_access_log
    WHERE created_at < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql;

-- RLS
ALTER TABLE feature_access_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Showroom users can view their logs"
    ON feature_access_log FOR SELECT
    USING (has_showroom_access(showroom_id));

CREATE POLICY "System can insert logs"
    ON feature_access_log FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Super admins can manage all logs"
    ON feature_access_log FOR ALL
    USING (is_super_admin());
```

### 4.4 Enhanced Helper Functions

```sql
-- ============================================
-- Migration: 019_enhanced_limit_functions
-- ============================================

-- Check any limit with soft/hard distinction
CREATE OR REPLACE FUNCTION check_limit(
    p_showroom_id UUID,
    p_limit_type TEXT -- 'projects', 'products', 'storage', 'team_members'
)
RETURNS JSONB AS $$
DECLARE
    v_plan subscription_plans;
    v_showroom showrooms;
    v_limit INT;
    v_current INT;
    v_soft_threshold DECIMAL;
    v_percentage DECIMAL;
BEGIN
    -- Get showroom and plan
    SELECT s.*, sp.* INTO v_showroom
    FROM showrooms s
    LEFT JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    SELECT sp.* INTO v_plan
    FROM subscription_plans sp
    WHERE sp.id = v_showroom.subscription_plan_id;

    -- Get limit and current usage based on type
    CASE p_limit_type
        WHEN 'projects' THEN
            v_limit := v_plan.project_limit;
            v_current := v_showroom.project_count_this_period;
        WHEN 'products' THEN
            v_limit := v_plan.product_limit;
            v_current := v_showroom.product_count;
        WHEN 'storage' THEN
            v_limit := v_plan.storage_limit_gb * 1024 * 1024 * 1024; -- Convert to bytes
            v_current := v_showroom.storage_used_bytes;
        WHEN 'team_members' THEN
            v_limit := v_plan.team_member_limit;
            v_current := v_showroom.team_member_count;
        ELSE
            RETURN jsonb_build_object('error', 'Invalid limit type');
    END CASE;

    -- NULL limit means unlimited
    IF v_limit IS NULL THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'unlimited', true,
            'current', v_current,
            'limit', null,
            'percentage', 0,
            'warning', false
        );
    END IF;

    v_soft_threshold := COALESCE(v_plan.soft_limit_threshold, 0.80);
    v_percentage := v_current::DECIMAL / v_limit::DECIMAL;

    RETURN jsonb_build_object(
        'allowed', v_current < v_limit,
        'unlimited', false,
        'current', v_current,
        'limit', v_limit,
        'remaining', GREATEST(0, v_limit - v_current),
        'percentage', ROUND(v_percentage * 100, 1),
        'warning', v_percentage >= v_soft_threshold AND v_current < v_limit,
        'exceeded', v_current >= v_limit
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check subscription status with grace period
CREATE OR REPLACE FUNCTION check_subscription_access(p_showroom_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_showroom showrooms;
    v_plan subscription_plans;
    v_now TIMESTAMPTZ := NOW();
    v_status TEXT;
    v_has_access BOOLEAN;
    v_reason TEXT;
BEGIN
    SELECT s.*, sp.*
    INTO v_showroom
    FROM showrooms s
    LEFT JOIN subscription_plans sp ON s.subscription_plan_id = sp.id
    WHERE s.id = p_showroom_id;

    SELECT sp.* INTO v_plan
    FROM subscription_plans sp
    WHERE sp.id = v_showroom.subscription_plan_id;

    v_status := v_showroom.subscription_status;

    -- Check various conditions
    CASE v_status
        WHEN 'active' THEN
            v_has_access := true;
            v_reason := null;
        WHEN 'trial' THEN
            IF v_showroom.trial_ends_at IS NOT NULL AND v_now > v_showroom.trial_ends_at THEN
                -- Check grace period
                IF v_showroom.grace_period_ends_at IS NOT NULL AND v_now <= v_showroom.grace_period_ends_at THEN
                    v_has_access := true;
                    v_reason := 'trial_grace_period';
                ELSE
                    v_has_access := false;
                    v_reason := 'trial_expired';
                END IF;
            ELSE
                v_has_access := true;
                v_reason := null;
            END IF;
        WHEN 'past_due' THEN
            -- Allow access during past_due with warning
            IF v_showroom.grace_period_ends_at IS NOT NULL AND v_now <= v_showroom.grace_period_ends_at THEN
                v_has_access := true;
                v_reason := 'payment_grace_period';
            ELSE
                v_has_access := false;
                v_reason := 'payment_overdue';
            END IF;
        WHEN 'canceled' THEN
            -- Access until period end
            IF v_showroom.current_period_end IS NOT NULL AND v_now <= v_showroom.current_period_end THEN
                v_has_access := true;
                v_reason := 'cancellation_pending';
            ELSE
                v_has_access := false;
                v_reason := 'subscription_canceled';
            END IF;
        WHEN 'suspended' THEN
            v_has_access := false;
            v_reason := 'subscription_suspended';
        ELSE
            v_has_access := false;
            v_reason := 'unknown_status';
    END CASE;

    RETURN jsonb_build_object(
        'has_access', v_has_access,
        'status', v_status,
        'reason', v_reason,
        'plan', v_showroom.subscription_plan,
        'trial_ends_at', v_showroom.trial_ends_at,
        'current_period_end', v_showroom.current_period_end,
        'grace_period_ends_at', v_showroom.grace_period_ends_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update product count
CREATE OR REPLACE FUNCTION update_product_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE showrooms
        SET product_count = COALESCE(product_count, 0) + 1
        WHERE id = NEW.showroom_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE showrooms
        SET product_count = GREATEST(0, COALESCE(product_count, 0) - 1)
        WHERE id = OLD.showroom_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_product_count_insert ON products;
DROP TRIGGER IF EXISTS trigger_update_product_count_delete ON products;

CREATE TRIGGER trigger_update_product_count_insert
    AFTER INSERT ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_product_count();

CREATE TRIGGER trigger_update_product_count_delete
    AFTER DELETE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_product_count();

-- Trigger to update team member count
CREATE OR REPLACE FUNCTION update_team_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE showrooms
        SET team_member_count = COALESCE(team_member_count, 0) + 1
        WHERE id = NEW.showroom_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE showrooms
        SET team_member_count = GREATEST(1, COALESCE(team_member_count, 0) - 1)
        WHERE id = OLD.showroom_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_team_member_count_insert ON showroom_users;
DROP TRIGGER IF EXISTS trigger_update_team_member_count_delete ON showroom_users;

CREATE TRIGGER trigger_update_team_member_count_insert
    AFTER INSERT ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION update_team_member_count();

CREATE TRIGGER trigger_update_team_member_count_delete
    AFTER DELETE ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION update_team_member_count();
```

### 4.5 RLS Policy Updates

```sql
-- ============================================
-- Migration: 020_subscription_rls_policies
-- ============================================

-- Products: Enforce product limit on insert
CREATE OR REPLACE FUNCTION check_product_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
BEGIN
    v_result := check_limit(NEW.showroom_id, 'products');

    IF NOT (v_result->>'allowed')::BOOLEAN THEN
        RAISE EXCEPTION 'Product limit reached. Please upgrade your plan to add more products.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_check_product_insert ON products;
CREATE TRIGGER trigger_check_product_insert
    BEFORE INSERT ON products
    FOR EACH ROW
    EXECUTE FUNCTION check_product_insert();

-- Team members: Enforce limit on insert
CREATE OR REPLACE FUNCTION check_team_member_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_result JSONB;
BEGIN
    v_result := check_limit(NEW.showroom_id, 'team_members');

    IF NOT (v_result->>'allowed')::BOOLEAN THEN
        RAISE EXCEPTION 'Team member limit reached. Please upgrade your plan to add more team members.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_check_team_member_insert ON showroom_users;
CREATE TRIGGER trigger_check_team_member_insert
    BEFORE INSERT ON showroom_users
    FOR EACH ROW
    EXECUTE FUNCTION check_team_member_insert();

-- Projects: Already has trigger, but enhance it
CREATE OR REPLACE FUNCTION check_project_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_limit_result JSONB;
    v_access_result JSONB;
BEGIN
    -- Check subscription access first
    v_access_result := check_subscription_access(NEW.showroom_id);

    IF NOT (v_access_result->>'has_access')::BOOLEAN THEN
        RAISE EXCEPTION 'Subscription issue: %. Please update your subscription.',
            v_access_result->>'reason';
    END IF;

    -- Check project limit
    v_limit_result := check_limit(NEW.showroom_id, 'projects');

    IF NOT (v_limit_result->>'allowed')::BOOLEAN THEN
        RAISE EXCEPTION 'Project limit reached (% of %). Please upgrade your plan.',
            v_limit_result->>'current',
            v_limit_result->>'limit';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Replace existing project trigger
DROP TRIGGER IF EXISTS trigger_check_project_insert ON projects;
CREATE TRIGGER trigger_check_project_insert
    BEFORE INSERT ON projects
    FOR EACH ROW
    EXECUTE FUNCTION check_project_insert();
```

---

## 5. Feature Gating Strategy

### 5.1 Multi-Layer Enforcement Model

```
+------------------+     +------------------+     +------------------+
|    UI Layer      | --> | Edge Function    | --> |    Database      |
|  (Soft Blocks)   |     | (Hard Blocks)    |     | (RLS Triggers)   |
+------------------+     +------------------+     +------------------+
        |                        |                        |
   - Hide features          - Validate limits        - Final enforcement
   - Show warnings          - Return errors          - Audit logging
   - Upgrade prompts        - Log attempts           - Usage updates
```

### 5.2 Feature Categories

#### Boolean Features (Has/Doesn't Have)
- `webhook_access` - Webhook integration
- `api_access` - REST API access
- `autocad_export` - Export to AutoCAD
- `priority_support` - Priority support queue
- `crm_integration` - CRM connectors
- `ai_agent` - AI processing features
- `has_white_label` - Remove NextLean branding

**Enforcement:**
- UI: Hide feature in sidebar/settings
- Edge Function: Return 403 with upgrade prompt
- Database: N/A (no data to protect)

#### Numeric Limits
- `project_limit` - Projects per billing period
- `product_limit` - Total active products
- `storage_limit_gb` - Storage usage
- `team_member_limit` - Team members

**Enforcement:**
- UI: Show usage bars, warnings at threshold
- Edge Function: Block creation, return limit info
- Database: Triggers prevent inserts

### 5.3 Soft vs Hard Limits

| Threshold | Action |
|-----------|--------|
| 0-79% | Normal operation |
| 80-99% | **Soft Limit**: Show warning banner, allow action |
| 100% | **Hard Limit**: Block action, show upgrade modal |
| 100%+ (existing data) | **Grace**: Allow read, block write |

---

## 6. Frontend Implementation

### 6.1 Subscription Context Provider

**File: `dashboard/src/contexts/subscription-context.tsx`**

```typescript
// This should be created to provide subscription state app-wide

import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { createClient } from '@/lib/supabase/client'
import {
  SubscriptionPlan,
  SubscriptionStatus,
  PlanFeatures,
  getPlanFeatures
} from '@/lib/subscription'

interface UsageMetrics {
  projects: { current: number; limit: number | null; percentage: number; warning: boolean }
  products: { current: number; limit: number | null; percentage: number; warning: boolean }
  storage: { current: number; limit: number | null; percentage: number; warning: boolean }
  teamMembers: { current: number; limit: number | null; percentage: number; warning: boolean }
}

interface SubscriptionContextType {
  // State
  loading: boolean
  plan: SubscriptionPlan | null
  status: SubscriptionStatus
  features: PlanFeatures
  usage: UsageMetrics

  // Computed
  isActive: boolean
  isTrialExpired: boolean
  trialDaysRemaining: number | null
  inGracePeriod: boolean

  // Methods
  refreshSubscription: () => Promise<void>
  canUseFeature: (feature: keyof PlanFeatures) => boolean
  canAddMore: (resource: keyof UsageMetrics) => boolean
  getUpgradeReason: (feature: keyof PlanFeatures) => string
}

const SubscriptionContext = createContext<SubscriptionContextType | null>(null)

export function SubscriptionProvider({
  children,
  showroomId
}: {
  children: ReactNode
  showroomId: string
}) {
  // Implementation here - fetches from DB, provides to children
}

export function useSubscription() {
  const context = useContext(SubscriptionContext)
  if (!context) {
    throw new Error('useSubscription must be used within SubscriptionProvider')
  }
  return context
}
```

### 6.2 Feature Gate Component

**File: `dashboard/src/components/subscription/feature-gate.tsx`**

```typescript
// Wraps features that require specific plans

interface FeatureGateProps {
  feature: keyof PlanFeatures
  children: ReactNode
  fallback?: ReactNode // What to show if not allowed
  showUpgrade?: boolean // Show upgrade prompt
}

export function FeatureGate({
  feature,
  children,
  fallback,
  showUpgrade = true
}: FeatureGateProps) {
  const { canUseFeature, getUpgradeReason } = useSubscription()

  if (canUseFeature(feature)) {
    return <>{children}</>
  }

  if (fallback) {
    return <>{fallback}</>
  }

  if (showUpgrade) {
    return <UpgradePrompt reason={getUpgradeReason(feature)} feature={feature} />
  }

  return null
}
```

### 6.3 Usage Warning Banner

**File: `dashboard/src/components/subscription/usage-warning.tsx`**

```typescript
// Shows when approaching limits

export function UsageWarningBanner() {
  const { usage, plan } = useSubscription()

  const warnings = Object.entries(usage)
    .filter(([, data]) => data.warning)
    .map(([key, data]) => ({
      resource: key,
      percentage: data.percentage,
      remaining: data.limit ? data.limit - data.current : null
    }))

  if (warnings.length === 0) return null

  return (
    <div className="bg-yellow-50 border-b border-yellow-200 px-4 py-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-yellow-600" />
          <span className="text-sm text-yellow-800">
            You're approaching your {warnings[0].resource} limit
            ({warnings[0].percentage}% used)
          </span>
        </div>
        <Button variant="outline" size="sm" asChild>
          <Link href="/showroom/billing">Upgrade Plan</Link>
        </Button>
      </div>
    </div>
  )
}
```

### 6.4 Upgrade Modal

**File: `dashboard/src/components/subscription/upgrade-modal.tsx`**

```typescript
// Shown when user tries to use a feature they don't have access to

interface UpgradeModalProps {
  isOpen: boolean
  onClose: () => void
  feature: keyof PlanFeatures
  currentPlan: SubscriptionPlan | null
}

export function UpgradeModal({
  isOpen,
  onClose,
  feature,
  currentPlan
}: UpgradeModalProps) {
  const requiredPlan = getRequiredPlanForFeature(feature)

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Upgrade Required</DialogTitle>
          <DialogDescription>
            {featureNames[feature]} requires the {requiredPlan} plan or higher.
          </DialogDescription>
        </DialogHeader>

        {/* Plan comparison */}
        <PlanComparison
          currentPlan={currentPlan}
          targetPlan={requiredPlan}
          highlightFeature={feature}
        />

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Maybe Later
          </Button>
          <Button asChild>
            <Link href={`/showroom/billing?upgrade=${requiredPlan}`}>
              Upgrade to {requiredPlan}
            </Link>
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
```

### 6.5 Protected Navigation Items

**File: Update `dashboard/src/components/shared/sidebar.tsx`**

```typescript
// Wrap navigation items that require specific features

const showroomNavItems = [
  { name: 'Projects', href: '/showroom/projects', icon: FolderKanban },
  { name: 'Products', href: '/showroom/products', icon: Package },
  { name: 'Customers', href: '/showroom/customers', icon: Users },
  { name: 'Branding', href: '/showroom/branding', icon: Palette },
  {
    name: 'Webhooks',
    href: '/showroom/webhooks',
    icon: Webhook,
    requiredFeature: 'webhookAccess' as const // Gate this
  },
  {
    name: 'API',
    href: '/showroom/api',
    icon: Code,
    requiredFeature: 'apiAccess' as const
  },
  { name: 'Settings', href: '/showroom/settings', icon: Settings },
  { name: 'Billing', href: '/showroom/billing', icon: CreditCard },
]

// In render:
{showroomNavItems.map((item) => {
  if (item.requiredFeature && !subscription.canUseFeature(item.requiredFeature)) {
    return (
      <NavItem
        key={item.name}
        {...item}
        disabled
        badge={<Lock className="h-3 w-3" />}
        onClick={() => setUpgradeModalFeature(item.requiredFeature)}
      />
    )
  }
  return <NavItem key={item.name} {...item} />
})}
```

### 6.6 Layout Integration

**File: Update `dashboard/src/app/(dashboard)/layout.tsx`**

```typescript
// Wrap the layout with subscription provider

export default async function DashboardLayout({ children }) {
  // ... existing auth logic ...

  // Fetch subscription data
  const { data: showroom } = await supabase
    .from('showrooms')
    .select(`
      id,
      subscription_status,
      subscription_plan,
      subscription_plan_id,
      project_count_this_period,
      product_count,
      storage_used_bytes,
      team_member_count,
      trial_ends_at,
      current_period_end,
      grace_period_ends_at,
      subscription_plans(*)
    `)
    .eq('id', showroomUser.showroom_id)
    .single()

  return (
    <SubscriptionProvider
      showroomId={showroomUser.showroom_id}
      initialData={showroom}
    >
      <div className="min-h-screen bg-gray-50">
        <UsageWarningBanner />
        <Sidebar userInfo={userInfo} />
        <main className="lg:pl-64">
          <div className="p-6">{children}</div>
        </main>
      </div>
    </SubscriptionProvider>
  )
}
```

---

## 7. Backend Implementation

### 7.1 Edge Function: Feature Check Middleware

**File: `supabase/functions/_shared/subscription.ts`**

```typescript
import { supabaseAdmin } from './supabase.ts'

interface FeatureCheckResult {
  allowed: boolean
  reason?: string
  limit?: number
  current?: number
  plan?: string
  upgradeRequired?: string
}

export async function checkFeature(
  showroomId: string,
  feature: string
): Promise<FeatureCheckResult> {
  const { data, error } = await supabaseAdmin.rpc('check_plan_feature', {
    p_showroom_id: showroomId,
    p_feature: feature
  })

  if (error || !data) {
    return {
      allowed: false,
      reason: 'Unable to verify feature access'
    }
  }

  return { allowed: data }
}

export async function checkLimit(
  showroomId: string,
  limitType: 'projects' | 'products' | 'storage' | 'team_members'
): Promise<FeatureCheckResult> {
  const { data, error } = await supabaseAdmin.rpc('check_limit', {
    p_showroom_id: showroomId,
    p_limit_type: limitType
  })

  if (error) {
    return {
      allowed: false,
      reason: 'Unable to verify limit'
    }
  }

  return {
    allowed: data.allowed,
    reason: data.exceeded ? 'limit_reached' : undefined,
    limit: data.limit,
    current: data.current,
    upgradeRequired: data.exceeded ? 'pro' : undefined
  }
}

export async function checkSubscriptionAccess(
  showroomId: string
): Promise<{ hasAccess: boolean; reason?: string; status: string }> {
  const { data, error } = await supabaseAdmin.rpc('check_subscription_access', {
    p_showroom_id: showroomId
  })

  if (error) {
    return {
      hasAccess: false,
      reason: 'verification_failed',
      status: 'unknown'
    }
  }

  return {
    hasAccess: data.has_access,
    reason: data.reason,
    status: data.status
  }
}

// Log feature access for analytics
export async function logFeatureAccess(
  showroomId: string,
  featureName: string,
  wasAllowed: boolean,
  denialReason?: string,
  userId?: string,
  requestPath?: string
): Promise<void> {
  await supabaseAdmin.from('feature_access_log').insert({
    showroom_id: showroomId,
    feature_name: featureName,
    was_allowed: wasAllowed,
    denial_reason: denialReason,
    user_id: userId,
    request_path: requestPath
  })
}
```

### 7.2 Updated submit-project Function

**File: `supabase/functions/submit-project/index.ts`**

Add at the beginning of the request handler:

```typescript
// After validating showroom exists:

// Check subscription access
const accessCheck = await checkSubscriptionAccess(submission.showroom_id)
if (!accessCheck.hasAccess) {
  await logFeatureAccess(
    submission.showroom_id,
    'project_submission',
    false,
    accessCheck.reason
  )

  return new Response(
    JSON.stringify({
      error: 'Subscription issue',
      reason: accessCheck.reason,
      message: getSubscriptionErrorMessage(accessCheck.reason)
    }),
    { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

// Check project limit
const limitCheck = await checkLimit(submission.showroom_id, 'projects')
if (!limitCheck.allowed) {
  await logFeatureAccess(
    submission.showroom_id,
    'project_submission',
    false,
    'project_limit_reached'
  )

  return new Response(
    JSON.stringify({
      error: 'Project limit reached',
      current: limitCheck.current,
      limit: limitCheck.limit,
      message: `You have reached your project limit (${limitCheck.current}/${limitCheck.limit}). Please upgrade your plan to continue.`
    }),
    { status: 402, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

// Check webhook feature before calling
if (showroom.webhook_url) {
  const webhookCheck = await checkFeature(submission.showroom_id, 'webhook_access')
  if (!webhookCheck.allowed) {
    // Don't call webhook, but don't fail the submission
    console.log(`Webhook configured but feature not available for showroom ${submission.showroom_id}`)
  } else {
    // Call webhook as before
  }
}
```

### 7.3 iOS Config Response Enhancement

**File: Update `supabase/functions/get-showroom-config/index.ts`**

Include subscription limits in config response:

```typescript
// Add to the response:
const { data: subscriptionLimits } = await supabaseAdmin.rpc('check_limit', {
  p_showroom_id: showroom.id,
  p_limit_type: 'projects'
})

return new Response(
  JSON.stringify({
    showroom: {
      id: showroom.id,
      name: showroom.name,
      // ... existing fields ...
    },
    branding: { /* ... */ },
    categories: [ /* ... */ ],
    products: { /* ... */ },

    // NEW: Subscription info for iOS app
    subscription: {
      status: showroom.subscription_status,
      plan: showroom.subscription_plan,
      projects: {
        current: subscriptionLimits?.current || 0,
        limit: subscriptionLimits?.limit,
        remaining: subscriptionLimits?.remaining,
        canSubmit: subscriptionLimits?.allowed
      },
      // Message to show if can't submit
      limitMessage: !subscriptionLimits?.allowed
        ? 'This showroom has reached its project limit. Please contact the showroom.'
        : null
    }
  }),
  { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
)
```

---

## 8. Upgrade/Downgrade Flows

### 8.1 Upgrade Flow

```
User clicks "Upgrade" --> Billing Page --> Stripe Checkout --> Webhook --> Database Update
                              |
                              v
                      Show plan comparison
                      Highlight new features
                      Calculate pro-rated cost
```

**Immediate Effects:**
1. New limits take effect instantly
2. All locked features become available
3. Trial banner disappears
4. Usage counters reset (for projects, which are per-period)

### 8.2 Downgrade Flow

```
User requests downgrade --> Confirmation Modal --> Stripe Update --> Scheduled for Period End
                                  |
                                  v
                           Show what will be lost:
                           - Features being removed
                           - Data over new limits
                           - Warning about locked content
```

**Deferred Effects (at period end):**
1. New limits apply
2. Excess data becomes read-only
3. Features locked with upgrade prompts

### 8.3 Downgrade Data Handling

When downgrading causes data to exceed limits:

```typescript
// Example: User has 150 products, downgrades to Basic (100 limit)
// Products 101-150 are NOT deleted, but:
// 1. Cannot add new products
// 2. Can edit existing products
// 3. All products remain visible
// 4. Must delete 50+ products to add new ones

// UI shows:
"You have 150 products but your plan allows 100.
Delete 50 products to add new ones, or upgrade your plan."
```

### 8.4 Grace Period Handling

```
Status: past_due
    |
    v
Grace Period (3 days)
    - Show warning banner
    - Allow all features
    - Send reminder emails (Day 1, 2, 3)
    |
    v
Grace Period Expires
    - Status: suspended
    - Read-only mode
    - Prominent upgrade prompt
    - No new submissions
```

---

## 9. Usage Tracking & Warnings

### 9.1 Real-Time Usage Updates

Track these metrics in real-time:

| Metric | Trigger | Update Method |
|--------|---------|---------------|
| Projects | Project submission | Database trigger |
| Products | Product CRUD | Database trigger |
| Storage | File upload/delete | Edge function |
| Team Members | Invitation accept/remove | Database trigger |

### 9.2 Period Reset

```sql
-- Daily job to reset period-based counters
CREATE OR REPLACE FUNCTION reset_period_counters()
RETURNS void AS $$
BEGIN
    UPDATE showrooms
    SET project_count_this_period = 0,
        period_start_date = CURRENT_DATE
    WHERE
        subscription_status = 'active'
        AND current_period_end < NOW()
        AND period_start_date < CURRENT_DATE - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
```

### 9.3 Warning Thresholds

| Usage % | Action |
|---------|--------|
| 50% | No action |
| 75% | Internal logging |
| 80% | Yellow banner in dashboard |
| 90% | Email notification to showroom owner |
| 95% | Orange banner, prominent upgrade CTA |
| 100% | Red banner, block new items, show upgrade modal |

### 9.4 Email Notifications

Send automated emails for:

1. **Trial ending soon** (3 days before)
2. **Usage approaching limit** (80%, 90%)
3. **Payment failed** (immediately, then daily)
4. **Subscription downgrade scheduled**
5. **Grace period ending** (1 day before)

---

## 10. Implementation Order

### Phase 1: Database Foundation (Week 1)

1. **Migration 016**: Update subscription_plans with new limits
2. **Migration 017**: Add usage tracking columns to showrooms
3. **Migration 018**: Create feature_access_log table
4. **Migration 019**: Enhanced helper functions
5. **Migration 020**: RLS and trigger updates
6. Verify existing data integrity

### Phase 2: Backend Enforcement (Week 2)

1. Create shared subscription utilities for Edge Functions
2. Update submit-project with limit checks
3. Update get-showroom-config with subscription info
4. Add feature logging to all protected endpoints
5. Implement storage tracking
6. Test all limits via API

### Phase 3: Frontend Components (Week 2-3)

1. Create SubscriptionContext provider
2. Implement FeatureGate component
3. Build UsageWarningBanner
4. Create UpgradeModal
5. Update Sidebar with protected items
6. Add usage display to Settings page

### Phase 4: Integration & Polish (Week 3)

1. Integrate provider in dashboard layout
2. Add upgrade prompts throughout app
3. Implement email notifications
4. Add real-time usage updates
5. Handle downgrade edge cases
6. Comprehensive testing

### Phase 5: iOS Updates (Week 4)

1. Parse subscription info from config response
2. Show limit warnings before submission
3. Handle submission errors gracefully
4. Display showroom subscription status
5. Test offline/online scenarios

---

## Appendix A: Component File Structure

```
dashboard/src/
├── contexts/
│   └── subscription-context.tsx
├── components/
│   └── subscription/
│       ├── index.ts
│       ├── feature-gate.tsx
│       ├── usage-warning.tsx
│       ├── upgrade-modal.tsx
│       ├── plan-comparison.tsx
│       ├── usage-meter.tsx
│       └── subscription-badge.tsx
├── hooks/
│   └── use-subscription.ts (re-export from context)
└── lib/
    └── subscription.ts (existing, will be updated)
```

---

## Appendix B: Error Messages

```typescript
const subscriptionErrorMessages = {
  trial_expired: 'Your trial has expired. Subscribe to continue using NextLean Scan.',
  trial_grace_period: 'Your trial has expired but you have a grace period. Subscribe now to avoid interruption.',
  payment_grace_period: 'Your payment is overdue. Please update your payment method.',
  payment_overdue: 'Your subscription has been suspended due to non-payment.',
  subscription_canceled: 'Your subscription has been canceled.',
  subscription_suspended: 'Your account has been suspended. Contact support for assistance.',
  project_limit_reached: 'You have reached your project limit for this period.',
  product_limit_reached: 'You have reached your product limit. Upgrade to add more.',
  storage_limit_reached: 'You have reached your storage limit. Upgrade for more space.',
  team_member_limit_reached: 'You have reached your team member limit.',
  feature_not_available: 'This feature is not available on your current plan.',
}
```

---

## Appendix C: Analytics Events

Track these events for business intelligence:

```typescript
// Feature access
'subscription.feature_accessed' // Feature used successfully
'subscription.feature_blocked' // Feature blocked due to plan
'subscription.limit_warning' // User saw limit warning
'subscription.limit_reached' // User hit a hard limit

// Conversion
'subscription.upgrade_prompt_shown' // Upgrade modal displayed
'subscription.upgrade_clicked' // User clicked upgrade
'subscription.upgrade_completed' // Stripe checkout completed
'subscription.downgrade_started' // User initiated downgrade

// Lifecycle
'subscription.trial_started'
'subscription.trial_expiring' // 3 days left
'subscription.trial_expired'
'subscription.grace_period_started'
'subscription.grace_period_ended'
```

---

*Document prepared by NextLean Architect Agent*
