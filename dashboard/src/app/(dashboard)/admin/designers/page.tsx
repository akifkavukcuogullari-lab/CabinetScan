'use client'

import { useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Plus, PenTool, Loader2, Copy, Check, Mail, Clock, Link2, RotateCw, BarChart3 } from 'lucide-react'
import Link from 'next/link'
import { toast } from 'sonner'

interface Designer {
  id: string
  user_id: string
  email: string
  full_name: string
  avatar_url: string | null
  bio: string | null
  is_active: boolean
  created_at: string
  active_project_count: number
}

interface PendingInvitation {
  id: string
  email: string
  full_name: string
  token: string
  expires_at: string
  created_at: string
}

export default function AdminDesignersPage() {
  const router = useRouter()
  const supabase = createClient()

  const [designers, setDesigners] = useState<Designer[]>([])
  const [pendingInvitations, setPendingInvitations] = useState<PendingInvitation[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Invite dialog state
  const [inviteOpen, setInviteOpen] = useState(false)
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteFullName, setInviteFullName] = useState('')
  const [inviteSubmitting, setInviteSubmitting] = useState(false)
  const [inviteLink, setInviteLink] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)

  // Toggling active state
  const [togglingId, setTogglingId] = useState<string | null>(null)

  // Invitation actions state
  const [copiedInvitationId, setCopiedInvitationId] = useState<string | null>(null)
  const [resendingId, setResendingId] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    setLoading(true)
    setError(null)

    try {
      // Fetch designers
      const { data: designerRows, error: designerError } = await supabase
        .from('designers')
        .select('*')
        .order('created_at', { ascending: false })

      if (designerError) {
        setError(designerError.message)
        setLoading(false)
        return
      }

      // Fetch active project counts per designer
      const { data: requestCounts } = await supabase
        .from('design_requests')
        .select('designer_id')
        .not('designer_id', 'is', null)
        .not('status', 'in', '("completed","canceled")')

      const countMap: Record<string, number> = {}
      requestCounts?.forEach((r: { designer_id: string | null }) => {
        if (r.designer_id) {
          countMap[r.designer_id] = (countMap[r.designer_id] || 0) + 1
        }
      })

      const designersWithCounts: Designer[] = (designerRows || []).map((d: {
        id: string
        user_id: string
        email: string
        full_name: string
        avatar_url: string | null
        bio: string | null
        is_active: boolean
        created_at: string
      }) => ({
        ...d,
        active_project_count: countMap[d.id] || 0,
      }))

      setDesigners(designersWithCounts)

      // Fetch pending invitations (not accepted, not expired)
      const { data: invitations } = await supabase
        .from('designer_invitations')
        .select('id, email, full_name, token, expires_at, created_at')
        .is('accepted_at', null)
        .gte('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false })

      setPendingInvitations(invitations || [])
    } catch (err) {
      console.error('Failed to fetch designers:', err)
      setError('Failed to load designers')
    } finally {
      setLoading(false)
    }
  }, [supabase])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  const handleInvite = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!inviteEmail.trim() || !inviteFullName.trim()) {
      toast.error('Please fill in all fields')
      return
    }

    setInviteSubmitting(true)
    setInviteLink(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        toast.error('You must be signed in to invite designers')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/invite-designer`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            email: inviteEmail.trim(),
            full_name: inviteFullName.trim(),
          }),
        }
      )

      const data = await response.json()

      if (!response.ok || !data.success) {
        toast.error(data.error || 'Failed to send invitation')
        return
      }

      // Show invitation link if available
      if (data.invitation_link) {
        setInviteLink(data.invitation_link)
      }

      if (data.error) {
        // Invitation created but email failed
        toast.warning(data.error)
      } else {
        toast.success(`Invitation sent to ${inviteEmail}`)
      }

      // Refresh data
      fetchData()
    } catch (err) {
      console.error('Failed to invite designer:', err)
      toast.error('An error occurred while sending the invitation')
    } finally {
      setInviteSubmitting(false)
    }
  }

  const handleCopyLink = async () => {
    if (!inviteLink) return
    try {
      await navigator.clipboard.writeText(inviteLink)
      setCopied(true)
      toast.success('Invitation link copied to clipboard')
      setTimeout(() => setCopied(false), 2000)
    } catch {
      toast.error('Failed to copy link')
    }
  }

  const handleCloseDialog = () => {
    setInviteOpen(false)
    setInviteEmail('')
    setInviteFullName('')
    setInviteLink(null)
    setCopied(false)
  }

  const handleToggleActive = async (designer: Designer) => {
    setTogglingId(designer.id)

    try {
      const { error: updateError } = await supabase
        .from('designers')
        .update({ is_active: !designer.is_active })
        .eq('id', designer.id)

      if (updateError) {
        toast.error('Failed to update designer status')
        return
      }

      setDesigners((prev) =>
        prev.map((d) =>
          d.id === designer.id ? { ...d, is_active: !d.is_active } : d
        )
      )

      toast.success(
        `${designer.full_name} is now ${!designer.is_active ? 'active' : 'inactive'}`
      )
    } catch (err) {
      console.error('Failed to toggle designer status:', err)
      toast.error('An error occurred')
    } finally {
      setTogglingId(null)
    }
  }

  const handleCopyInvitationLink = async (invitation: PendingInvitation) => {
    try {
      const link = `${window.location.origin}/accept-designer-invitation?token=${invitation.token}`
      await navigator.clipboard.writeText(link)
      setCopiedInvitationId(invitation.id)
      toast.success('Invitation link copied to clipboard')
      setTimeout(() => setCopiedInvitationId(null), 2000)
    } catch {
      toast.error('Failed to copy link')
    }
  }

  const handleResendInvitation = async (invitation: PendingInvitation) => {
    setResendingId(invitation.id)

    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        toast.error('You must be signed in to resend invitations')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/invite-designer`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            email: invitation.email,
            full_name: invitation.full_name,
          }),
        }
      )

      const data = await response.json()

      if (!response.ok || !data.success) {
        toast.error(data.error || 'Failed to resend invitation')
        return
      }

      if (data.error) {
        toast.warning(data.error)
      } else {
        toast.success(`Invitation resent to ${invitation.email}`)
      }

      fetchData()
    } catch (err) {
      console.error('Failed to resend invitation:', err)
      toast.error('An error occurred while resending the invitation')
    } finally {
      setResendingId(null)
    }
  }

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Designers</h1>
            <p className="text-gray-500">Manage designer accounts and invitations</p>
          </div>
        </div>
        <Card>
          <CardContent className="flex items-center justify-center py-12">
            <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Designers</h1>
          <p className="text-gray-500">Manage designer accounts and invitations</p>
        </div>
        <div className="flex items-center gap-2">
          <Link href="/admin/designers/performance">
            <Button variant="outline">
              <BarChart3 className="h-4 w-4 mr-2" />
              Performance Report
            </Button>
          </Link>
        <Dialog open={inviteOpen} onOpenChange={(open) => {
          if (!open) handleCloseDialog()
          else setInviteOpen(true)
        }}>
          <DialogTrigger asChild>
            <Button>
              <Plus className="h-4 w-4 mr-2" />
              Invite Designer
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Invite a Designer</DialogTitle>
              <DialogDescription>
                Send an invitation to a designer to join CabinetScan. They will receive an email with a link to create their account.
              </DialogDescription>
            </DialogHeader>

            {inviteLink ? (
              <div className="space-y-4 py-4">
                <div className="p-3 bg-green-50 text-green-800 rounded-md text-sm">
                  Invitation created successfully!
                </div>
                <div className="space-y-2">
                  <Label>Invitation Link</Label>
                  <div className="flex gap-2">
                    <Input
                      value={inviteLink}
                      readOnly
                      className="bg-gray-50 text-xs"
                    />
                    <Button
                      variant="outline"
                      size="icon"
                      onClick={handleCopyLink}
                      className="shrink-0"
                    >
                      {copied ? (
                        <Check className="h-4 w-4 text-green-600" />
                      ) : (
                        <Copy className="h-4 w-4" />
                      )}
                    </Button>
                  </div>
                  <p className="text-xs text-gray-500">
                    Share this link with the designer if they did not receive the email.
                  </p>
                </div>
                <DialogFooter>
                  <Button variant="outline" onClick={handleCloseDialog}>
                    Done
                  </Button>
                </DialogFooter>
              </div>
            ) : (
              <form onSubmit={handleInvite}>
                <div className="space-y-4 py-4">
                  <div className="space-y-2">
                    <Label htmlFor="invite-name">Full Name</Label>
                    <Input
                      id="invite-name"
                      placeholder="Jane Smith"
                      value={inviteFullName}
                      onChange={(e) => setInviteFullName(e.target.value)}
                      required
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="invite-email">Email Address</Label>
                    <Input
                      id="invite-email"
                      type="email"
                      placeholder="jane@example.com"
                      value={inviteEmail}
                      onChange={(e) => setInviteEmail(e.target.value)}
                      required
                    />
                  </div>
                </div>
                <DialogFooter>
                  <Button
                    type="button"
                    variant="outline"
                    onClick={handleCloseDialog}
                    disabled={inviteSubmitting}
                  >
                    Cancel
                  </Button>
                  <Button type="submit" disabled={inviteSubmitting}>
                    {inviteSubmitting ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Sending...
                      </>
                    ) : (
                      <>
                        <Mail className="mr-2 h-4 w-4" />
                        Send Invitation
                      </>
                    )}
                  </Button>
                </DialogFooter>
              </form>
            )}
          </DialogContent>
        </Dialog>
        </div>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading designers: {error}
          </CardContent>
        </Card>
      ) : designers.length > 0 || pendingInvitations.length > 0 ? (
        <div className="space-y-6">
          {/* Pending invitations */}
          {pendingInvitations.length > 0 && (
            <Card>
              <div className="px-6 py-4 border-b">
                <h2 className="text-sm font-semibold text-gray-700">
                  Pending Invitations ({pendingInvitations.length})
                </h2>
              </div>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>Sent</TableHead>
                    <TableHead>Expires</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {pendingInvitations.map((inv) => (
                    <TableRow key={inv.id}>
                      <TableCell className="font-medium">{inv.full_name}</TableCell>
                      <TableCell>{inv.email}</TableCell>
                      <TableCell className="text-gray-500">
                        {new Date(inv.created_at).toLocaleDateString()}
                      </TableCell>
                      <TableCell>
                        <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">
                          <Clock className="h-3 w-3 mr-1" />
                          {new Date(inv.expires_at).toLocaleDateString()}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-2">
                          <Button
                            variant="outline"
                            size="sm"
                            className="gap-1.5"
                            onClick={() => handleCopyInvitationLink(inv)}
                          >
                            {copiedInvitationId === inv.id ? (
                              <>
                                <Check className="h-3.5 w-3.5 text-green-600" />
                                Copied
                              </>
                            ) : (
                              <>
                                <Link2 className="h-3.5 w-3.5" />
                                Copy Link
                              </>
                            )}
                          </Button>
                          <Button
                            variant="outline"
                            size="sm"
                            className="gap-1.5"
                            onClick={() => handleResendInvitation(inv)}
                            disabled={resendingId === inv.id}
                          >
                            {resendingId === inv.id ? (
                              <>
                                <Loader2 className="h-3.5 w-3.5 animate-spin" />
                                Sending...
                              </>
                            ) : (
                              <>
                                <RotateCw className="h-3.5 w-3.5" />
                                Resend
                              </>
                            )}
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </Card>
          )}

          {/* Designers list */}
          {designers.length > 0 && (
            <Card>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Name</TableHead>
                    <TableHead>Email</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Active Projects</TableHead>
                    <TableHead>Joined</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {designers.map((designer) => (
                    <TableRow
                      key={designer.id}
                      className="cursor-pointer hover:bg-gray-50"
                      onClick={() => router.push(`/admin/designers/${designer.id}`)}
                    >
                      <TableCell>
                        <p className="font-medium">{designer.full_name}</p>
                      </TableCell>
                      <TableCell className="text-gray-500">
                        {designer.email}
                      </TableCell>
                      <TableCell>
                        {designer.is_active ? (
                          <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
                            Active
                          </Badge>
                        ) : (
                          <Badge variant="outline" className="bg-gray-50 text-gray-600 border-gray-200">
                            Inactive
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        {designer.active_project_count > 0 ? (
                          <span className="text-blue-600 font-medium">
                            {designer.active_project_count}
                          </span>
                        ) : (
                          <span className="text-gray-400">0</span>
                        )}
                      </TableCell>
                      <TableCell className="text-gray-500">
                        {new Date(designer.created_at).toLocaleDateString()}
                      </TableCell>
                      <TableCell className="text-right" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center justify-end gap-3">
                          <div className="flex items-center gap-2">
                            <span className="text-xs text-gray-500">
                              {designer.is_active ? 'Active' : 'Inactive'}
                            </span>
                            <Switch
                              checked={designer.is_active}
                              onCheckedChange={() => handleToggleActive(designer)}
                              disabled={togglingId === designer.id}
                            />
                          </div>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </Card>
          )}
        </div>
      ) : (
        <Card>
          <CardContent className="py-10 text-center">
            <PenTool className="h-12 w-12 mx-auto text-gray-400 mb-4" />
            <h3 className="text-lg font-medium mb-2">No designers yet</h3>
            <p className="text-gray-500 mb-4">
              Invite your first designer to get started
            </p>
            <Button onClick={() => setInviteOpen(true)}>
              <Plus className="h-4 w-4 mr-2" />
              Invite Designer
            </Button>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
