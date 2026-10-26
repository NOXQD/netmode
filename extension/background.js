// Redirects the video and audio files a page plays to the netmode proxy on
// localhost. The proxy fetches them in short ranges over several fresh
// connections and keeps a buffer ahead of the player.
//
// Safety nets: the redirect exists only while the proxy answers; hosts the
// proxy cannot serve (no range support, refused, private addresses) are listed
// by the proxy and get an allow rule, so the browser talks to them directly.
importScripts("token.js")                      // PORT and TOKEN, written by install.sh

const BASE = "http://127.0.0.1:" + PORT
const REDIRECT_ID = 1
const PRIVATE_ID = 2
const BYPASS_ID = 100

// Sites that stream through their own players and CDNs and gain nothing here.
const SKIP = ["youtube.com", "googlevideo.com", "netflix.com", "nflxvideo.net",
              "twitch.tv", "ttvnw.net", "spotify.com", "scdn.co"]

// Local and private addresses never go through the proxy.
const PRIVATE = "^https://(localhost|127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|169\\.254\\.|[^/:]*\\.(local|lan|internal|home|localdomain))([:/]|$)"

function rules(bypass) {
  const list = [
    {
      id: REDIRECT_ID,
      priority: 1,
      action: { type: "redirect", redirect: { regexSubstitution: BASE + "/" + TOKEN + "/\\1\\2" } },
      condition: {
        regexFilter: "^https://([^/:?#]+)(/.*)$",
        resourceTypes: ["media"],
        excludedRequestDomains: SKIP,
      },
    },
    {
      id: PRIVATE_ID,
      priority: 3,
      action: { type: "allow" },
      condition: { regexFilter: PRIVATE, resourceTypes: ["media"] },
    },
  ]
  bypass.forEach((host, i) => list.push({
    id: BYPASS_ID + i,
    priority: 2,
    action: { type: "allow" },
    condition: { requestDomains: [host], resourceTypes: ["media"] },
  }))
  return list
}

async function getJson(path) {
  try {
    const r = await fetch(BASE + path, { cache: "no-store" })
    return r.ok ? await r.json() : null
  } catch (e) {
    return null
  }
}

async function proxyAlive() {
  try {
    const r = await fetch(BASE + "/ping", { cache: "no-store" })
    return r.ok
  } catch (e) {
    return false
  }
}

async function sync() {
  const alive = await proxyAlive()
  const bypass = alive ? ((await getJson("/bypass")) || []).slice(0, 200) : []
  const old = (await chrome.declarativeNetRequest.getDynamicRules()).map(r => r.id)
  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: old,
    addRules: alive ? rules(bypass) : [],
  })
  chrome.action.setBadgeText({ text: alive ? "on" : "" })
  chrome.action.setBadgeBackgroundColor({ color: "#3a3a3a" })
}

let timer = null
function soon() {
  clearTimeout(timer)
  timer = setTimeout(sync, 300)
}

// A failed request to the proxy means a host to bypass or a proxy that went away.
chrome.webRequest.onCompleted.addListener(d => { if (d.statusCode >= 400) soon() }, { urls: ["http://127.0.0.1/*"] })
chrome.webRequest.onErrorOccurred.addListener(soon, { urls: ["http://127.0.0.1/*"] })

chrome.runtime.onInstalled.addListener(sync)
chrome.runtime.onStartup.addListener(sync)
chrome.alarms.create("sync", { periodInMinutes: 0.5 })
chrome.alarms.onAlarm.addListener(sync)
sync()
