// AWS S3 client for Glacier operations
// Uses AWS SDK v3 for Deno

import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  RestoreObjectCommand,
  HeadObjectCommand,
} from 'npm:@aws-sdk/client-s3@3.450.0'
import { getSignedUrl } from 'npm:@aws-sdk/s3-request-presigner@3.450.0'

// Environment variables (set in Supabase Dashboard -> Edge Functions -> Secrets)
const AWS_ACCESS_KEY_ID = Deno.env.get('AWS_ACCESS_KEY_ID') ?? ''
const AWS_SECRET_ACCESS_KEY = Deno.env.get('AWS_SECRET_ACCESS_KEY') ?? ''
const AWS_REGION = Deno.env.get('AWS_REGION') ?? 'us-east-1'
const S3_ARCHIVE_BUCKET = Deno.env.get('S3_ARCHIVE_BUCKET') ?? 'cabinetscan-archive-prod'

if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
  console.warn('AWS credentials not configured - archive functions will fail')
}

export const s3Client = new S3Client({
  region: AWS_REGION,
  credentials: {
    accessKeyId: AWS_ACCESS_KEY_ID,
    secretAccessKey: AWS_SECRET_ACCESS_KEY,
  },
})

export const ARCHIVE_BUCKET = S3_ARCHIVE_BUCKET

export interface ArchiveFileResult {
  success: boolean
  s3Key?: string
  error?: string
}

// Upload file to S3 (will automatically transition to Glacier via lifecycle policy)
export async function uploadToArchive(
  key: string,
  body: Uint8Array | ReadableStream<Uint8Array>,
  contentType: string,
  metadata?: Record<string, string>
): Promise<ArchiveFileResult> {
  try {
    await s3Client.send(
      new PutObjectCommand({
        Bucket: ARCHIVE_BUCKET,
        Key: key,
        Body: body,
        ContentType: contentType,
        Metadata: metadata,
        StorageClass: 'GLACIER', // Immediately to Glacier
      })
    )
    return { success: true, s3Key: key }
  } catch (error) {
    console.error(`Failed to upload ${key} to S3:`, error)
    return { success: false, error: String(error) }
  }
}

// Initiate Glacier restore
export async function initiateRestore(
  key: string,
  tier: 'Expedited' | 'Standard' | 'Bulk' = 'Expedited',
  daysAvailable: number = 2 // How long to keep restored copy
): Promise<{ success: boolean; requestId?: string; error?: string }> {
  try {
    const response = await s3Client.send(
      new RestoreObjectCommand({
        Bucket: ARCHIVE_BUCKET,
        Key: key,
        RestoreRequest: {
          Days: daysAvailable,
          GlacierJobParameters: {
            Tier: tier,
          },
        },
      })
    )
    return {
      success: true,
      requestId: response.$metadata.requestId,
    }
  } catch (error: unknown) {
    // RestoreAlreadyInProgress is not an error
    if (error && typeof error === 'object' && 'name' in error && error.name === 'RestoreAlreadyInProgress') {
      return { success: true, requestId: 'already-in-progress' }
    }
    console.error(`Failed to initiate restore for ${key}:`, error)
    return { success: false, error: String(error) }
  }
}

// Check if object is restored and available
export async function checkRestoreStatus(
  key: string
): Promise<{
  isRestored: boolean
  isRestoring: boolean
  expiresAt?: Date
  error?: string
}> {
  try {
    const response = await s3Client.send(
      new HeadObjectCommand({
        Bucket: ARCHIVE_BUCKET,
        Key: key,
      })
    )

    const restore = response.Restore
    if (!restore) {
      return { isRestored: false, isRestoring: false }
    }

    // Parse restore header: 'ongoing-request="true"' or 'ongoing-request="false", expiry-date="..."'
    const isOngoing = restore.includes('ongoing-request="true"')
    const isComplete = restore.includes('ongoing-request="false"')

    let expiresAt: Date | undefined
    const expiryMatch = restore.match(/expiry-date="([^"]+)"/)
    if (expiryMatch) {
      expiresAt = new Date(expiryMatch[1])
    }

    return {
      isRestored: isComplete,
      isRestoring: isOngoing,
      expiresAt,
    }
  } catch (error) {
    console.error(`Failed to check restore status for ${key}:`, error)
    return { isRestored: false, isRestoring: false, error: String(error) }
  }
}

// Download restored file from S3
export async function downloadFromArchive(key: string): Promise<{
  success: boolean
  data?: Uint8Array
  contentType?: string
  error?: string
}> {
  try {
    const response = await s3Client.send(
      new GetObjectCommand({
        Bucket: ARCHIVE_BUCKET,
        Key: key,
      })
    )

    const data = await response.Body?.transformToByteArray()
    if (!data) {
      return { success: false, error: 'Empty response body' }
    }

    return {
      success: true,
      data,
      contentType: response.ContentType,
    }
  } catch (error) {
    console.error(`Failed to download ${key} from S3:`, error)
    return { success: false, error: String(error) }
  }
}

// Generate presigned URL for direct download (useful during 48hr window)
export async function getPresignedDownloadUrl(
  key: string,
  expiresInSeconds: number = 3600
): Promise<string> {
  return getSignedUrl(
    s3Client,
    new GetObjectCommand({
      Bucket: ARCHIVE_BUCKET,
      Key: key,
    }),
    { expiresIn: expiresInSeconds }
  )
}

// Delete from archive (after re-upload or cleanup)
export async function deleteFromArchive(key: string): Promise<boolean> {
  try {
    await s3Client.send(
      new DeleteObjectCommand({
        Bucket: ARCHIVE_BUCKET,
        Key: key,
      })
    )
    return true
  } catch (error) {
    console.error(`Failed to delete ${key} from S3:`, error)
    return false
  }
}
