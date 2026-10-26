// Redirects the player's requests for the AnimeLib video servers to the
// netmode proxy on localhost, but only while the proxy answers, so a stopped
// proxy never breaks playback.
const PORT = 18765
const RULE_ID = 1

const rule = {
  id: RULE_ID,
  priority: 1,
  action: { type: "redirect", redirect: { regexSubstitution: "http://127.0.0.1:" + PORT + "/\\1\\2" } },
  condition: {
    regexFilter: "^https://(video[0-9]*\\.cdnlibs\\.org)(/.*)$",
    resourceTypes: ["media", "xmlhttprequest", "other"],
  },
}

async function proxyAlive() {
  try {
    const r = await fetch("http://127.0.0.1:" + PORT + "/ping", { cache: "no-store" })
    return r.ok
  } catch (e) {
    return false
  }
}

async function sync() {
  const on = await proxyAlive()
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: [RULE_ID],
    addRules: on ? [rule] : [],
  })
  chrome.action.setBadgeText({ text: on ? "on" : "" })
  chrome.action.setBadgeBackgroundColor({ color: "#3a3a3a" })
}

chrome.runtime.onInstalled.addListener(sync)
chrome.runtime.onStartup.addListener(sync)
chrome.alarms.create("sync", { periodInMinutes: 0.5 })
chrome.alarms.onAlarm.addListener(sync)
sync()
