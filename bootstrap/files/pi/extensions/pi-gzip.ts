/**
 * Compress model request bodies on the way out, so a relay that is slow to read a large
 * body sends the first token sooner.
 *
 * On by default for every provider. Per provider in models.json:
 *   "compat": { "gzip": false }     opt out
 *   "compat": { "encoding": "br" }  br | zstd instead of gzip
 * Env: PI_GZIP=0 off; PI_GZIP_MIN_BYTES (default 1024); PI_GZIP_DEBUG=1 logs to stderr.
 *
 * The interceptor sits at the fetch layer, so it covers every fetch-based API: OpenAI
 * chat/responses/Azure/Codex, Anthropic, Mistral, Google, pi-messages, and any
 * OpenAI-compatible relay. Bedrock uses the AWS SDK's node:http transport and WebSocket
 * transport skips fetch; neither is covered.
 * Self-check: bun ~/.pi/agent/pi-gzip.test.ts
 */

import * as zlib from "node:zlib";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export type Encoding = "gzip" | "br" | "zstd";

/** Only the two compat keys this extension reads; models.json keeps its other keys. */
export interface GzipCompat {
	gzip?: unknown;
	encoding?: unknown;
}

/** A registry model, structurally: everything else about it is ignored here. */
export interface EncodableModel {
	baseUrl?: string | undefined;
	compat?: unknown;
}

export interface State {
	off: boolean;
	/** Request host -> encoding, built from the live model registry at session_start. */
	hosts: Map<string, Encoding>;
	minBytes: number;
	debug: boolean;
}

/** Bodies smaller than a packet save nothing and gzip adds bytes. */
export const DEFAULT_MIN_BYTES = 1024;

export const state: State = { off: true, hosts: new Map(), minBytes: DEFAULT_MIN_BYTES, debug: false };

const ALIASES: Record<string, Encoding> = {
	gzip: "gzip",
	br: "br",
	brotli: "br",
	zstd: "zstd",
	zstandard: "zstd",
};

/** Missing, unknown, empty and non-string values fall back to gzip; zstd needs the runtime compressor. */
export function normalizeEncoding(value: unknown): Encoding {
	const named = typeof value === "string" ? ALIASES[value.trim().toLowerCase()] : undefined;
	if (named === "zstd" && typeof zlib.zstdCompressSync !== "function") return "gzip";
	return named ?? "gzip";
}

/** The encoding for one provider's compat, or null when that provider opted out. */
export function providerEncoding(compat: unknown): Encoding | null {
	const keys = (compat ?? {}) as GzipCompat;
	// gzip:false wins over encoding: the provider asked for no compression at all.
	return keys.gzip === false ? null : normalizeEncoding(keys.encoding);
}

export function hostOf(url: string): string | undefined {
	try {
		return new URL(url).host;
	} catch {
		return undefined;
	}
}

export function hostMap(models: readonly EncodableModel[]): Map<string, Encoding> {
	const hosts = new Map<string, Encoding>();
	for (const model of models) {
		if (!model.baseUrl) continue;
		const encoding = providerEncoding(model.compat);
		const host = encoding === null ? undefined : hostOf(model.baseUrl);
		if (host !== undefined) hosts.set(host, encoding);
	}
	return hosts;
}

export function minBytes(env: Record<string, string | undefined>): number {
	const raw = env.PI_GZIP_MIN_BYTES;
	if (raw === undefined || raw.trim() === "") return DEFAULT_MIN_BYTES;
	const value = Number(raw);
	return Number.isFinite(value) && value >= 0 ? Math.floor(value) : DEFAULT_MIN_BYTES;
}

export function compressBytes(bytes: Uint8Array, encoding: Encoding): Uint8Array {
	if (encoding === "br") return zlib.brotliCompressSync(bytes);
	if (encoding === "zstd") return zlib.zstdCompressSync(bytes);
	return zlib.gzipSync(bytes);
}

function requestUrl(input: RequestInfo | URL): string {
	if (typeof input === "string") return input;
	return input instanceof URL ? input.href : input.url;
}

/** The init to send instead, or undefined when this request is forwarded untouched. */
export function rewrite(input: RequestInfo | URL, init: RequestInit | undefined, s: State): RequestInit | undefined {
	if (s.off || typeof init?.body !== "string") return undefined;
	const method = init.method ?? (input instanceof Request ? input.method : "");
	if (method.toUpperCase() !== "POST") return undefined;
	const url = requestUrl(input);
	const encoding = s.hosts.get(hostOf(url) ?? "");
	if (encoding === undefined) return undefined;
	const headers = new Headers(init.headers);
	// Already encoded by the caller or an earlier interceptor: leave it alone.
	if (headers.has("content-encoding")) return undefined;
	const bytes = new TextEncoder().encode(init.body);
	if (bytes.byteLength < s.minBytes) return undefined;
	const body = compressBytes(bytes, encoding);
	headers.set("content-encoding", encoding);
	// Stale once the body changes; let the HTTP stack recompute it.
	headers.delete("content-length");
	if (s.debug) console.error(`[pi-gzip] ${encoding} ${bytes.byteLength} -> ${body.byteLength} B ${url}`);
	return { ...init, body, headers };
}

/** Process-wide, once: re-reading `state` per request keeps the map rebuild cheap. */
export function installFetch(): void {
	const original = globalThis.fetch as typeof fetch & { piGzip?: boolean };
	if (original.piGzip) return;
	const wrapped = ((input: RequestInfo | URL, init?: RequestInit) => {
		const next = rewrite(input, init, state);
		return next === undefined ? original(input, init) : original(input, next);
	}) as typeof fetch & { piGzip?: boolean };
	wrapped.piGzip = true;
	globalThis.fetch = wrapped;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		state.off = process.env.PI_GZIP === "0";
		state.debug = process.env.PI_GZIP_DEBUG === "1";
		state.minBytes = minBytes(process.env);
		state.hosts = hostMap(ctx.modelRegistry.getAll());
		installFetch();
		if (state.debug) {
			console.error(`[pi-gzip] ${state.off ? "disabled" : `${state.hosts.size} hosts`}, min ${state.minBytes} B`);
		}
	});
}
