class_name Edition
extends RefCounted

## Which build this is (issue 247): the free demo (the forest
## pond, free forever) or the full version. One build-time flag: the demo's export preset adds the custom feature
## tag `demo` (Project > Export > Features > Custom); every other build is the full one. Nothing at run time can
## turn a full build into the demo or back, except in a debug build, where `VIBENATURE_EDITION=demo|full` stands in
## for the tag so `just dev` and the snapshots can show either. Tests set `forced`.
##
## The demo's morning card (issue 268) is due once a game day,
## on the day's first arrival (the van driving in, or the app starting with you already at the log); never on the
## first run's welcome arrival, a hand-off, or anything else mid-session.

const DEMO_FEATURE := "demo"
const ENV := "VIBENATURE_EDITION"
## The arrivals that can bring the card (DailyRhythm's events).
const ARRIVALS: Array[String] = ["arrive", "arrive_now"]

## "demo" or "full" overrides everything (tests); "" reads the build.
static var forced := ""


static func is_demo() -> bool:
	if forced != "":
		return forced == "demo"
	if OS.is_debug_build():
		var env := OS.get_environment(ENV)
		if env != "":
			return env == "demo"
	return OS.has_feature(DEMO_FEATURE)


## Whether the day's event `what` brings the card: the demo only, an arrival only, and only on a game day
## (`today`) it has not shown on yet (`shown_day`).
static func morning_card_due(demo: bool, what: String, today: String, shown_day: String) -> bool:
	return demo and ARRIVALS.has(what) and today != "" and today != shown_day
