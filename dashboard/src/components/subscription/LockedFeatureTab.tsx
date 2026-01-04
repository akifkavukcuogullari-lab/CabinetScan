'use client'

import { TabsTrigger } from '@/components/ui/tabs'
import { Lock } from 'lucide-react'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import { PlanFeatures, featureNames, getRequiredPlanForFeature } from '@/lib/subscription'

interface LockedFeatureTabProps {
  feature: keyof PlanFeatures
  value: string
  isLocked: boolean
  children: React.ReactNode
  className?: string
}

export function LockedFeatureTab({
  feature,
  value,
  isLocked,
  children,
  className = ''
}: LockedFeatureTabProps) {
  const featureName = featureNames[feature]
  const requiredPlan = getRequiredPlanForFeature(feature)

  if (!isLocked) {
    return (
      <TabsTrigger value={value} className={className}>
        {children}
      </TabsTrigger>
    )
  }

  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <TabsTrigger
            value={value}
            className={`${className} opacity-50 cursor-not-allowed`}
            disabled
          >
            {children}
            <Lock className="h-3 w-3 ml-1" />
          </TabsTrigger>
        </TooltipTrigger>
        <TooltipContent>
          <p className="text-xs">
            {featureName} requires {requiredPlan?.toUpperCase()} plan
          </p>
          <p className="text-xs text-gray-400 mt-1">
            Click to upgrade
          </p>
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  )
}
