"""Supabase client utilities for the pipeline worker."""

import os
import httpx
from typing import Any


class SupabaseClient:
    """Minimal Supabase client for the pipeline worker.

    Uses service_role key to update job status and upload results.
    """

    def __init__(self):
        self.url = os.environ.get("SUPABASE_URL", "").rstrip("/")
        self.service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not self.url or not self.service_key:
            raise RuntimeError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        print(f"[SupabaseClient] URL: {self.url}", flush=True)
        print(f"[SupabaseClient] Key prefix: {self.service_key[:20]}...", flush=True)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.service_key}",
            "Content-Type": "application/json",
            "apikey": self.service_key,
        }

    async def update_job_status(
        self,
        job_id: str,
        status: str | None = None,
        progress: float | None = None,
        stage: str | None = None,
        error_message: str | None = None,
        **kwargs: Any,
    ) -> None:
        """Update a processing job directly via PostgREST (bypasses edge function)."""
        import datetime

        update: dict[str, Any] = {}
        if status is not None:
            update["status"] = status
        if progress is not None:
            update["progress"] = progress
        if stage is not None:
            update["stage"] = stage
        if error_message is not None:
            update["error_message"] = error_message

        # Track timing transitions
        now = datetime.datetime.utcnow().isoformat() + "Z"
        if status == "processing":
            update["started_at"] = now
        if status in ("completed", "failed"):
            update["completed_at"] = now

        # Results fields from kwargs
        for key in (
            "measurements_data", "floor_plan_png_url", "measurements_json_url",
            "scale_confidence", "validation_passed", "validation_issues",
            "processing_time_ms", "stage_timings",
        ):
            if key in kwargs:
                update[key] = kwargs[key]

        if not update:
            return

        url = f"{self.url}/rest/v1/processing_jobs?id=eq.{job_id}"
        print(f"[SupabaseClient] PATCH {url} body={update}", flush=True)

        async with httpx.AsyncClient() as client:
            resp = await client.patch(
                url,
                json=update,
                headers={
                    **self._headers(),
                    "Prefer": "return=representation",
                },
                timeout=30.0,
            )
            print(f"[SupabaseClient] Response: {resp.status_code} {resp.text[:200]}", flush=True)
            resp.raise_for_status()

    async def upload_file(
        self,
        bucket: str,
        path: str,
        data: bytes,
        content_type: str = "application/octet-stream",
    ) -> str:
        """Upload a file to Supabase storage. Returns public URL."""
        url = f"{self.url}/storage/v1/object/{bucket}/{path}"
        print(f"[SupabaseClient] Upload {url} ({len(data)} bytes)", flush=True)

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                url,
                content=data,
                headers={
                    "Authorization": f"Bearer {self.service_key}",
                    "apikey": self.service_key,
                    "Content-Type": content_type,
                    "x-upsert": "true",
                },
                timeout=120.0,
            )
            print(f"[SupabaseClient] Upload response: {resp.status_code}", flush=True)
            resp.raise_for_status()
        return f"{self.url}/storage/v1/object/public/{bucket}/{path}"

    async def download_file(self, url: str) -> bytes:
        """Download a file from a URL or relative storage path.

        If the URL doesn't start with http(s), treats it as a relative
        Supabase storage path (e.g. 'scans/QNEXWR/video.mp4') and
        builds the full authenticated download URL.
        """
        if not url.startswith("http://") and not url.startswith("https://"):
            # Relative storage path — split into bucket/path
            parts = url.split("/", 1)
            if len(parts) == 2:
                bucket, path = parts
            else:
                bucket, path = parts[0], ""
            url = f"{self.url}/storage/v1/object/{bucket}/{path}"
            print(f"[SupabaseClient] Download (resolved): {url}", flush=True)

        async with httpx.AsyncClient() as client:
            resp = await client.get(
                url,
                headers={
                    "Authorization": f"Bearer {self.service_key}",
                    "apikey": self.service_key,
                },
                timeout=120.0,
            )
            resp.raise_for_status()
            return resp.content
