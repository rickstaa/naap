/**
 * Public Network Stats
 * GET /api/v1/public/stats?window=24h
 *
 * Unauthenticated, CORS-open, edge-cacheable snapshot of network-wide
 * metrics across all published service connectors. Designed for the
 * Livepeer Foundation website stats page and other external consumers.
 *
 * Reads pre-aggregated `ConnectorMetrics` rows (populated by the cron at
 * `/api/v1/gw/admin/metrics/aggregate`) — this route does not trigger any
 * upstream fetches or live aggregation. It is a cached read of derived data
 * that already exists in the naap Postgres.
 *
 * Response shape is defined in `@naap/types` (`PublicStatsResponse`).
 */

export const runtime = 'nodejs';
export const maxDuration = 30;

import { NextRequest, NextResponse } from 'next/server';
import type {
  PublicStatsConnector,
  PublicStatsHistoryPoint,
  PublicStatsResponse,
  PublicStatsSummary,
  PublicStatsWindow,
} from '@naap/types';
import { prisma } from '@/lib/db';
import { bffStaleWhileRevalidate } from '@/lib/api/bff-swr';
import { dashboardRouteCacheControl } from '@/lib/facade/cache';

/** Max connectors returned in the per-connector breakdown. */
const MAX_CONNECTORS = 25;

/** Origin cache TTL for the public snapshot — matches stats page freshness needs. */
const PUBLIC_STATS_TTL_MS = 60 * 1000;

type ConnectorMetricsRow = {
  connectorId: string;
  totalRequests: number;
  errorCount: number;
  latencyMeanMs: number;
  upstreamLatencyMeanMs: number;
  gatewayOverheadMs: number;
  availabilityPercent: number;
  healthCheckCount: number;
  healthChecksPassed: number;
  throughputRpm: number;
  periodStart: Date;
};

function parseWindow(raw: string | null): PublicStatsWindow {
  if (raw === '1h' || raw === '24h' || raw === '7d') return raw;
  return '24h';
}

function buildSummary(rows: ConnectorMetricsRow[], connectorCount: number): PublicStatsSummary {
  const totalRequests = rows.reduce((s, r) => s + r.totalRequests, 0);
  const errorCount = rows.reduce((s, r) => s + r.errorCount, 0);
  const errorRate = totalRequests > 0 ? errorCount / totalRequests : 0;

  const weightedAvg = (field: 'latencyMeanMs' | 'upstreamLatencyMeanMs' | 'gatewayOverheadMs'): number => {
    if (totalRequests === 0) return 0;
    return rows.reduce((s, r) => s + r[field] * r.totalRequests, 0) / totalRequests;
  };

  const totalHC = rows.reduce((s, r) => s + r.healthCheckCount, 0);
  const passedHC = rows.reduce((s, r) => s + r.healthChecksPassed, 0);
  const availabilityPercent = totalHC > 0 ? (passedHC / totalHC) * 100 : 100;

  const throughputRpm = rows.reduce((s, r) => s + r.throughputRpm, 0);

  return {
    connectorCount,
    totalRequests,
    errorRate: round(errorRate, 4),
    successRate: round(1 - errorRate, 4),
    latencyMeanMs: round(weightedAvg('latencyMeanMs'), 2),
    upstreamLatencyMeanMs: round(weightedAvg('upstreamLatencyMeanMs'), 2),
    gatewayOverheadMs: round(weightedAvg('gatewayOverheadMs'), 2),
    availabilityPercent: round(availabilityPercent, 2),
    throughputRpm: round(throughputRpm, 2),
  };
}

function buildHistory(rows: ConnectorMetricsRow[]): PublicStatsHistoryPoint[] {
  const byBucket = new Map<string, ConnectorMetricsRow[]>();
  for (const r of rows) {
    const key = r.periodStart.toISOString();
    const arr = byBucket.get(key);
    if (arr) arr.push(r);
    else byBucket.set(key, [r]);
  }

  const points: PublicStatsHistoryPoint[] = [];
  for (const [periodStart, bucketRows] of byBucket) {
    const totalRequests = bucketRows.reduce((s, r) => s + r.totalRequests, 0);
    const errorCount = bucketRows.reduce((s, r) => s + r.errorCount, 0);
    const errorRate = totalRequests > 0 ? errorCount / totalRequests : 0;

    const latencyMeanMs = totalRequests > 0
      ? bucketRows.reduce((s, r) => s + r.latencyMeanMs * r.totalRequests, 0) / totalRequests
      : 0;

    const totalHC = bucketRows.reduce((s, r) => s + r.healthCheckCount, 0);
    const passedHC = bucketRows.reduce((s, r) => s + r.healthChecksPassed, 0);
    const availabilityPercent = totalHC > 0 ? (passedHC / totalHC) * 100 : 100;

    const throughputRpm = bucketRows.reduce((s, r) => s + r.throughputRpm, 0);

    points.push({
      periodStart,
      totalRequests,
      errorRate: round(errorRate, 4),
      latencyMeanMs: round(latencyMeanMs, 2),
      availabilityPercent: round(availabilityPercent, 2),
      throughputRpm: round(throughputRpm, 2),
    });
  }

  points.sort((a, b) => a.periodStart.localeCompare(b.periodStart));
  return points;
}

function buildConnectorBreakdown(
  rows: ConnectorMetricsRow[],
  connectorMeta: Map<string, { slug: string; displayName: string }>
): PublicStatsConnector[] {
  const byConnector = new Map<string, ConnectorMetricsRow[]>();
  for (const r of rows) {
    const arr = byConnector.get(r.connectorId);
    if (arr) arr.push(r);
    else byConnector.set(r.connectorId, [r]);
  }

  const results: PublicStatsConnector[] = [];
  for (const [connectorId, connectorRows] of byConnector) {
    const meta = connectorMeta.get(connectorId);
    if (!meta) continue;

    const totalRequests = connectorRows.reduce((s, r) => s + r.totalRequests, 0);
    const errorCount = connectorRows.reduce((s, r) => s + r.errorCount, 0);
    const errorRate = totalRequests > 0 ? errorCount / totalRequests : 0;

    const latencyMeanMs = totalRequests > 0
      ? connectorRows.reduce((s, r) => s + r.latencyMeanMs * r.totalRequests, 0) / totalRequests
      : 0;

    const totalHC = connectorRows.reduce((s, r) => s + r.healthCheckCount, 0);
    const passedHC = connectorRows.reduce((s, r) => s + r.healthChecksPassed, 0);
    const availabilityPercent = totalHC > 0 ? (passedHC / totalHC) * 100 : 100;

    const throughputRpm = connectorRows.length > 0
      ? connectorRows.reduce((s, r) => s + r.throughputRpm, 0) / connectorRows.length
      : 0;

    results.push({
      slug: meta.slug,
      displayName: meta.displayName,
      totalRequests,
      errorRate: round(errorRate, 4),
      latencyMeanMs: round(latencyMeanMs, 2),
      availabilityPercent: round(availabilityPercent, 2),
      throughputRpm: round(throughputRpm, 2),
    });
  }

  results.sort((a, b) => b.totalRequests - a.totalRequests);
  return results.slice(0, MAX_CONNECTORS);
}

function round(n: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(n * f) / f;
}

async function computeSnapshot(window: PublicStatsWindow): Promise<PublicStatsResponse> {
  const connectors = await prisma.serviceConnector.findMany({
    where: { status: 'published', visibility: 'public' },
    select: { id: true, slug: true, displayName: true },
  });

  const connectorMeta = new Map<string, { slug: string; displayName: string }>();
  for (const c of connectors) connectorMeta.set(c.id, { slug: c.slug, displayName: c.displayName });

  if (connectors.length === 0) {
    return {
      window,
      computedAt: new Date().toISOString(),
      summary: buildSummary([], 0),
      connectors: [],
      history: [],
    };
  }

  const period = window === '7d' ? 'daily' : 'hourly';
  const since = new Date();
  if (window === '1h') since.setUTCHours(since.getUTCHours() - 1);
  else if (window === '24h') since.setUTCHours(since.getUTCHours() - 24);
  else since.setUTCDate(since.getUTCDate() - 7);

  const connectorIds: string[] = connectors.map((c: { id: string }) => c.id);

  const rows = await prisma.connectorMetrics.findMany({
    where: {
      connectorId: { in: connectorIds },
      period,
      periodStart: { gte: since },
    },
    select: {
      connectorId: true,
      totalRequests: true,
      errorCount: true,
      latencyMeanMs: true,
      upstreamLatencyMeanMs: true,
      gatewayOverheadMs: true,
      availabilityPercent: true,
      healthCheckCount: true,
      healthChecksPassed: true,
      throughputRpm: true,
      periodStart: true,
    },
  });

  return {
    window,
    computedAt: new Date().toISOString(),
    summary: buildSummary(rows, connectors.length),
    connectors: buildConnectorBreakdown(rows, connectorMeta),
    history: buildHistory(rows),
  };
}

function corsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type',
    'Access-Control-Max-Age': '86400',
  };
}

export async function OPTIONS(): Promise<NextResponse> {
  return new NextResponse(null, { status: 204, headers: corsHeaders() });
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const window = parseWindow(request.nextUrl.searchParams.get('window'));
  const cacheKey = `public-stats:${window}`;

  try {
    const { data, cache } = await bffStaleWhileRevalidate(
      cacheKey,
      () => computeSnapshot(window),
      'public-stats'
    );

    const res = NextResponse.json(data);
    res.headers.set('Cache-Control', dashboardRouteCacheControl(PUBLIC_STATS_TTL_MS));
    res.headers.set('X-Cache', cache);
    for (const [k, v] of Object.entries(corsHeaders())) res.headers.set(k, v);
    return res;
  } catch (err) {
    console.error('[public/stats] error:', err);
    return NextResponse.json(
      { error: { code: 'SERVICE_UNAVAILABLE', message: 'Public stats are unavailable' } },
      {
        status: 503,
        headers: {
          'Cache-Control': 'public, max-age=0, s-maxage=5, stale-while-revalidate=0',
          ...corsHeaders(),
        },
      }
    );
  }
}
