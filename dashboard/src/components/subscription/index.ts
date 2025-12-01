/**
 * Subscription components for feature gating and usage tracking.
 *
 * These components work with the SubscriptionContext to provide
 * subscription-based feature access and usage warnings.
 */

// Feature gating components
export {
  FeatureGate,
  FeatureBadge,
  RequireFeature,
  RequireActiveSubscription,
  LimitGate,
  UsageMeter,
} from './feature-gate'

// Upgrade modal and prompts
export {
  UpgradeModal,
  UpgradePrompt,
  UpgradeBanner,
} from './upgrade-modal'

// Usage warning banner
export { UsageWarningBanner } from './usage-warning-banner'

// Re-export context hooks for convenience
export {
  useSubscriptionContext,
  useSubscriptionContextOptional,
  SubscriptionProvider,
  type SubscriptionContextType,
  type UsageMetric,
  type UsageMetrics,
  type SubscriptionData,
  type PlanDetails,
} from '@/contexts/subscription-context'
