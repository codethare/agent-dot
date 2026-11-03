/**
 * Footer — two rows under the editor.
 *   ~/dev/cornice  main                                   deepseek-v4.1-flash · high
 *   ████░░░░░░ 41%  ↑ 101k  ↓ 6.8k  $0.305  CH72%                MCP 4/7
 * Row 1 is the frame: where you are on the left, what you are talking to on the right — the two
 * halves of "what am I doing". Row 2 is the meters: consumption left, capability right. The
 * numbers change every turn, so they live on their own row and row 1 never churns. Each row keeps
 * a fixed left edge and a fixed right edge, so a given fact always sits in the same place.
 * Replaces the built-in 3-row footer, which printed the model and the context percentage twice.
 * Self-check: bun ~/.pi/agent/context-bar.test.ts
 */

import { basename, relative, resolve, sep } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const CELLS = 10;
const GAP = 2;

/** Row 1 left, least-missed first: the path degrades to its basename, then goes. */
const FRAME_DROPS = ["path", "pathAll"] as const;
/** Row 2 left, least-missed first. The percentage never drops; the MCP chip is last out. */
const METER_DROPS = ["cache", "cost", "output", "bar", "input", "mcp"] as const;

type Totals = { input: number; output: number; cost: number; cacheHit: number | null };
type UsageLike = { input: number; output: number; cacheRead: number; cacheWrite: number; cost: { total: number } };

export function bar(percent: number | null, cells = CELLS): string {
	if (percent === null) return "░".repeat(cells);
	const filled = Math.max(0, Math.min(cells, Math.round((percent / 100) * cells)));
	return "█".repeat(filled) + "░".repeat(cells - filled);
}

export function formatTokens(count: number): string {
	if (count < 1000) return `${count}`;
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

/** `~/dev/cornice` for a path under home, the full path otherwise. */
function shortPath(cwd: string): string {
	const home = process.env.HOME;
	if (!home) return cwd;
	const rel = relative(resolve(home), resolve(cwd));
	const inside = rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !rel.startsWith(sep));
	return inside ? (rel === "" ? "~" : `~${sep}${rel}`) : cwd;
}

/** One row: left cluster flush left, right cluster flush right, the gap between them flexes. */
function row(left: string, right: string, width: number): string {
	const rightWidth = visibleWidth(right);
	let l = left;
	if (visibleWidth(l) + GAP + rightWidth > width) {
		l = truncateToWidth(l, Math.max(0, width - GAP - rightWidth), "…");
	}
	const gap = Math.max(GAP, width - visibleWidth(l) - rightWidth);
	return truncateToWidth(l + " ".repeat(gap) + right, width, "…");
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return; // setFooter exists in TUI mode only
		ctx.ui.setFooter((tui, theme, footerData) => {
			const off = footerData.onBranchChange(() => tui.requestRender());
			let totals: Totals | null = null;
			let totalsKey = "";

			// Session totals scan every entry and this renders on every frame. Entries are
			// append-only, so entry count plus leaf id is a sufficient key; context usage and
			// the branch are read live instead.
			const readTotals = (): Totals => {
				const entries = ctx.sessionManager.getEntries();
				const key = `${entries.length}|${ctx.sessionManager.getLeafId()}`;
				if (totals && totalsKey === key) return totals;
				const t: Totals = { input: 0, output: 0, cost: 0, cacheHit: null };
				const add = (u: UsageLike | undefined | null) => {
					if (!u) return;
					t.input += u.input;
					t.output += u.output;
					t.cost += u.cost.total;
				};
				for (const e of entries) {
					if (e.type === "usage") add(e.usage);
					else if (e.type === "message" && e.message.role === "assistant") {
						add(e.message.usage);
						const u = e.message.usage;
						const prompt = u.input + u.cacheRead + u.cacheWrite;
						if (prompt > 0) t.cacheHit = (u.cacheRead / prompt) * 100;
					} else if (e.type === "message" && e.message.role === "toolResult") add(e.message.usage);
					else if ((e.type === "branch_summary" || e.type === "compaction") && e.usage) add(e.usage);
				}
				totals = t;
				totalsKey = key;
				return t;
			};

			return {
				dispose: off,
				invalidate() {},
				render(width: number): string[] {
					const t = readTotals();
					const usage = ctx.getContextUsage();
					const percent = usage?.percent ?? null;
					const percentText = (percent === null ? "?" : `${Math.round(percent)}%`).padStart(3);
					const pctColor: "error" | "warning" | "muted" =
						(percent ?? 0) > 90 ? "error" : (percent ?? 0) > 70 ? "warning" : "muted";
					const sessionName = ctx.sessionManager.getSessionName();
					const branch = footerData.getGitBranch();
					const model = ctx.model?.id.split("/").pop() ?? "no-model";
					const level = ctx.model?.reasoning ? ctx.thinkingLevel : undefined;
					// pi-mcp-adapter owns this string, its colour, its verbosity setting and its off switch.
					const mcp = footerData.getExtensionStatuses().get("mcp");

					// Row 1 — frame: location left, model right.
					const frameRight = theme.fg("text", model) + (level ? theme.fg("dim", ` · ${level}`) : "");
					let frame = "";
					for (let i = 0; i <= FRAME_DROPS.length; i++) {
						const drop = new Set<string>(FRAME_DROPS.slice(0, i));
						const parts: string[] = [];
						if (!drop.has("pathAll")) {
							const p = drop.has("path") ? basename(ctx.cwd) : shortPath(ctx.cwd);
							parts.push(theme.fg("dim", sessionName ? `${p} · ${sessionName}` : p));
						}
						if (branch) parts.push(theme.fg("muted", branch));
						frame = parts.join("  ");
						if (visibleWidth(frame) + GAP + visibleWidth(frameRight) <= width) break;
					}

					// Row 2 — meters left, capability right.
					const num = (glyph: string, v: number) => theme.fg("muted", `${glyph} ${formatTokens(v).padStart(4)}`);
					let meters = "";
					let capability = "";
					for (let i = 0; i <= METER_DROPS.length; i++) {
						const drop = new Set<string>(METER_DROPS.slice(0, i));
						const parts: string[] = [];
						// The block gauge is decoration; the percentage is the fact and never drops.
						parts.push((drop.has("bar") ? "" : theme.fg("dim", `${bar(percent)} `)) + theme.fg(pctColor, percentText));
						if (!drop.has("input")) parts.push(num("↑", t.input));
						if (!drop.has("output")) parts.push(num("↓", t.output));
						if (!drop.has("cost")) parts.push(theme.fg("muted", `$${t.cost.toFixed(3)}`));
						if (!drop.has("cache") && t.cacheHit !== null) parts.push(theme.fg("muted", `CH${t.cacheHit.toFixed(0)}%`));
						meters = parts.join("  ");
						capability = drop.has("mcp") ? "" : (mcp ?? "");
						if (visibleWidth(meters) + GAP + visibleWidth(capability) <= width) break;
					}

					return [row(frame, frameRight, width), row(meters, capability, width)];
				},
			};
		});
	});
}
