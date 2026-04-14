// @naap/types - Public network stats shapes
//
// These shapes are the contract between the naap `/api/v1/public/stats`
// endpoint and external consumers (e.g. the Livepeer Foundation website
// stats page). They are intentionally separate from the internal
// `PerformanceMetrics` / `ConnectorMetrics` shapes so the public surface
// can evolve independently of the DB schema.

export type PublicStatsWindow = '1h' | '24h' | '7d';

/** Point-in-time network-wide summary across all published connectors. */
export interface PublicStatsSummary {
  /** Number of published connectors contributing to this snapshot. */
  connectorCount: number;
  /** Total request count across all connectors in the window. */
  totalRequests: number;
  /** 0..1 error rate across all requests in the window. */
  errorRate: number;
  /** 0..1 success rate across all requests in the window. */
  successRate: number;
  /** Request-weighted mean end-to-end latency in ms. */
  latencyMeanMs: number;
  /** Request-weighted mean upstream latency in ms. */
  upstreamLatencyMeanMs: number;
  /** Request-weighted mean gateway overhead in ms. */
  gatewayOverheadMs: number;
  /** Availability % (0..100) computed from health-check pass ratio. */
  availabilityPercent: number;
  /** Sum of throughput across connectors in requests/minute. */
  throughputRpm: number;
}

/** Per-connector row in the public breakdown. */
export interface PublicStatsConnector {
  slug: string;
  displayName: string;
  totalRequests: number;
  errorRate: number;
  latencyMeanMs: number;
  availabilityPercent: number;
  throughputRpm: number;
}

/** Single bucket on the network-wide time-series. */
export interface PublicStatsHistoryPoint {
  /** ISO-8601 UTC timestamp for the start of the bucket. */
  periodStart: string;
  totalRequests: number;
  errorRate: number;
  latencyMeanMs: number;
  availabilityPercent: number;
  throughputRpm: number;
}

/** Full response shape for `GET /api/v1/public/stats`. */
export interface PublicStatsResponse {
  /** Window the snapshot covers. */
  window: PublicStatsWindow;
  /** ISO-8601 UTC timestamp this payload was computed at (origin time). */
  computedAt: string;
  /** Network-wide aggregated summary. */
  summary: PublicStatsSummary;
  /** Per-connector breakdown, sorted by totalRequests desc. */
  connectors: PublicStatsConnector[];
  /** Network-wide history (hourly buckets for 1h/24h, daily for 7d). */
  history: PublicStatsHistoryPoint[];
}
