'use client'

import { useState } from 'react'
import Link from 'next/link'
import { Lock, FileCode, ArrowUpRight } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

export function LockedDxfTab() {
  const [showUpgradeDialog, setShowUpgradeDialog] = useState(false)

  return (
    <>
      <button
        type="button"
        className="inline-flex items-center justify-center whitespace-nowrap rounded-sm px-3 py-1.5 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 gap-2 opacity-50 cursor-pointer hover:opacity-70 hover:bg-muted"
        onClick={() => setShowUpgradeDialog(true)}
      >
        <FileCode className="h-4 w-4" />
        DXF Preview
        <Lock className="h-3 w-3 ml-1" />
      </button>

      <Dialog open={showUpgradeDialog} onOpenChange={setShowUpgradeDialog}>
        <DialogContent className="sm:max-w-sm p-6">
          <DialogHeader className="space-y-3">
            <div className="mx-auto p-2.5 bg-gradient-to-br from-purple-100 to-blue-100 rounded-full">
              <Lock className="h-5 w-5 text-purple-600" />
            </div>
            <DialogTitle className="text-center text-lg">Upgrade Required</DialogTitle>
            <DialogDescription className="text-center text-sm">
              <span className="font-medium text-gray-900">AutoCAD export</span> is a premium feature available on the{' '}
              <span className="font-semibold text-purple-600">PRO</span> plan and above.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 mt-4">
            <Link href="/showroom/billing" onClick={() => setShowUpgradeDialog(false)}>
              <Button className="w-full bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700" size="sm">
                Upgrade to PRO
                <ArrowUpRight className="h-3.5 w-3.5 ml-1.5" />
              </Button>
            </Link>
            <Button variant="ghost" onClick={() => setShowUpgradeDialog(false)} className="w-full" size="sm">
              Maybe Later
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}
