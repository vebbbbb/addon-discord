// Package navtokdiscord exposes the addon files so the companion can install them (go:embed
// cannot reach outside the module directory, hence this file lives at the repository root).
package navtokdiscord

import "embed"

// AddonFS contains the folder addon/NavtokDiscord exactly as it must appear in Interface\AddOns.
//
//go:embed addon/NavtokDiscord
var AddonFS embed.FS

// AddonRoot is the path of the addon folder inside AddonFS.
const AddonRoot = "addon/NavtokDiscord"
