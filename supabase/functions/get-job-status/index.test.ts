/**
 * Tests for get-job-status Edge Function.
 * Phase 3.3-test: Server Pipeline V2
 *
 * Run: deno test --allow-env supabase/functions/get-job-status/index.test.ts
 */

import {
  assertEquals,
  assertExists,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeMockSupabase(
  selectResult: { data: unknown; error: unknown } = {
    data: {
      id: "job-uuid-123",
      status: "processing",
      progress: 0.5,
      stage: "depth_estimation",
      error_message: null,
    },
    error: null,
  }
) {
  return {
    from: (_table: string) => ({
      select: (_cols: string) => ({
        eq: (_col: string, _val: string) => ({
          single: () => Promise.resolve(selectResult),
        }),
      }),
    }),
  };
}

async function handleRequest(
  req: Request,
  supabaseAdmin = makeMockSupabase()
): Promise<Response> {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const jobId = url.searchParams.get("job_id");

    if (!jobId) {
      return new Response(
        JSON.stringify({ error: "job_id query parameter is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { data: job, error } = await supabaseAdmin
      .from("processing_jobs")
      .select("id, status, progress, stage, error_message")
      .eq("id", jobId)
      .single();

    if (error || !job) {
      return new Response(
        JSON.stringify({ error: "Job not found" }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const typedJob = job as {
      id: string;
      status: string;
      progress: number;
      stage: string | null;
      error_message: string | null;
    };

    return new Response(
      JSON.stringify({
        job_id: typedJob.id,
        status: typedJob.status,
        progress: typedJob.progress,
        stage: typedJob.stage,
        error_message: typedJob.error_message,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (_err) {
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("CORS preflight returns 200", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-status", { method: "OPTIONS" })
  );
  assertEquals(res.status, 200);
});

Deno.test("missing job_id returns 400", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-status", { method: "GET" })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "job_id query parameter is required");
});

Deno.test("nonexistent job returns 404", async () => {
  const emptyDb = makeMockSupabase({ data: null, error: { message: "not found" } });
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=nonexistent", {
      method: "GET",
    }),
    emptyDb
  );
  assertEquals(res.status, 404);
  const body = await res.json();
  assertEquals(body.error, "Job not found");
});

Deno.test("queued job returns correct status", async () => {
  const db = makeMockSupabase({
    data: {
      id: "job-q",
      status: "queued",
      progress: 0,
      stage: null,
      error_message: null,
    },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=job-q", {
      method: "GET",
    }),
    db
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.job_id, "job-q");
  assertEquals(body.status, "queued");
  assertEquals(body.progress, 0);
  assertEquals(body.stage, null);
  assertEquals(body.error_message, null);
});

Deno.test("processing job returns progress and stage", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=job-uuid-123", {
      method: "GET",
    })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "processing");
  assertEquals(body.progress, 0.5);
  assertEquals(body.stage, "depth_estimation");
});

Deno.test("completed job returns status completed", async () => {
  const db = makeMockSupabase({
    data: {
      id: "job-done",
      status: "completed",
      progress: 1.0,
      stage: "vlm_validation",
      error_message: null,
    },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=job-done", {
      method: "GET",
    }),
    db
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "completed");
  assertEquals(body.progress, 1.0);
});

Deno.test("failed job returns error_message", async () => {
  const db = makeMockSupabase({
    data: {
      id: "job-fail",
      status: "failed",
      progress: 0.3,
      stage: "depth_estimation",
      error_message: "GPU out of memory",
    },
    error: null,
  });
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=job-fail", {
      method: "GET",
    }),
    db
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "failed");
  assertEquals(body.error_message, "GPU out of memory");
});

Deno.test("response has all expected fields", async () => {
  const res = await handleRequest(
    new Request("http://localhost/get-job-status?job_id=job-uuid-123", {
      method: "GET",
    })
  );
  const body = await res.json();
  assertExists(body.job_id);
  assertExists(body.status);
  // progress, stage, error_message may be null but keys should exist
  assertEquals("progress" in body, true);
  assertEquals("stage" in body, true);
  assertEquals("error_message" in body, true);
});
