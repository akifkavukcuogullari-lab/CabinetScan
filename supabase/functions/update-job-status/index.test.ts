/**
 * Tests for update-job-status Edge Function.
 * Phase 3.5-test: Server Pipeline V2
 *
 * Run: deno test --allow-env supabase/functions/update-job-status/index.test.ts
 */

import {
  assertEquals,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const SERVICE_ROLE_KEY = "test-service-role-key-12345";

function makeMockSupabase(
  updateResult: { error: unknown } = { error: null }
) {
  return {
    from: (_table: string) => ({
      update: (_data: unknown) => ({
        eq: (_col: string, _val: string) => Promise.resolve(updateResult),
      }),
    }),
  };
}

async function handleRequest(
  req: Request,
  supabaseAdmin = makeMockSupabase(),
  serviceRoleKey: string | undefined = SERVICE_ROLE_KEY
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
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        {
          status: 405,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Verify service role authorization
    const authHeader = req.headers.get("Authorization");
    if (
      !authHeader ||
      !serviceRoleKey ||
      authHeader !== `Bearer ${serviceRoleKey}`
    ) {
      return new Response(
        JSON.stringify({
          error: "Unauthorized — service role key required",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const body = await req.json();

    if (!body.job_id) {
      return new Response(
        JSON.stringify({ error: "job_id is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Build update object
    const update: Record<string, unknown> = {};
    if (body.status !== undefined) update.status = body.status;
    if (body.progress !== undefined) update.progress = body.progress;
    if (body.stage !== undefined) update.stage = body.stage;
    if (body.error_message !== undefined) update.error_message = body.error_message;
    if (body.worker_id !== undefined) update.worker_id = body.worker_id;

    if (body.status === "processing" && !body.started_at) {
      update.started_at = new Date().toISOString();
    }
    if (body.status === "completed" || body.status === "failed") {
      update.completed_at = new Date().toISOString();
    }

    if (body.measurements_data !== undefined) update.measurements_data = body.measurements_data;
    if (body.floor_plan_png_url !== undefined) update.floor_plan_png_url = body.floor_plan_png_url;
    if (body.measurements_json_url !== undefined) update.measurements_json_url = body.measurements_json_url;
    if (body.scale_confidence !== undefined) update.scale_confidence = body.scale_confidence;
    if (body.validation_passed !== undefined) update.validation_passed = body.validation_passed;
    if (body.validation_issues !== undefined) update.validation_issues = body.validation_issues;
    if (body.processing_time_ms !== undefined) update.processing_time_ms = body.processing_time_ms;
    if (body.stage_timings !== undefined) update.stage_timings = body.stage_timings;

    if (Object.keys(update).length === 0) {
      return new Response(
        JSON.stringify({ error: "No fields to update" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { error: updateError } = await supabaseAdmin
      .from("processing_jobs")
      .update(update)
      .eq("id", body.job_id);

    if (updateError) {
      return new Response(
        JSON.stringify({
          error: "Failed to update job",
          message: (updateError as { message: string }).message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(
      JSON.stringify({ success: true, job_id: body.job_id }),
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

/** Helper to make an authenticated POST request */
function makeAuthRequest(
  body: Record<string, unknown>,
  authKey = SERVICE_ROLE_KEY
): Request {
  return new Request("http://localhost/update-job-status", {
    method: "POST",
    body: JSON.stringify(body),
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${authKey}`,
    },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Deno.test("CORS preflight returns 200", async () => {
  const res = await handleRequest(
    new Request("http://localhost/update-job-status", { method: "OPTIONS" })
  );
  assertEquals(res.status, 200);
});

Deno.test("GET returns 405", async () => {
  const res = await handleRequest(
    new Request("http://localhost/update-job-status", { method: "GET" })
  );
  assertEquals(res.status, 405);
});

// -- Auth tests --

Deno.test("missing auth header returns 401", async () => {
  const res = await handleRequest(
    new Request("http://localhost/update-job-status", {
      method: "POST",
      body: JSON.stringify({ job_id: "abc", status: "processing" }),
      headers: { "Content-Type": "application/json" },
    })
  );
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.error, "Unauthorized — service role key required");
});

Deno.test("wrong auth key returns 401", async () => {
  const res = await handleRequest(
    makeAuthRequest({ job_id: "abc", status: "processing" }, "wrong-key")
  );
  assertEquals(res.status, 401);
});

Deno.test("anon key returns 401", async () => {
  const res = await handleRequest(
    makeAuthRequest({ job_id: "abc" }, "anon-key-not-service-role")
  );
  assertEquals(res.status, 401);
});

// -- Validation tests --

Deno.test("missing job_id returns 400", async () => {
  const res = await handleRequest(
    makeAuthRequest({ status: "processing" })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "job_id is required");
});

Deno.test("no update fields returns 400", async () => {
  const res = await handleRequest(
    makeAuthRequest({ job_id: "abc" })
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "No fields to update");
});

// -- Success tests --

Deno.test("update status to processing returns success", async () => {
  const res = await handleRequest(
    makeAuthRequest({ job_id: "job-123", status: "processing", worker_id: "worker-1" })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
  assertEquals(body.job_id, "job-123");
});

Deno.test("update progress returns success", async () => {
  const res = await handleRequest(
    makeAuthRequest({
      job_id: "job-123",
      progress: 0.5,
      stage: "depth_estimation",
    })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
});

Deno.test("update with results on completion returns success", async () => {
  const res = await handleRequest(
    makeAuthRequest({
      job_id: "job-123",
      status: "completed",
      progress: 1.0,
      measurements_data: { room_name: "Kitchen", total_linear_ft: 18.5 },
      floor_plan_png_url: "https://storage.example.com/plan.png",
      validation_passed: true,
      validation_issues: [],
      processing_time_ms: 45000,
      scale_confidence: "high",
      stage_timings: { frame_extraction: 2000, depth_estimation: 15000 },
    })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
});

Deno.test("update with failed status returns success", async () => {
  const res = await handleRequest(
    makeAuthRequest({
      job_id: "job-456",
      status: "failed",
      error_message: "GPU out of memory",
      stage: "depth_estimation",
    })
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.success, true);
});

Deno.test("database error returns 500", async () => {
  const failingDb = makeMockSupabase({
    error: { message: "connection refused" },
  });
  const res = await handleRequest(
    makeAuthRequest({ job_id: "job-789", status: "processing" }),
    failingDb
  );
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "Failed to update job");
  assertEquals(body.message, "connection refused");
});
