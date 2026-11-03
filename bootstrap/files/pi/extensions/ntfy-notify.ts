/**
 * Broadcast to ntfy when a Pi run has settled and the session is waiting for input.
 * Config: ~/.pi/agent/pi-ntfy.json ({"topic", "server"}), overridden by env NTFY_TOPIC / NTFY_SERVER.
 * Title = session name, body = last assistant message (head-clipped for ntfy's 4K message limit).
 * Self-check: bun ~/.pi/agent/ntfy-notify.test.ts
 */

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

/** ntfy.sh default `message-size-limit` is 4K bytes; CJK is 3 bytes/char, so stay well under. */
export const BODY_LIMIT = 1200;
/** ntfy `Title` limit is 250 bytes. */
export const TITLE_LIMIT = 120;

const FALLBACK_BODY = "run settled, waiting for input";

/** Keep the head, mark the cut. */
export function clip(text: string, limit: number): string {
	return text.length > limit ? `${text.slice(0, limit)}...` : text;
}

export interface SessionSummary {
	name?: string | undefined;
	text?: string | undefined;
}

export function buildMessage(
	cwd: string,
	env: Record<string, string | undefined>,
	session: SessionSummary = {},
) {
	const topic = env.NTFY_TOPIC;
	if (!topic) return null;
	const server = (env.NTFY_SERVER || "https://ntfy.sh").replace(/\/+$/, "");
	const name = (session.name || basename(cwd)).replace(/\s+/g, " ").trim();
	const text = session.text?.trim() ?? "";
	return {
		url: `${server}/${topic}`,
		headers: { Title: `pi: ${clip(name, TITLE_LIMIT)}` },
		body: clip(text.length > 0 ? text : FALLBACK_BODY, BODY_LIMIT),
	};
}

/** Text of the last assistant message in the settled run, from the compaction-aware context. */
export function conversationText(ctx: ExtensionContext): string {
	const messages = ctx.sessionManager.buildSessionProjection().messages;
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (message === undefined || message.role !== "assistant") continue;
		const text = message.content
			.filter((part) => part.type === "text")
			.map((part) => part.text)
			.join("\n")
			.trim();
		if (text.length > 0) return text;
	}
	return "";
}

/** `{topic, server}` from the config file, as NTFY_* names. Missing or broken file = no config. */
export function configFileEnv(path: string): Record<string, string | undefined> {
	const env: Record<string, string | undefined> = {};
	let values: Record<string, unknown>;
	try {
		values = JSON.parse(readFileSync(path, "utf8"));
	} catch {
		return env;
	}
	if (values !== null && typeof values === "object") {
		if (typeof values["topic"] === "string") env["NTFY_TOPIC"] = values["topic"] as string;
		if (typeof values["server"] === "string") env["NTFY_SERVER"] = values["server"] as string;
	}
	return env;
}

export default function (pi: ExtensionAPI) {
	pi.on("agent_settled", (_event, ctx: ExtensionContext) => {
		const path = process.env.NTFY_CONFIG_FILE || join(homedir(), ".pi/agent/pi-ntfy.json");
		const msg = buildMessage(ctx.cwd, { ...configFileEnv(path), ...process.env }, {
			name: ctx.sessionManager.getSessionName(),
			text: conversationText(ctx),
		});
		if (!msg) return;
		void fetch(msg.url, { method: "POST", headers: msg.headers, body: msg.body }).catch(() => {});
	});
}
