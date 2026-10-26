.pragma library

function parse(text) {
  try { return JSON.parse(text) } catch (e) { return null }
}

function ms(v) {
  if (v === null || v === undefined) return "—"
  return (v >= 100 ? Math.round(v) : Math.round(v * 10) / 10) + " мс"
}

function ping(p) {
  if (!p || p.avg === undefined) return "—"
  return ms(p.avg) + "  ±" + (Math.round(p.jitter * 10) / 10) + (p.loss > 0 ? "  потери " + p.loss + "%" : "")
}

function mbit(v) {
  if (v === null || v === undefined) return "—"
  return (v >= 100 ? Math.round(v) : Math.round(v * 10) / 10) + " Мбит/с"
}

// Quality of the line in one word, from latency, jitter and loss.
function quality(p) {
  if (!p || p.avg === undefined) return "нет сети"
  if (p.loss >= 5 || p.avg > 250) return "плохо"
  if (p.jitter > 25 || p.avg > 120) return "нестабильно"
  if (p.jitter > 10 || p.avg > 60) return "нормально"
  return "отлично"
}

// "1.1.1.1#cloudflare-dns.com" -> "cloudflare-dns.com  1.1.1.1"
function dnsName(d) {
  if (!d) return "—"
  var i = d.indexOf("#")
  return i < 0 ? d : d.slice(i + 1) + "  " + d.slice(0, i)
}

function stats(snap, keepalive) {
  if (!snap) return []
  var rows = []
  var w = snap.wifi
  if (w && w.connected)
    rows.push({ k: "Wi-Fi", v: (w.ssid || "") + "  " + w.signal + " дБм  " + Math.round(w.rx) + "/" + Math.round(w.tx) + " Мбит/с" })
  rows.push({ k: "Роутер", v: ping(snap.gateway) })
  rows.push({ k: "Интернет", v: ping(snap.internet) + "  · " + quality(snap.internet) })
  rows.push({ k: "DNS", v: dnsName(snap.dns) })
  rows.push({ k: "Ускоритель", v: snap.proxy ? "работает  ·  отдано " + Math.round(snap.proxy.served / 1e6) + " МБ" : "не запущен" })
  if (keepalive) rows.push({ k: "Wi-Fi", v: "не засыпает  ·  100 пак/с" })
  return rows
}

function benchRows(b) {
  if (!b) return []
  var rows = []
  rows.push({ k: "Скачивание", v: Math.round(b.down_1) + " / " + mbit(b.down_4) + "  (1 и 4 потока)" })
  rows.push({ k: "Под нагрузкой", v: ping(b.loaded) })
  rows.push({ k: "DNS-запрос", v: "кэш " + ms(b.dns.cached_ms) + "  ·  без кэша " + ms(b.dns.miss_ms) })
  return rows
}
