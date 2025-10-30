#!/usr/bin/env bash
set -euo pipefail

# Simple installer script for adding Web UI to MarzneshinIpLimit
# Usage when hosted on GitHub raw:
#   curl -sL https://github.com/<you>/MarzneshinIpLimit/raw/main/script.sh | sudo bash -s -- install
# or run locally: sudo bash script.sh install

REPO_ORIG="https://github.com/muttehitler/MarzneshinIpLimit.git"
# If you forked and want to use your fork, set REPO_FORK to "https://github.com/<you>/MarzneshinIpLimit.git"
# REPO_FORK=""
REPO="${REPO_FORK:-$REPO_ORIG}"

DIR="${HOME}/MarzneshinIpLimit"
WEB_FILE="web_server.py"
WEB_DIR="$DIR/web"
REQ_FILE="$DIR/requirements.txt"
COMPOSE_OVERRIDE="$DIR/docker-compose.web.yml"

function die(){ echo >&2 "ERROR: $*"; exit 1; }

echo "Arg1: ${1:-none}"
MODE="${1:-install}"

if [[ "$MODE" != "install" ]]; then
  echo "Unknown mode '$MODE'. Only 'install' is supported."
  exit 1
fi

echo "Step 1: clone or update repo to $DIR"
if [ -d "$DIR/.git" ]; then
  echo "Repo exists -> pulling latest..."
  git -C "$DIR" pull --rebase || true
else
  git clone "$REPO" "$DIR"
fi

echo "Step 2: create web folder and write web_server.py & index.html"
mkdir -p "$WEB_DIR"

cat > "$DIR/$WEB_FILE" <<'PY'
#!/usr/bin/env python3
# web_server.py
import os, json
from pathlib import Path
from flask import Flask, jsonify, render_template, send_from_directory

app = Flask(__name__, static_folder="web/static", template_folder="web")
REPO_ROOT = Path(__file__).parent.resolve()
DETECTED_JSON = REPO_ROOT / "detected_users.json"

def read_from_detected_json():
    if not DETECTED_JSON.exists():
        return None
    try:
        data = json.loads(DETECTED_JSON.read_text(encoding="utf-8"))
    except Exception:
        return None
    out = []
    if isinstance(data, list):
        for item in data:
            ip = item.get("ip") or item.get("client_ip") or item.get("ip_address")
            cfg = item.get("config") or item.get("username") or item.get("user")
            cnt = item.get("count") or item.get("connections") or item.get("active", 0)
            out.append({"ip": ip, "config": cfg, "count": int(cnt or 0)})
        return out
    if isinstance(data, dict):
        for user, v in data.items():
            try:
                if isinstance(v, dict):
                    for ip, cnt in v.items():
                        out.append({"ip": ip, "config": user, "count": int(cnt or 0)})
                elif isinstance(v, list):
                    for entry in v:
                        ip = entry.get("ip") if isinstance(entry, dict) else entry
                        out.append({"ip": ip, "config": user, "count": 1})
            except Exception:
                continue
        if out:
            return out
    return None

def try_import_marz():
    try:
        import marzneshiniplimit as m
    except Exception:
        return None
    candidates = ["detected_users", "get_detected_users", "get_ip_stats", "detected_users_data",
                  "get_active_ips", "detected_users_json"]
    for name in candidates:
        try:
            attr = getattr(m, name, None)
            if callable(attr):
                res = attr()
                if isinstance(res, list):
                    return res
                if isinstance(res, dict):
                    out = []
                    for user, ips in res.items():
                        if isinstance(ips, dict):
                            for ip, cnt in ips.items():
                                out.append({"ip": ip, "config": user, "count": int(cnt or 0)})
                    if out:
                        return out
            elif isinstance(attr, (list, dict)):
                if isinstance(attr, list):
                    return attr
                if isinstance(attr, dict):
                    out = []
                    for user, ips in attr.items():
                        if isinstance(ips, dict):
                            for ip, cnt in ips.items():
                                out.append({"ip": ip, "config": user, "count": int(cnt or 0)})
                    if out:
                        return out
        except Exception:
            continue
    return None

def get_ip_stats():
    res = read_from_detected_json()
    if res:
        return res
    res = try_import_marz()
    if res:
        return res
    import requests
    candidates = [
        "http://127.0.0.1:6284/ips",
        "http://127.0.0.1:6284/api/ips",
        "http://127.0.0.1:6284/api/v1/ips"
    ]
    for url in candidates:
        try:
            r = requests.get(url, timeout=1.5)
            if r.status_code == 200:
                data = r.json()
                if isinstance(data, list):
                    return data
        except Exception:
            continue
    return []

from flask import request

@app.route("/api/ips")
def api_ips():
    data = get_ip_stats()
    out = []
    for item in data:
        if not item:
            continue
        ip = item.get("ip") if isinstance(item, dict) else None
        cfg = item.get("config") if isinstance(item, dict) else None
        cnt = item.get("count") if isinstance(item, dict) else None
        if not ip:
            ip = item.get("client_ip") if isinstance(item, dict) else None
        if not cfg:
            cfg = item.get("username") if isinstance(item, dict) else None
        if cnt is None:
            for k in ("connections", "active", "count"):
                if isinstance(item, dict) and k in item:
                    cnt = item[k]
        try:
            cnt = int(cnt or 0)
        except Exception:
            cnt = 0
        out.append({"ip": ip or "unknown", "config": cfg or "unknown", "count": cnt})
    out_sorted = sorted(out, key=lambda x: x["count"], reverse=True)
    return jsonify(out_sorted)

@app.route("/")
def index():
    return render_template("index.html")

@app.route("/static/<path:p>")
def static_files(p):
    return send_from_directory(os.path.join(REPO_ROOT, "web", "static"), p)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 8080)), debug=False)
PY

cat > "$WEB_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Marzneshin — IP ها</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
  <div class="container py-4">
    <h3 class="mb-3">لیست آی‌پی‌ها و تنظیمات متصل</h3>

    <div class="mb-3">
      <button id="refreshBtn" class="btn btn-primary btn-sm">تازه‌سازی</button>
      <span class="ms-2 text-muted">آخرین به‌روز‌رسانی: <span id="lastUpdate">-</span></span>
    </div>

    <div class="table-responsive">
      <table class="table table-striped table-bordered">
        <thead class="table-dark">
          <tr>
            <th>ترتیب</th>
            <th>IP</th>
            <th>کانفیگ / کاربر</th>
            <th>تعداد اتصال</th>
          </tr>
        </thead>
        <tbody id="ipTableBody">
          <tr><td colspan="4" class="text-center text-muted">در حال بارگذاری…</td></tr>
        </tbody>
      </table>
    </div>

    <div id="note" class="text-muted small mt-2">
      اگر دیتای IP در فایل <code>detected_users.json</code> وجود داشته باشد از آن خوانده می‌شود. در غیر این صورت تلاش می‌شود از ماژول پایتونی یا API محلی برنامه استفاده شود.
    </div>
  </div>

<script>
async function loadIps(){
  const tbody = document.getElementById("ipTableBody");
  tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">در حال بارگذاری…</td></tr>';
  try {
    const res = await fetch('/api/ips');
    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) {
      tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">داده‌ای یافت نشد</td></tr>';
      document.getElementById("lastUpdate").innerText = new Date().toLocaleString();
      return;
    }
    let html = '';
    data.forEach((r,i) => {
      html += `<tr>
        <td>${i+1}</td>
        <td><code>${r.ip}</code></td>
        <td>${r.config||'-'}</td>
        <td>${r.count}</td>
      </tr>`;
    });
    tbody.innerHTML = html;
    document.getElementById("lastUpdate").innerText = new Date().toLocaleString();
  } catch (e) {
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-danger">خطا در دریافت داده</td></tr>';
    console.error(e);
  }
}

document.getElementById("refreshBtn").addEventListener("click", loadIps);
window.addEventListener("load", loadIps);
</script>
</body>
</html>
HTML

echo "Step 3: ensure requirements.txt contains flask and requests"
touch "$REQ_FILE"

# ✅ مطمئن شو آخر فایل خط خالی (newline) داره تا پکیج‌ها نچسبن به هم
sed -i -e '$a\' "$REQ_FILE"

# ✅ اضافه کردن امن پکیج‌ها در صورت نبود
grep -qi "^flask" "$REQ_FILE" 2>/dev/null || echo "Flask==3.0.3" >> "$REQ_FILE"
grep -qi "^requests" "$REQ_FILE" 2>/dev/null || echo "requests" >> "$REQ_FILE"
# Make sure requirements file ends with newline to avoid merge errors
sed -i -e '$a\' "$REQ_FILE"

# safely add dependencies if missing
grep -qi "^flask" "$REQ_FILE" 2>/dev/null || echo "Flask==3.0.3" >> "$REQ_FILE"
grep -qi "^requests" "$REQ_FILE" 2>/dev/null || echo "requests" >> "$REQ_FILE"

echo "Step 4: create docker-compose override file (docker-compose.web.yml)"
cat > "$COMPOSE_OVERRIDE" <<'YML'
version: "3.8"
services:
  web:
    build: .
    container_name: marzneshin_web
    command: python3 web_server.py
    volumes:
      - ./:/app:cached
    working_dir: /app
    ports:
      - "8080:8080"
    restart: unless-stopped
YML

echo "Step 5: attempt to build & run web service with docker compose"
cd "$DIR"

# choose compose invocation
if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose -f docker-compose.yml -f docker-compose.web.yml"
else
  COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.web.yml"
fi

# build & up
$COMPOSE_CMD build web || true
$COMPOSE_CMD up -d web

echo "Done. Web UI should be available at http://<server-ip>:8080 (or on the server: http://127.0.0.1:8080)."
echo "If container fails, check logs: sudo $COMPOSE_CMD logs -f web"

fix: prevent python-jose==3.3.0requests error by adding newline
