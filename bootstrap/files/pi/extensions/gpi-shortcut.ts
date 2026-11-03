/**
 * Ctrl+: (ctrl+shift+;) opens the pi-ghost overlay, same as typing /gpi.
 * The physical key also arrives as ctrl+; under some terminals, so both are bound.
 */
import { Key, type KeyId } from "@earendil-works/pi-tui";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const KEYS: KeyId[] = [Key.ctrlShift(";"), Key.ctrl(";")];

export default function (pi: ExtensionAPI) {
	for (const key of KEYS) {
		pi.registerShortcut(key, {
			description: "Open ghost pi (/gpi)",
			handler: () => pi.sendUserMessage("/gpi", { expandPromptTemplates: true }),
		});
	}
}
