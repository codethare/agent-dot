/**
 * Writes this pane's pi lifecycle state to ~/.cache/pi-agent-state/<pane>.status,
 * for the tmux status bar (`~/.config/tmux/bin/agentdot.sh`) and the agent list/menu/picker.
 * Also nudges clients that are not looking at this pane when the agent finishes or
 * blocks on a prompt. No-op outside tmux.
 * States: idle | working | done | waiting (blocked on an extension UI prompt).
 * Self-check: bun ~/.config/tmux/test/agent-state.test.ts
 */
import { execFileSync } from "node:child_process";
import { mkdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DIR = process.env.PI_AGENT_STATE_DIR ?? join(homedir(), ".cache", "pi-agent-state");
const pane = process.env.TMUX_PANE?.replace(/^%/, "");

export default function (pi: ExtensionAPI) {
  if (!pane) return;
  const file = join(DIR, `${pane}.status`);
  const self = `%${pane}`;
  let last = "";

  const set = (state: string) => {
    if (state === last) return; // one write per real transition, no per-token I/O
    last = state;
    mkdirSync(DIR, { recursive: true });
    const tmp = `${file}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify({ state, pane: self, ts: Math.floor(Date.now() / 1000) }));
    renameSync(tmp, file); // atomic: tmux reads this file from another process
  };

  const notify = (what: string) => {
    // Status-line nudge to every client currently showing some other pane.
    let clients: string;
    try {
      clients = execFileSync("tmux", ["list-clients", "-F", "#{client_name}\t#{pane_id}"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
    } catch {
      return; // tmux server gone
    }
    const msg = `π ${basename(process.cwd())} ${what}`;
    for (const line of clients.split("\n")) {
      const [client, at] = line.split("\t");
      if (!client || at === self) continue; // you are looking at it
      try {
        execFileSync("tmux", ["display-message", "-c", client, "-d", "5000", msg], { stdio: "ignore" });
      } catch {}
    }
  };

  pi.on("session_start", () => set("idle"));
  pi.on("agent_start", () => set("working"));
  pi.on("agent_settled", () => {
    set("done"); // final: no retry/compaction/queue left
    notify("finished");
  });
  pi.on("ui_prompt_start", () => {
    set("waiting");
    notify("needs your answer");
  });
  pi.on("ui_prompt_end", () => set("working"));
  pi.on("session_shutdown", () => {
    last = "";
    rmSync(file, { force: true });
  });
}
