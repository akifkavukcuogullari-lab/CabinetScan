'use client'

import { useState } from 'react'
import Link from 'next/link'
import { Lock, ArrowUpRight } from 'lucide-react'
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from '@/components/ui/tooltip'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { PlanFeatures, featureNames, getRequiredPlanForFeature } from '@/lib/subscription'

interface LockedFeatureProps {
  feature: keyof PlanFeatures
  children: React.ReactNode
  isLocked: boolean
  className?: string
  showTooltip?: boolean
}

export function LockedFeature({
  feature,
  children,
  isLocked,
  className = '',
  showTooltip = true
}: LockedFeatureProps) {
  const [showUpgradeDialog, setShowUpgradeDialog] = useState(false)

  const featureName = featureNames[feature]
  const requiredPlan = getRequiredPlanForFeature(feature)

  if (!isLocked) {
    return <>{children}</>
  }

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setShowUpgradeDialog(true)
  }

  const content = (
    <div
      className={`relative ${className}`}
      onClick={handleClick}
    >
      {/* Grayed out children - visible but disabled */}
      <div className="opacity-50 pointer-events-none cursor-not-allowed">
        {children}
      </div>

      {/* Lock indicator - small badge in top-right */}
      <div className="absolute top-2 right-2 p-1.5 bg-white rounded-md shadow-sm border border-gray-300 cursor-pointer hover:shadow-md hover:scale-110 transition-all">
        <Lock className="h-3 w-3 text-gray-500" />
      </div>
    </div>
  )

  if (!showTooltip) {
    return (
      <>
        {content}
        <UpgradeDialog
          isOpen={showUpgradeDialog}
          onClose={() => setShowUpgradeDialog(false)}
          featureName={featureName}
          requiredPlan={requiredPlan}
        />
      </>
    )
  }

  return (
    <>
      <TooltipProvider>
        <Tooltip>
          <TooltipTrigger asChild>
            {content}
          </TooltipTrigger>
          <TooltipContent>
            <p className="text-xs">
              <Lock className="h-3 w-3 inline mr-1" />
              {featureName} requires {requiredPlan?.toUpperCase()} plan
            </p>
          </TooltipContent>
        </Tooltip>
      </TooltipProvider>

      <UpgradeDialog
        isOpen={showUpgradeDialog}
        onClose={() => setShowUpgradeDialog(false)}
        featureName={featureName}
        requiredPlan={requiredPlan}
      />
    </>
  )
}

interface UpgradeDialogProps {
  isOpen: boolean
  onClose: () => void
  featureName: string
  requiredPlan: string | null
}

function UpgradeDialog({
  isOpen,
  onClose,
  featureName,
  requiredPlan
}: UpgradeDialogProps) {
  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-sm p-6">
        <DialogHeader className="space-y-3">
          <div className="mx-auto p-2.5 bg-gradient-to-br from-purple-100 to-blue-100 rounded-full">
            <Lock className="h-5 w-5 text-purple-600" />
          </div>
          <DialogTitle className="text-center text-lg">Upgrade Required</DialogTitle>
          <DialogDescription className="text-center text-sm">
            <span className="font-medium text-gray-900">{featureName}</span> is a premium feature available on the{' '}
            <span className="font-semibold text-purple-600">{requiredPlan?.toUpperCase()}</span> plan and above.
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-2 mt-4">
          <Link href="/showroom/billing" onClick={onClose}>
            <Button className="w-full bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700" size="sm">
              Upgrade to {requiredPlan?.toUpperCase()}
              <ArrowUpRight className="h-3.5 w-3.5 ml-1.5" />
            </Button>
          </Link>
          <Button variant="ghost" onClick={onClose} className="w-full" size="sm">
            Maybe Later
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
