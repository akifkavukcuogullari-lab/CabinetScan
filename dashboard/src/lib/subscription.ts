/**
 * Subscription feature gating utilities
 */

export type SubscriptionPlan = 'trial' | 'starter' | 'pro' | 'business' | 'enterprise'
export type SubscriptionStatus = 'trial' | 'active' | 'past_due' | 'canceled' | 'suspended'

export interface SubscriptionInfo {
  plan: SubscriptionPlan | null
  status: SubscriptionStatus
  projectLimit: number | null
  projectsUsed: number
  trialEndsAt: Date | null
  periodEnd: Date | null
  cancelAtPeriodEnd: boolean
}

export interface PlanFeatures {
  projectLimit: number | null
  productLimit: number | null
  storageGb: number | null
  teamMembers: number | null
  retentionDays: number | null
  webhookAccess: boolean
  apiAccess: boolean
  autocadExport: boolean
  prioritySupport: boolean
  crmIntegration: boolean
  aiAgent: boolean
  customBranding: boolean
  productSelection: boolean
  emailToCustomer: boolean
  photosVideo: boolean
}

// Plan feature definitions
const planFeatures: Record<SubscriptionPlan, PlanFeatures> = {
  trial: {
    // Trial gets Pro-level features to showcase full value
    projectLimit: 100,
    productLimit: 100,
    storageGb: 50,
    teamMembers: 3,
    retentionDays: 60,
    webhookAccess: false,
    apiAccess: false,
    autocadExport: true,
    prioritySupport: true,
    crmIntegration: false,
    aiAgent: false,
    customBranding: true,
    productSelection: true,
    emailToCustomer: false,
    photosVideo: true,
  },
  starter: {
    projectLimit: 20,
    productLimit: null, // No products for Starter
    storageGb: 5,
    teamMembers: 1,
    retentionDays: 30,
    webhookAccess: false,
    apiAccess: false,
    autocadExport: false,
    prioritySupport: false,
    crmIntegration: false,
    aiAgent: false,
    customBranding: false, // White-labeling is Pro+ only
    productSelection: false, // Scan-only, no product selection
    emailToCustomer: false,
    photosVideo: true,
  },
  pro: {
    projectLimit: 100,
    productLimit: 100,
    storageGb: 50,
    teamMembers: 3,
    retentionDays: 60,
    webhookAccess: false,
    apiAccess: false,
    autocadExport: true,
    prioritySupport: true,
    crmIntegration: false,
    aiAgent: false,
    customBranding: true,
    productSelection: true,
    emailToCustomer: false,
    photosVideo: true,
  },
  business: {
    projectLimit: null, // Unlimited
    productLimit: 300,
    storageGb: 100,
    teamMembers: 10,
    retentionDays: 90,
    webhookAccess: true,
    apiAccess: true,
    autocadExport: true,
    prioritySupport: true,
    crmIntegration: false,
    aiAgent: true,
    customBranding: true,
    productSelection: true,
    emailToCustomer: true,
    photosVideo: true,
  },
  enterprise: {
    projectLimit: null,
    productLimit: null, // Unlimited
    storageGb: null, // Unlimited
    teamMembers: null, // Unlimited
    retentionDays: null, // Never archived
    webhookAccess: true,
    apiAccess: true,
    autocadExport: true,
    prioritySupport: true,
    crmIntegration: true,
    aiAgent: true,
    customBranding: true,
    productSelection: true,
    emailToCustomer: true,
    photosVideo: true,
  },
}

/**
 * Get features for a specific plan
 * Trial users get Pro-level features dynamically
 */
export function getPlanFeatures(plan: SubscriptionPlan | null): PlanFeatures {
  // Trial users get Pro features to experience full value
  if (plan === 'trial' || plan === null) {
    return planFeatures['pro']
  }
  return planFeatures[plan]
}

/**
 * Check if user has access to a specific feature
 */
export function hasFeature(
  plan: SubscriptionPlan | null,
  feature: keyof PlanFeatures
): boolean {
  const features = getPlanFeatures(plan)
  const value = features[feature]

  // Handle boolean features
  if (typeof value === 'boolean') {
    return value
  }

  // For null (unlimited) or number, return true
  return true
}

/**
 * Check if user can create more projects
 */
export function canCreateProject(
  plan: SubscriptionPlan | null,
  projectsUsed: number
): boolean {
  const features = getPlanFeatures(plan)

  // Unlimited projects
  if (features.projectLimit === null) {
    return true
  }

  return projectsUsed < features.projectLimit
}

/**
 * Get remaining projects count
 */
export function getRemainingProjects(
  plan: SubscriptionPlan | null,
  projectsUsed: number
): number | null {
  const features = getPlanFeatures(plan)

  // Unlimited
  if (features.projectLimit === null) {
    return null
  }

  return Math.max(0, features.projectLimit - projectsUsed)
}

/**
 * Check if subscription is active (can use features)
 */
export function isSubscriptionActive(status: SubscriptionStatus): boolean {
  return ['trial', 'active'].includes(status)
}

/**
 * Check if trial has expired
 */
export function isTrialExpired(
  status: SubscriptionStatus,
  trialEndsAt: Date | null
): boolean {
  if (status !== 'trial' || !trialEndsAt) {
    return false
  }

  return new Date() > trialEndsAt
}

/**
 * Get trial days remaining
 */
export function getTrialDaysRemaining(trialEndsAt: Date | null): number {
  if (!trialEndsAt) return 0

  const now = new Date()
  const endDate = new Date(trialEndsAt)
  const diffTime = endDate.getTime() - now.getTime()

  return Math.max(0, Math.ceil(diffTime / (1000 * 60 * 60 * 24)))
}

/**
 * Feature names for display
 */
export const featureNames: Record<keyof PlanFeatures, string> = {
  projectLimit: 'Projects per month',
  productLimit: 'Products',
  storageGb: 'Storage',
  teamMembers: 'Team members',
  retentionDays: 'Project retention',
  webhookAccess: 'Webhooks',
  apiAccess: 'API access',
  autocadExport: 'AutoCAD export',
  prioritySupport: 'Priority support',
  crmIntegration: 'CRM integration',
  aiAgent: 'AI-generated quotes',
  customBranding: 'Custom branding',
  productSelection: 'Product selection',
  emailToCustomer: 'Email to customer',
  photosVideo: 'Photos & video',
}

/**
 * Determine which plan is needed for a feature
 */
export function getRequiredPlanForFeature(
  feature: keyof PlanFeatures
): SubscriptionPlan | null {
  // Check paid plans only (skip trial)
  const plansInOrder: SubscriptionPlan[] = ['starter', 'pro', 'business', 'enterprise']

  for (const plan of plansInOrder) {
    if (hasFeature(plan, feature)) {
      return plan
    }
  }

  return 'enterprise'
}

/**
 * Create subscription info object from showroom data
 */
export function createSubscriptionInfo(showroom: {
  subscription_status: string
  subscription_plan: string | null
  project_count_this_period: number
  trial_ends_at: string | null
  current_period_end: string | null
  cancel_at_period_end: boolean
}): SubscriptionInfo {
  const features = getPlanFeatures(showroom.subscription_plan as SubscriptionPlan | null)

  return {
    plan: (showroom.subscription_plan as SubscriptionPlan) || null,
    status: showroom.subscription_status as SubscriptionStatus,
    projectLimit: features.projectLimit,
    projectsUsed: showroom.project_count_this_period || 0,
    trialEndsAt: showroom.trial_ends_at ? new Date(showroom.trial_ends_at) : null,
    periodEnd: showroom.current_period_end
      ? new Date(showroom.current_period_end)
      : null,
    cancelAtPeriodEnd: showroom.cancel_at_period_end || false,
  }
}
