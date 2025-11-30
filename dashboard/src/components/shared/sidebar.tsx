'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import {
  Building2,
  LayoutGrid,
  Package,
  FolderKanban,
  Settings,
  Palette,
  LogOut,
  Menu,
  X,
  CreditCard,
} from 'lucide-react'
import { useState } from 'react'
import { Sheet, SheetContent, SheetTrigger } from '@/components/ui/sheet'

type UserInfo =
  | { type: 'admin'; name: string; email: string }
  | {
      type: 'showroom'
      name: string
      email: string
      showroomId: string
      showroomName: string
    }

interface SidebarProps {
  userInfo: UserInfo
}

const adminLinks = [
  { href: '/admin/showrooms', label: 'Showrooms', icon: Building2 },
  { href: '/admin/categories', label: 'Categories', icon: LayoutGrid },
]

const showroomLinks = [
  { href: '/showroom/projects', label: 'Projects', icon: FolderKanban },
  { href: '/showroom/products', label: 'Products', icon: Package },
  { href: '/showroom/branding', label: 'Branding', icon: Palette },
  { href: '/showroom/billing', label: 'Billing', icon: CreditCard },
  { href: '/showroom/settings', label: 'Settings', icon: Settings },
]

export function Sidebar({ userInfo }: SidebarProps) {
  const pathname = usePathname()
  const router = useRouter()
  const supabase = createClient()
  const [open, setOpen] = useState(false)

  const links = userInfo.type === 'admin' ? adminLinks : showroomLinks

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    router.push('/login')
  }

  const NavContent = () => (
    <div className="flex flex-col h-full">
      <div className="p-6 border-b">
        <h1 className="text-xl font-bold">Nextlyn Scan</h1>
        {userInfo.type === 'showroom' && (
          <p className="text-sm text-gray-500 mt-1">{userInfo.showroomName}</p>
        )}
      </div>

      <nav className="flex-1 p-4 space-y-1">
        {links.map((link) => {
          const Icon = link.icon
          const isActive = pathname.startsWith(link.href)

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

      <div className="p-4 border-t">
        <div className="mb-4">
          <p className="text-sm font-medium truncate">{userInfo.name}</p>
          <p className="text-xs text-gray-500 truncate">{userInfo.email}</p>
        </div>
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
      <div className="lg:hidden fixed top-0 left-0 right-0 z-40 bg-white border-b h-16 flex items-center px-4">
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
        <h1 className="ml-4 text-lg font-bold">Nextlyn Scan</h1>
      </div>

      {/* Desktop sidebar */}
      <aside className="hidden lg:block fixed inset-y-0 left-0 w-64 bg-white border-r">
        <NavContent />
      </aside>

      {/* Mobile spacer */}
      <div className="lg:hidden h-16" />
    </>
  )
}
