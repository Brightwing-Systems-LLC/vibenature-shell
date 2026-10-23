class_name LoginItem
extends RefCounted

## Open at login (issue 196). The native extension registers
## the release app as its own Login Item (SMAppService.mainApp) and reports the system's state; this decides what
## the person's setting (`settings.open_at_login`, Config's General switch and the welcome's last step) becomes
## when that state changes, and what to ask for.
##
## The game asks through `WANT_ENV` ("on" / "off") and reads `STATE_ENV`: "enabled", "off", "approval" (switched
## off in System Settings, or waiting there for the person), or "unavailable" (a dev run, a snapshot, before
## macOS 13: nothing to do). The last state seen is kept in the settings (`login_item_seen`), so a change made in
## System Settings while VibeNature was closed is found at the next launch and never undone.

const STATE_ENV := "VIBENATURE_LOGIN_ITEM"
const WANT_ENV := "VIBENATURE_LOGIN_ITEM_WANT"
const KNOWN: Array[String] = ["enabled", "off", "approval"]


## The setting once the system's `state` is seen, given the state seen before (`last_seen`; "" never seen). Only a
## change of state that VibeNature did not ask for moves it: Login Items losing the app while the setting is on
## turns it off, the person adding it there while it is off turns it on. Anything else keeps the setting.
static func reconcile(setting: bool, state: String, last_seen: String) -> bool:
	if not KNOWN.has(state) or not KNOWN.has(last_seen) or state == last_seen:
		return setting
	if setting and last_seen == "enabled":
		return false
	if not setting and state == "enabled":
		return true
	return setting


## What to ask the extension for: the setting, or nothing when there is no Login Item to manage.
static func want(setting: bool, state: String) -> String:
	if not KNOWN.has(state):
		return ""
	return "on" if setting else "off"


## The state worth remembering: only one the system reported.
static func seen(state: String, last_seen: String) -> String:
	return state if KNOWN.has(state) else last_seen
