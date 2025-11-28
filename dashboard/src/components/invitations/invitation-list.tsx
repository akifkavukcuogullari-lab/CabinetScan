'use client'

import { useState, useEffect } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { formatError, logError, isUniqueViolation, FormattedError } from '@/lib/errors'
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
  const [error, setError] = useState<FormattedError | null>(null)

  // New invitation dialog state
  const [dialogOpen, setDialogOpen] = useState(false)
  const [newInvitation, setNewInvitation] = useState({
    email: '',
    fullName: '',
  })
  const [inviteError, setInviteError] = useState<FormattedError | null>(null)
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
      logError(err, { context: 'fetchInvitationData', showroomId })
      const formatted = formatError(err)
      setError(formatted)
      toast.error('Failed to Load Data', {
        description: formatted.message,
      })
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

    const loadingToast = toast.loading('Sending invitation...', {
      description: `Sending to ${newInvitation.email}`,
    })

    try {
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        toast.dismiss(loadingToast)
        const err: FormattedError = {
          title: 'Session Expired',
          message: 'Your session has expired. Please sign in again.',
          isRetryable: false,
        }
        setInviteError(err)
        toast.error(err.title, { description: err.message })
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
      toast.dismiss(loadingToast)

      if (!response.ok || !data.success) {
        const errorMessage = data.error || 'Failed to send invitation'

        // Check for duplicate email
        if (errorMessage.toLowerCase().includes('already') ||
            errorMessage.toLowerCase().includes('exists') ||
            errorMessage.toLowerCase().includes('duplicate')) {
          const err: FormattedError = {
            title: 'Already Invited',
            message: 'This email address has already been invited to this showroom.',
            suggestion: 'Check the invitation list below or use a different email.',
            isRetryable: false,
          }
          setInviteError(err)
          toast.error(err.title, { description: err.message })
        } else {
          const err: FormattedError = {
            title: 'Invitation Failed',
            message: errorMessage,
            isRetryable: true,
          }
          setInviteError(err)
          toast.error(err.title, { description: err.message })
        }
        return
      }

      // Success - close dialog and refresh
      toast.success('Invitation Sent', {
        description: `Invitation sent to ${newInvitation.email}`,
      })
      setDialogOpen(false)
      setNewInvitation({ email: '', fullName: '' })
      fetchData()
    } catch (err) {
      toast.dismiss(loadingToast)
      logError(err, { context: 'sendInvitation', showroomId, email: newInvitation.email })
      const formatted = formatError(err)
      setInviteError(formatted)
      toast.error(formatted.title, {
        description: formatted.message,
      })
    } finally {
      setInviting(false)
    }
  }

  const resendInvitation = async (invitationId: string, email: string) => {
    setActionLoading(invitationId)

    const loadingToast = toast.loading('Resending invitation...', {
      description: `Sending to ${email}`,
    })

    try {
      // First revoke the old invitation
      const { error: revokeError } = await supabase
        .from('showroom_invitations')
        .update({ status: 'revoked' })
        .eq('id', invitationId)

      if (revokeError) {
        logError(revokeError, { context: 'revokeOldInvitation', invitationId })
        // Continue anyway - we'll try to send a new one
      }

      // Then send a new one
      const { data: { session } } = await supabase.auth.getSession()

      if (!session) {
        toast.dismiss(loadingToast)
        toast.error('Session Expired', {
          description: 'Your session has expired. Please sign in again.',
        })
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
      toast.dismiss(loadingToast)

      if (!response.ok || !data.success) {
        const errorMessage = data.error || 'Failed to resend invitation'
        toast.error('Resend Failed', {
          description: errorMessage,
        })
        return
      }

      toast.success('Invitation Resent', {
        description: `New invitation sent to ${email}`,
      })
      fetchData()
    } catch (err) {
      toast.dismiss(loadingToast)
      logError(err, { context: 'resendInvitation', invitationId, email })
      const formatted = formatError(err)
      toast.error(formatted.title, {
        description: formatted.message,
      })
    } finally {
      setActionLoading(null)
    }
  }

  const revokeInvitation = async (invitationId: string, email: string) => {
    setActionLoading(invitationId)

    try {
      const { error: revokeError } = await supabase
        .from('showroom_invitations')
        .update({ status: 'revoked' })
        .eq('id', invitationId)

      if (revokeError) throw revokeError

      toast.success('Invitation Revoked', {
        description: `The invitation for ${email} has been revoked.`,
      })
      fetchData()
    } catch (err) {
      logError(err, { context: 'revokeInvitation', invitationId })
      const formatted = formatError(err)
      toast.error('Revoke Failed', {
        description: formatted.message,
      })
    } finally {
      setActionLoading(null)
    }
  }

  const getStatusBadge = (status: string, expiresAt: string) => {
    const isExpired = status === 'pending' && new Date(expiresAt) < new Date()

    if (isExpired) {
      return (
        <Badge variant="outline" className="bg-orange-50 text-orange-700 border-orange-200">
          <Clock className="h-3 w-3 mr-1" aria-hidden="true" />
          Expired
        </Badge>
      )
    }

    switch (status) {
      case 'pending':
        return (
          <Badge variant="outline" className="bg-yellow-50 text-yellow-700 border-yellow-200">
            <Mail className="h-3 w-3 mr-1" aria-hidden="true" />
            Pending
          </Badge>
        )
      case 'accepted':
        return (
          <Badge variant="outline" className="bg-green-50 text-green-700 border-green-200">
            <CheckCircle2 className="h-3 w-3 mr-1" aria-hidden="true" />
            Accepted
          </Badge>
        )
      case 'expired':
        return (
          <Badge variant="outline" className="bg-orange-50 text-orange-700 border-orange-200">
            <Clock className="h-3 w-3 mr-1" aria-hidden="true" />
            Expired
          </Badge>
        )
      case 'revoked':
        return (
          <Badge variant="outline" className="bg-gray-50 text-gray-700 border-gray-200">
            <XCircle className="h-3 w-3 mr-1" aria-hidden="true" />
            Revoked
          </Badge>
        )
      default:
        return <Badge variant="outline">{status}</Badge>
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8" role="status" aria-label="Loading invitations">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" aria-hidden="true" />
        <span className="sr-only">Loading invitations...</span>
      </div>
    )
  }

  if (error) {
    return (
      <div
        className="p-4 rounded-lg bg-red-50 border border-red-200"
        role="alert"
        aria-live="polite"
      >
        <div className="flex items-start gap-3">
          <AlertCircle className="h-5 w-5 text-red-600 mt-0.5 flex-shrink-0" aria-hidden="true" />
          <div className="flex-1">
            <p className="font-medium text-red-800">{error.title}</p>
            <p className="text-sm text-red-700 mt-1">{error.message}</p>
            <Button
              variant="outline"
              size="sm"
              className="mt-3 text-red-700 border-red-300 hover:bg-red-100"
              onClick={fetchData}
            >
              <RefreshCw className="h-3 w-3 mr-2" aria-hidden="true" />
              Try Again
            </Button>
          </div>
        </div>
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
          <Dialog open={dialogOpen} onOpenChange={(open) => {
            setDialogOpen(open)
            if (!open) {
              // Clear form and errors when closing
              setNewInvitation({ email: '', fullName: '' })
              setInviteError(null)
            }
          }}>
            <DialogTrigger asChild>
              <Button size="sm">
                <UserPlus className="h-4 w-4 mr-2" aria-hidden="true" />
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
                  <div
                    className="p-3 rounded-md bg-red-50 border border-red-200"
                    role="alert"
                    aria-live="polite"
                  >
                    <div className="flex items-start gap-2">
                      <AlertCircle className="h-4 w-4 text-red-600 mt-0.5 flex-shrink-0" aria-hidden="true" />
                      <div>
                        <p className="text-sm font-medium text-red-800">{inviteError.title}</p>
                        <p className="text-sm text-red-700">{inviteError.message}</p>
                        {inviteError.suggestion && (
                          <p className="text-xs text-red-600 mt-1">{inviteError.suggestion}</p>
                        )}
                      </div>
                    </div>
                  </div>
                )}
                <div className="space-y-2">
                  <Label htmlFor="invite-email">
                    Email Address <span className="text-red-500">*</span>
                  </Label>
                  <Input
                    id="invite-email"
                    type="email"
                    placeholder="name@company.com"
                    value={newInvitation.email}
                    onChange={(e) => {
                      setNewInvitation((prev) => ({
                        ...prev,
                        email: e.target.value,
                      }))
                      // Clear error when user starts typing
                      if (inviteError) setInviteError(null)
                    }}
                    disabled={inviting}
                    aria-required="true"
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
                    disabled={inviting}
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
                  aria-label={inviting ? 'Sending invitation...' : 'Send invitation'}
                >
                  {inviting ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" aria-hidden="true" />
                      Sending...
                    </>
                  ) : (
                    <>
                      <Mail className="h-4 w-4 mr-2" aria-hidden="true" />
                      Send Invitation
                    </>
                  )}
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>

        {invitations.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <MailX className="h-8 w-8 mx-auto mb-2 opacity-50" aria-hidden="true" />
            <p>No invitations sent yet</p>
            <p className="text-sm mt-1">Click &quot;Invite User&quot; to send your first invitation.</p>
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
                            aria-label={`Resend invitation to ${invitation.email}`}
                          >
                            {actionLoading === invitation.id ? (
                              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                            ) : (
                              <>
                                <RefreshCw className="h-4 w-4 mr-1" aria-hidden="true" />
                                Resend
                              </>
                            )}
                          </Button>
                        )}
                        {canRevoke && (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => revokeInvitation(invitation.id, invitation.email)}
                            disabled={actionLoading === invitation.id}
                            className="text-red-600 hover:text-red-700 hover:bg-red-50"
                            aria-label={`Revoke invitation for ${invitation.email}`}
                          >
                            {actionLoading === invitation.id ? (
                              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                            ) : (
                              <>
                                <XCircle className="h-4 w-4 mr-1" aria-hidden="true" />
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
