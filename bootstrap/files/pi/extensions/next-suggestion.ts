/**
 * Ghost suggestion — after each answer, the message you are most likely to send next waits in the
 * input box in grey. Tab (or →) puts it in the box so you can edit it; Enter in an empty box sends
 * it as is; Ctrl+Shift+T opens the whole suggestion in an editor and sends what you confirm.
 * Typing hides it, and the next answer brings a new one.
 *
 * Which model writes the suggestion: ~/.pi/agent/next-suggestion.json, {"provider": "...", "model": "..."}
 * (a small fast model is the point). Without that file the session model is used. Takes effect on /reload.
 *
 * Self-check: bun ~/.pi/agent/next-suggestion.test.ts
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
	CustomEditor,
	getAgentDir,
	type ExtensionAPI,
	type ExtensionContext,
	type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, truncateToWidth, visibleWidth, type EditorTheme, type TUI } from "@earendil-works/pi-tui";

/** pi-tui's FAKE_CURSOR_END, which marks the cell the editor draws the cursor on. Not exported. */
const CURSOR_END = "\x1b_pi:/fc\x07";
export const MAX_TURNS = 6;
export const MAX_CHARS = 1200;
/** The sample is a short line, and a late suggestion is worse than none. */
const MAX_OUTPUT_TOKENS = 32;
const SAMPLE_TIMEOUT_MS = 8_000;
/** Config path override, so the self-check drives a throwaway file instead of the real one. */
export const CONFIG_ENV = "NEXT_SUGGESTION_CONFIG";

const SYSTEM_PROMPT = `You predict what the user of a coding agent types next, from the conversation so far.

- Output only that message: no quotes, no labels, no explanation.
- 2 to 12 words, one line, in the language the user has been writing in; match their style.
- Predict what they would type, not what you think they should do.
- If the assistant asked a question or offered options, answer the way the user would.
- Never use the assistant's voice ("Let me...", "Here's..."), evaluative replies ("looks good"), or questions.
- Never invent files, commands, or facts the conversation does not contain.
- If nothing obvious follows, output nothing.`;

export type Turn = { role: "user" | "assistant"; text: string };
type Config = { provider?: string; model?: string };
type ChatModel = NonNullable<ExtensionContext["model"]>;

/** Text of a message's content: a plain string, or the text parts of a block array. */
export function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const part of content) {
		if (part === null || typeof part !== "object") continue;
		const block = part as { type?: unknown; text?: unknown };
		if (block.type === "text" && typeof block.text === "string") parts.push(block.text);
		else if (block.type === "image") parts.push("[image]");
	}
	return parts.join("\n");
}

/** The last `limit` user/assistant messages, whitespace collapsed and each capped at MAX_CHARS. */
export function recentTurns(
	messages: readonly { role: string; content?: unknown }[],
	limit = MAX_TURNS,
): Turn[] {
	const turns: Turn[] = [];
	for (const message of messages) {
		if (message.role !== "user" && message.role !== "assistant") continue;
		const text = textOf(message.content).replace(/\s+/g, " ").trim();
		if (text.length === 0) continue;
		turns.push({ role: message.role, text: text.length > MAX_CHARS ? `${text.slice(0, MAX_CHARS)}…` : text });
	}
	return turns.slice(-limit);
}

export function transcript(turns: readonly Turn[]): string {
	return turns.map((turn) => `### ${turn.role === "user" ? "User" : "Assistant"}\n${turn.text}`).join("\n\n");
}

/** What one sample produced: a suggestion, a deliberate silence, or a failure the user may want to know about. */
export type Outcome = { kind: "suggestion"; text: string } | { kind: "silent" } | { kind: "failed"; reason: string };

/**
 * The last gate before the composer, so a model that ignores its instructions cannot put prose in the box:
 * one line, 2-12 words, no questions, no evaluative or assistant-voiced replies.
 */
export function filterSuggestion(raw: string): string | undefined {
	const flat = raw.trim().split(/\s+/).filter(Boolean).join(" ");
	if (flat.length === 0 || flat.length >= 100 || /[\n\r\t]/.test(raw)) return undefined;
	if (/[?!`*]/.test(flat) || flat.endsWith(".") || flat.startsWith("- ")) return undefined;
	const lower = flat.toLowerCase();
	if (["done", "no suggestion", "stay silent", "silence"].includes(lower)) return undefined;
	if (lower.startsWith("suggestion:") || lower.startsWith("next prompt:")) return undefined;
	if (wrapped(flat, "(", ")") || wrapped(flat, "[", "]")) return undefined;
	if (wrapped(flat, '"', '"') || wrapped(flat, "'", "'")) return undefined;
	if (["looks good", "thanks", "thank you", "let me", "i'll", "i will", "here's"].some((p) => lower.startsWith(p))) {
		return undefined;
	}
	const words = flat.split(" ").length;
	if (words > 12 || (words < 2 && !["yes", "commit", "push", "continue"].includes(lower))) return undefined;
	return flat;
}

function wrapped(text: string, open: string, close: string): boolean {
	return text.startsWith(open) && text.endsWith(close);
}

/** What a key does while a suggestion waits in an otherwise empty input box. */
export function ghostAction(
	key: "tab" | "right" | "enter" | "other",
	empty: boolean,
	hasGhost: boolean,
): "accept" | "submit" | "pass" {
	if (!empty || !hasGhost) return "pass";
	if (key === "tab" || key === "right") return "accept";
	if (key === "enter") return "submit";
	return "pass";
}

/** Put `ghost` right after the cursor cell on the one line that holds it, still `width` columns wide. */
export function ghostLine(line: string, ghost: string, width: number): string {
	const end = line.indexOf(CURSOR_END);
	if (end === -1) return line;
	const head = line.slice(0, end + CURSOR_END.length);
	const tail = line.slice(end + CURSOR_END.length).replace(/ +$/, "");
	const room = width - visibleWidth(head) - visibleWidth(tail);
	if (room < 4) return line;
	const merged = head + truncateToWidth(ghost, room, "…") + tail;
	return merged + " ".repeat(Math.max(0, width - visibleWidth(merged)));
}

/** `{provider, model}` from the config file. Half-configured or unreadable = an error, no config. */
export function loadConfig(path: string): { config: Config; error?: string } {
	if (!existsSync(path)) return { config: {} };
	let raw: Record<string, unknown>;
	try {
		raw = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
	} catch (err) {
		return { config: {}, error: `${path}: ${err instanceof Error ? err.message : String(err)}` };
	}
	const provider = typeof raw["provider"] === "string" ? raw["provider"] : undefined;
	const model = typeof raw["model"] === "string" ? raw["model"] : undefined;
	if ((provider === undefined) !== (model === undefined)) {
		return { config: {}, error: `${path} needs both "provider" and "model"` };
	}
	return { config: { provider, model } };
}

type Ghost = { text: string; tui?: TUI };

class GhostEditor extends CustomEditor {
	private readonly ghost: Ghost;
	private readonly ctx: ExtensionContext;

	constructor(tui: TUI, theme: EditorTheme, keybindings: KeybindingsManager, ghost: Ghost, ctx: ExtensionContext) {
		super(tui, theme, keybindings, { embedWorkingStatus: true });
		this.ghost = ghost;
		this.ctx = ctx;
	}

	render(width: number): string[] {
		const lines = super.render(width);
		if (this.ghost.text.length === 0 || this.getText().trim().length > 0) return lines;
		const cursor = lines.findIndex((line) => line.includes(CURSOR_END));
		if (cursor === -1) return lines;
		lines[cursor] = ghostLine(lines[cursor]!, this.ctx.ui.theme.fg("muted", this.ghost.text), width);
		return lines;
	}

	handleInput(data: string): void {
		const key = matchesKey(data, "tab")
			? "tab"
			: matchesKey(data, "right")
				? "right"
				: matchesKey(data, "enter")
					? "enter"
					: "other";
		const action = ghostAction(key, this.getText().trim().length === 0, this.ghost.text.length > 0);
		if (action === "pass") {
			super.handleInput(data);
			return;
		}
		const suggestion = this.ghost.text;
		this.ghost.text = "";
		this.setText(suggestion);
		// submitValue is private on Editor, but it is the only path that clears undo/history the way Enter does.
		if (action === "submit") (this as unknown as { submitValue(): void }).submitValue();
		this.ghost.tui?.requestRender();
	}
}

export default function (pi: ExtensionAPI) {
	// One ghost for the life of the process: the editor keeps a reference to it, so a new session must
	// reset its fields rather than replace it.
	const ghost: Ghost = { text: "" };
	let active = false;
	let config: Config = {};
	let warned = false;
	let sampleFailed = false;
	let generating: AbortController | undefined;

	const setGhost = (text: string) => {
		if (!active) return;
		ghost.text = text;
		ghost.tui?.requestRender();
	};

	const warnOnce = (ctx: ExtensionContext, message: string) => {
		if (warned) return;
		warned = true;
		ctx.ui.notify(message, "warning");
	};

	// A broken sample every turn would be noise, so say it once per session.
	const sampleFailedOnce = (ctx: ExtensionContext, reason: string) => {
		if (sampleFailed) return;
		sampleFailed = true;
		ctx.ui.notify(`next-suggestion: suggestion sampling failed (${reason})`, "info");
	};

	const pickModel = (ctx: ExtensionContext): ChatModel | undefined => {
		if (!config.provider || !config.model) return ctx.model;
		const found = ctx.modelRegistry.find(config.provider, config.model);
		if (!found) {
			warnOnce(ctx, `next-suggestion: no model ${config.provider}/${config.model}, using the session model`);
			return ctx.model;
		}
		return found;
	};

	const generate = async (ctx: ExtensionContext, controller: AbortController): Promise<Outcome> => {
		const turns = recentTurns(ctx.sessionManager.buildSessionProjection().messages);
		if (!turns.some((turn) => turn.role === "assistant")) return { kind: "silent" };
		const model = pickModel(ctx);
		if (!model) return { kind: "silent" };
		if (!ctx.modelRegistry.hasConfiguredAuth(model)) {
			warnOnce(ctx, `next-suggestion: no credentials for ${model.provider}/${model.id}`);
			return { kind: "silent" };
		}
		let timedOut = false;
		const deadline = setTimeout(() => {
			timedOut = true;
			controller.abort();
		}, SAMPLE_TIMEOUT_MS);
		try {
			const response = await ctx.modelRegistry.complete(
				model,
				{
					systemPrompt: SYSTEM_PROMPT,
					messages: [
						{ role: "user", content: [{ type: "text", text: transcript(turns) }], timestamp: Date.now() },
					],
				},
				// A fresh, uncached, short sample: it must not touch the session's prompt cache.
				{ signal: controller.signal, cacheRetention: "none", maxTokens: MAX_OUTPUT_TOKENS },
			);
			if (response.stopReason === "error") return { kind: "failed", reason: "the model returned an error" };
			if (response.stopReason === "aborted") return timedOut ? { kind: "failed", reason: "timed out" } : { kind: "silent" };
			const text = filterSuggestion(
				response.content
					.filter((part): part is { type: "text"; text: string } => part.type === "text")
					.map((part) => part.text)
					.join(" "),
			);
			return text === undefined ? { kind: "silent" } : { kind: "suggestion", text };
		} catch (err) {
			if (timedOut) return { kind: "failed", reason: "timed out" };
			if (controller.signal.aborted) return { kind: "silent" };
			return { kind: "failed", reason: err instanceof Error ? err.message : String(err) };
		} finally {
			clearTimeout(deadline);
		}
	};

	pi.registerShortcut(Key.ctrlShift("t"), {
		description: "Show the next-message suggestion",
		handler: async (ctx) => {
			if (!active || ghost.text.length === 0) {
				ctx.ui.notify("No next-message suggestion yet", "info");
				return;
			}
			// The editor shows what the ghost has to truncate; Enter sends the text you confirm.
			const edited = await ctx.ui.editor("Next message", ghost.text);
			if (edited === undefined) return;
			pi.sendUserMessage(edited);
		},
	});

	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		const loaded = loadConfig(
			process.env[CONFIG_ENV] || join(getAgentDir(), "next-suggestion.json"),
		);
		config = loaded.config;
		warned = false;
		sampleFailed = false;
		active = true;
		ghost.text = "";
		if (loaded.error) warnOnce(ctx, `next-suggestion: ${loaded.error}`);
		ctx.ui.setEditorComponent((tui, theme, keybindings) => {
			ghost.tui = tui;
			return new GhostEditor(tui, theme, keybindings, ghost, ctx);
		});
	});

	pi.on("agent_start", () => {
		generating?.abort();
		setGhost("");
	});

	pi.on("input", () => setGhost(""));

	pi.on("agent_settled", (event, ctx) => {
		if (!active || ctx.mode !== "tui" || event.aborted) return;
		generating?.abort();
		const controller = new AbortController();
		generating = controller;
		void generate(ctx, controller)
			.then((outcome) => {
				if (generating !== controller) return; // a newer sample replaced this one
				if (outcome.kind === "suggestion") {
					if (!controller.signal.aborted) setGhost(outcome.text);
				} else if (outcome.kind === "failed") sampleFailedOnce(ctx, outcome.reason);
			})
			.catch((err) => console.error("next-suggestion:", err));
	});

	pi.on("session_shutdown", () => {
		generating?.abort();
		generating = undefined;
		active = false;
		ghost.text = "";
		ghost.tui = undefined;
	});
}
