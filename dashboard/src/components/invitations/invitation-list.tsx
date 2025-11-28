'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
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
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Loader2,
  Mail,
  MailX,
  RefreshCw,
  UserPlus,
  Clock,
  CheckCircle2,
  XCircle,
  AlertCircle,
} from 'lucide-react'

interface Invitation {
  id: string
  email: string
  full_name: string | null
  status: 'pending' | 'accepted' | 'expired' | 'revoked'
  role: string
  expires_at: string
  created_at: string
  accepted_at: string | null
}

interface ShowroomUser {
  id: string
  email: string
  full_name: string
  role: string
  is_primary: boolean
  is_active: boolean
  created_at: string
  last_login_at: string | null
}

interface InvitationListProps {
  showroomId: string
}

export function InvitationList({ showroomId }: InvitationListProps) {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const [invitations, setInvitations] = useState<Invitation[]>([])
  const [users, setUsers] = useState<ShowroomUser[]>([])
  const [error, setError] = useState<string | null>(null)

  // New invitation dialog state
  const [dialogOpen, setDialogOpen] = useState(false)
  const [newInvitation, setNewInvitation] = useState({
    email: '',
    fullName: '',
  })
  const [inviteError, setInviteError] = useState<string | null>(null)
  const [inviting, setInviting] = useState(false)

  const fetchData = async () => {
    setLoading(true)
    setError(null)

    try {
      // Fetch invitations
      const { data: invitationData, error: invError } = await supabase
        .from('showroom_invitations')
        .select('*')
        .eq('showroom_id', showroomId)
        .order('created_at', { ascending: false })

      if (invError) throw invError
      setInvitations(invitationData || [])

      // Fetch existing users
      const { data: userData, error: userError } = await supabase
        .from('showroom_users')
        .select('*')
        .eq('showroom_id', showroomId)
        .eq('is_active', true)
        .order('created_at', { ascending: true })

      if (userError) throw userError
      setUsers(userData || [])
    } catch (err) {
      console.error('Failed to fetch data:', err)
      setError('Failed to load invitation data')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchData()
  }, [showroomId])

  const sendInvitation = async () => {
    if (!newInvitation.email) return

    setInviting(true)
    setInviteError(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        setInviteError('Not authenticated')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-invitation`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            showroom_id: showroomId,
            email: newInvitation.email,
            full_name: newInvitation.fullName || undefined,
          }),
        }
      )

      const data = await response.json()

      if (!response.ok || !data.success) {
        setInviteError(data.error || 'Failed to send invitation')
        return
      }

      // Success - close dialog and refresh
      setDialogOpen(false)
      setNewInvitation({ email: '', fullName: '' })
      fetchData()
    } catch (err) {
      console.error('Failed to send invitation:', err)
      setInviteError('Failed to send invitation')
    } finally {
      setInviting(false)
    }
  }

  const resendInvitation = async (invitationId: string, email: string) => {
    setActionLoading(invitationId)

    try {
      // First revoke the old invitation
      await supabase
        .from('showroom_invitations')
        .update({ status: 'revoked' })
        .eq('id', invitationId)

      // Then send a new one
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        setError('Not authenticated')
        return
      }

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-invitation`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            showroom_id: showroomId,
            email,
          }),
        }
      )

      const data = await response.json()

      if (!response.ok || !data.success) {
        setError(data.error || 'Failed to resend invitation')
        return
      }

      fetchData()
    } catch (err) {
      console.error('Failed to resend invitation:', err)
      setError('Failed to resend invitation')
    } finally {
      setActionLoading(null)
    }
  }

  const revokeInvitation = async (invitationId: string) => {
    setActionLoading(invitationId)

    try {
      const { error: revokeError } = await supabase
        .from('showroom_invitations')
        .update({ status: 'revoked' })
        .eq('id', invitationId)

      if (revokeError) throw revokeError

      fetchData()
    } catch (err) {
      console.error('Failed to revoke invitation:', err)
      setError('Failed to revoke invitation')
    } finally {
      setActionLoading(null)
    }
  }

  const getStatusBadge = (status: string, expiresAt: string) => {
    const isExpired = status === 'pending' && new Date(expiresAt) < new Date()

    if (isExpired) {
      return (
        <Badge variant="outline" className="bg-orange-50 text-orange-700 border-orange-200">
          <Clock className="h-3 w-3 mr-1" />
          Expired
        </Badge>
      )
    }

    switch (status) {
      case 'pending':
        return (
          <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">
            <Mail className="h-3 w-3 mr-1" />
            Pending
          </Badge>
        )
      case 'accepted':
        return (
          <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
            <CheckCircle2 className="h-3 w-3 mr-1" />
            Accepted
          </Badge>
        )
      case 'expired':
        return (
          <Badge variant="outline" className="bg-orange-50 text-orange-700 border-orange-200">
            <Clock className="h-3 w-3 mr-1" />
            Expired
          </Badge>
        )
      case 'revoked':
        return (
          <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
            <XCircle className="h-3 w-3 mr-1" />
            Revoked
          </Badge>
        )
      default:
        return <Badge variant="outline">{status}</Badge>
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Existing Users Section */}
      {users.length > 0 && (
        <div>
          <h3 className="text-sm font-medium text-gray-700 mb-3">Active Team Members</h3>
          <div className="space-y-2">
            {users.map((user) => (
              <div
                key={user.id}
                className="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
              >
                <div>
                  <p className="font-medium">{user.full_name || user.email}</p>
                  <p className="text-sm text-gray-500">{user.email}</p>
                </div>
                <div className="flex items-center gap-2">
                  {user.is_primary && (
                    <Badge variant="secondary">Primary</Badge>
                  )}
                  <Badge variant="outline">{user.role}</Badge>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Invitations Section */}
      <div>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-medium text-gray-700">Invitations</h3>
          <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
            <DialogTrigger asChild>
              <Button size="sm">
                <UserPlus className="h-4 w-4 mr-2" />
                Invite User
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Invite Team Member</DialogTitle>
                <DialogDescription>
                  Send an invitation email to join this showroom.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                {inviteError && (
                  <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md flex items-center gap-2">
                    <AlertCircle className="h-4 w-4" />
                    {inviteError}
                  </div>
                )}
                <div className="space-y-2">
                  <Label htmlFor="invite-email">Email Address *</Label>
                  <Input
                    id="invite-email"
                    type="email"
                    placeholder="name@company.com"
                    value={newInvitation.email}
                    onChange={(e) =>
                      setNewInvitation((prev) => ({
                        ...prev,
                        email: e.target.value,
                      }))
                    }
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="invite-name">Full Name (Optional)</Label>
                  <Input
                    id="invite-name"
                    type="text"
                    placeholder="John Smith"
                    value={newInvitation.fullName}
                    onChange={(e) =>
                      setNewInvitation((prev) => ({
                        ...prev,
                        fullName: e.target.value,
                      }))
                    }
                  />
                </div>
              </div>
              <DialogFooter>
                <Button
                  variant="outline"
                  onClick={() => setDialogOpen(false)}
                  disabled={inviting}
                >
                  Cancel
                </Button>
                <Button
                  onClick={sendInvitation}
                  disabled={inviting || !newInvitation.email}
                >
                  {inviting ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Sending...
                    </>
                  ) : (
                    <>
                      <Mail className="h-4 w-4 mr-2" />
                      Send Invitation
                    </>
                  )}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>

        {error && (
          <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md mb-4">
            {error}
          </div>
        )}

        {invitations.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <MailX className="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p>No invitations sent yet</p>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Email</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Sent</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {invitations.map((invitation) => {
                const isExpired =
                  invitation.status === 'pending' &&
                  new Date(invitation.expires_at) < new Date()
                const canResend =
                  invitation.status === 'pending' ||
                  invitation.status === 'expired' ||
                  isExpired
                const canRevoke = invitation.status === 'pending' && !isExpired

                return (
                  <TableRow key={invitation.id}>
                    <TableCell>{invitation.email}</TableCell>
                    <TableCell>{invitation.full_name || '-'}</TableCell>
                    <TableCell>
                      {getStatusBadge(invitation.status, invitation.expires_at)}
                    </TableCell>
                    <TableCell>
                      {new Date(invitation.created_at).toLocaleDateString()}
                    </TableCell>
                    <TableCell className="text-right">
                      <div className="flex items-center justify-end gap-2">
                        {canResend && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() =>
                              resendInvitation(invitation.id, invitation.email)
                            }
                            disabled={actionLoading === invitation.id}
                          >
                            {actionLoading === invitation.id ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <>
                                <RefreshCw className="h-4 w-4 mr-1" />
                                Resend
                              </>
                            )}
                          </Button>
                        )}
                        {canRevoke && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => revokeInvitation(invitation.id)}
                            disabled={actionLoading === invitation.id}
                            className="text-red-600 hover:text-red-700 hover:bg-red-50"
                          >
                            {actionLoading === invitation.id ? (
                              <Loader2 className="h-4 w-4 animate-spin" />
                            ) : (
                              <>
                                <XCircle className="h-4 w-4 mr-1" />
                                Revoke
                              </>
                            )}
                          </Button>
                        )}
                      </div>
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        )}
      </div>
    </div>
  )
}
