'use client'

import { useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet'
import { UpgradeModal } from '@/components/subscription/upgrade-modal'
import { useSubscriptionContextOptional } from '@/contexts/subscription-context'
import { PlanFeatures, SubscriptionPlan } from '@/lib/subscription'
import {
  Building2,
  LayoutGrid,
  Package,
  FolderKanban,
  Settings,
  Palette,
  LogOut,
  Menu,
  CreditCard,
  Users,
  Lock,
  Inbox,
  UserCog,
  PenTool,
  Moon,
  Sun,
  TrendingUp,
  Phone,
} from 'lucide-react'
import { NotificationBell } from '@/components/design/NotificationBell'
import { useTheme } from 'next-themes'

type UserInfo =
  | { type: 'admin'; name: string; email: string }
  | {
      type: 'showroom'
      name: string
      email: string
      showroomId: string
      showroomName: string
    }
  | {
      type: 'designer'
      name: string
      email: string
      designerId: string
      avatarUrl: string | null
    }

interface SidebarProps {
  userInfo: UserInfo
}

interface NavLink {
  href: string
  label: string
  icon: React.ComponentType<{ className?: string }>
  requiredFeature?: keyof PlanFeatures
}

const adminLinks: NavLink[] = [
  { href: '/admin/showrooms', label: 'Showrooms', icon: Building2 },
  { href: '/admin/categories', label: 'Categories', icon: LayoutGrid },
  { href: '/admin/designers', label: 'Designers', icon: PenTool },
  { href: '/admin/voice-agent', label: 'Voice Agent', icon: Phone },
  { href: '/admin/settings', label: 'Settings', icon: Settings },
]

const showroomLinks: NavLink[] = [
  { href: '/showroom/projects', label: 'Projects', icon: FolderKanban },
  { href: '/showroom/customers', label: 'Customers', icon: Users },
  { href: '/showroom/products', label: 'Products', icon: Package },
  { href: '/showroom/branding', label: 'Branding', icon: Palette },
  { href: '/showroom/voice-agent', label: 'Voice Agent', icon: Phone },
  { href: '/showroom/billing', label: 'Billing', icon: CreditCard },
  { href: '/showroom/settings', label: 'Settings', icon: Settings },
]

const designerLinks: NavLink[] = [
  { href: '/designer/pool', label: 'Design Pool', icon: Inbox },
  { href: '/designer/projects', label: 'My Projects', icon: FolderKanban },
  { href: '/designer/performance', label: 'Performance', icon: TrendingUp },
  { href: '/designer/profile', label: 'Profile', icon: UserCog },
]

export function Sidebar({ userInfo }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [open, setOpen] = useState(false)

  // Subscription context - may be null for admin users
  const subscription = useSubscriptionContextOptional()

  // Upgrade modal state
  const [upgradeModalOpen, setUpgradeModalOpen] = useState(false)
  const [upgradeFeature, setUpgradeFeature] = useState<keyof PlanFeatures>('webhookAccess')

  const links = userInfo.type === 'admin'
    ? adminLinks
    : userInfo.type === 'designer'
    ? designerLinks
    : showroomLinks

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  // Check if a feature is accessible
  const canAccessFeature = (feature: keyof PlanFeatures | undefined): boolean => {
    if (!feature) return true // No feature requirement
    if (!subscription) return true // No subscription context (admin)
    return subscription.canUseFeature(feature)
  }

  // Handle click on locked nav item
  const handleLockedClick = (feature: keyof PlanFeatures) => {
    setUpgradeFeature(feature)
    setUpgradeModalOpen(true)
    setOpen(false) // Close mobile menu if open
  }

  // Get current plan for upgrade modal
  const currentPlan = subscription?.subscription?.plan || null

  // Theme toggle for designer users
  const { theme, setTheme } = useTheme()

  const NavContent = () => (
    <div className="flex flex-col h-full">
      <div className="p-6 border-b">
        <h1 className="text-xl font-bold">CabinetScan</h1>
        {userInfo.type === 'showroom' && (
          <p className="text-sm text-gray-500 mt-1">{userInfo.showroomName}</p>
        )}
        {userInfo.type === 'designer' && (
          <p className="text-sm text-muted-foreground mt-1">Designer Dashboard</p>
        )}
      </div>

      <nav className="flex-1 p-4 space-y-1">
        {links.map((link) => {
          const Icon = link.icon
          const isActive = pathname.startsWith(link.href)
          const isLocked = !canAccessFeature(link.requiredFeature)

          // Render locked nav item
          if (isLocked && link.requiredFeature) {
            return (
              <button
                key={link.href}
                onClick={() => handleLockedClick(link.requiredFeature!)}
                className={cn(
                  'flex items-center justify-between w-full px-3 py-2 rounded-md text-sm font-medium transition-colors',
                  'text-gray-400 hover:bg-gray-100 cursor-pointer'
                )}
              >
                <span className="flex items-center gap-3">
                  <Icon className="h-5 w-5" />
                  {link.label}
                </span>
                <Lock className="h-4 w-4 text-gray-400" />
              </button>
            )
          }

          // Render regular nav item
          return (
            <Link
              key={link.href}
              href={link.href}
              onClick={() => setOpen(false)}
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors',
                isActive
                  ? 'bg-blue-50 text-blue-700'
                  : 'text-gray-600 hover:bg-gray-100'
              )}
            >
              <Icon className="h-5 w-5" />
              {link.label}
            </Link>
          )
        })}
      </nav>

      {/* Subscription status indicator for showroom users */}
      {userInfo.type === 'showroom' && subscription && (
        <SubscriptionIndicator
          plan={subscription.subscription?.plan || null}
          status={subscription.subscription?.status || 'trial'}
          trialDaysRemaining={subscription.trialDaysRemaining}
          isTrial={subscription.isTrial}
        />
      )}

      <div className="p-4 border-t">
        <div className="mb-4 flex items-center justify-between">
          <div className="min-w-0">
            <p className="text-sm font-medium truncate">{userInfo.name}</p>
            <p className="text-xs text-muted-foreground truncate">{userInfo.email}</p>
          </div>
          {(userInfo.type === 'designer' || userInfo.type === 'showroom') && (
            <NotificationBell recipientType={userInfo.type} />
          )}
        </div>
        {userInfo.type === 'designer' && (
          <Button
            variant="ghost"
            size="sm"
            className="w-full mb-2 justify-start gap-2"
            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
          >
            {theme === 'dark' ? (
              <Sun className="h-4 w-4" />
            ) : (
              <Moon className="h-4 w-4" />
            )}
            {theme === 'dark' ? 'Light mode' : 'Dark mode'}
          </Button>
        )}
        <Button
          variant="outline"
          size="sm"
          className="w-full"
          onClick={handleSignOut}
        >
          <LogOut className="h-4 w-4 mr-2" />
          Sign out
        </Button>
      </div>
    </div>
  )

  return (
    <>
      {/* Mobile header */}
      <div className="lg:hidden fixed top-0 left-0 right-0 z-40 bg-background border-b h-16 flex items-center px-4">
        <Sheet open={open} onOpenChange={setOpen}>
          <SheetTrigger asChild>
            <Button variant="ghost" size="icon">
              <Menu className="h-6 w-6" />
            </Button>
          </SheetTrigger>
          <SheetContent side="left" className="p-0 w-64">
            <NavContent />
          </SheetContent>
        </Sheet>
        <h1 className="ml-4 text-lg font-bold">CabinetScan</h1>
      </div>

      {/* Desktop sidebar */}
      <aside className="hidden lg:block fixed inset-y-0 left-0 w-64 bg-background border-r">
        <NavContent />
      </aside>

      {/* Mobile spacer */}
      <div className="lg:hidden h-16" />

      {/* Upgrade Modal */}
      <UpgradeModal
        isOpen={upgradeModalOpen}
        onClose={() => setUpgradeModalOpen(false)}
        feature={upgradeFeature}
        currentPlan={currentPlan}
      />
    </>
  )
}

/**
 * Subscription status indicator shown in the sidebar.
 */
function SubscriptionIndicator({
  plan,
  status,
  trialDaysRemaining,
  isTrial,
}: {
  plan: SubscriptionPlan | null
  status: string
  trialDaysRemaining: number | null
  isTrial: boolean
}) {
  // Don't show for active paid plans
  if (status === 'active' && plan && plan !== 'trial') {
    return null
  }

  // Trial indicator
  if (isTrial && trialDaysRemaining !== null) {
    const urgency =
      trialDaysRemaining <= 1 ? 'red' : trialDaysRemaining <= 3 ? 'yellow' : 'blue'

    const bgColors = {
      red: 'bg-red-50 border-red-200',
      yellow: 'bg-yellow-50 border-yellow-200',
      blue: 'bg-blue-50 border-blue-200',
    }

    const textColors = {
      red: 'text-red-700',
      yellow: 'text-yellow-700',
      blue: 'text-blue-700',
    }

    return (
      <div className={cn('mx-4 mb-4 p-3 rounded-lg border', bgColors[urgency])}>
        <p className={cn('text-xs font-medium', textColors[urgency])}>
          {trialDaysRemaining === 0
            ? 'Trial expires today'
            : trialDaysRemaining === 1
            ? '1 day left in trial'
            : `${trialDaysRemaining} days left in trial`}
        </p>
        <Link
          href="/showroom/billing"
          className={cn('text-xs font-medium hover:underline', textColors[urgency])}
        >
          Upgrade now
        </Link>
      </div>
    )
  }

  // Past due indicator
  if (status === 'past_due') {
    return (
      <div className="mx-4 mb-4 p-3 rounded-lg border bg-red-50 border-red-200">
        <p className="text-xs font-medium text-red-700">Payment overdue</p>
        <Link
          href="/showroom/billing"
          className="text-xs font-medium text-red-700 hover:underline"
        >
          Update payment
        </Link>
      </div>
    )
  }

  return null
}
