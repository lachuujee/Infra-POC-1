import base64, json, logging, os, re
from urllib import request, error, parse
from datetime import datetime
import boto3

# env
SECRET_ARN     = os.environ["SECRET_ARN"]
GITHUB_REPO    = os.environ["GITHUB_REPO"]
DEFAULT_BRANCH = os.environ.get("DEFAULT_BRANCH", "main")
SKELETONS_ROOT = os.environ.get("SKELETONS_ROOT", "skeletons")
LIVE_ROOT      = os.environ.get("LIVE_ROOT", "live/sandbox")

LOG = logging.getLogger(); LOG.setLevel(logging.INFO)
s3 = boto3.client("s3"); secm = boto3.client("secretsmanager")

# --- github io ---
def _github_token() -> str:
    r = secm.get_secret_value(SecretId=SECRET_ARN)
    raw = r.get("SecretString") or base64.b64decode(r["SecretBinary"]).decode()
    try:
        d = json.loads(raw); return d.get("token") or d.get("github_token") or d.get("GITHUB_TOKEN") or ""
    except Exception:
        return raw.strip()

def _gh_headers():
    t = _github_token()
    if not t: raise RuntimeError("GitHub token missing")
    return {"Authorization": f"token {t}", "Accept": "application/vnd.github+json", "User-Agent": "intake-lambda"}

def _gh_url(path: str, params: dict | None = None) -> str:
    base = f"https://api.github.com/repos/{GITHUB_REPO}/{path.lstrip('/')}"
    return base + ("?" + parse.urlencode(params) if params else "")

def gh_get(path: str, params: dict | None = None, raise_404=False):
    try:
        with request.urlopen(request.Request(_gh_url(path, params), headers=_gh_headers(), method="GET")) as r:
            return json.loads(r.read().decode())
    except error.HTTPError as e:
        if e.code == 404 and not raise_404: return None
        raise RuntimeError(f"GET {path} -> {e.code} {e.read().decode()}")

def gh_put(path: str, payload: dict):
    with request.urlopen(request.Request(_gh_url(path), data=json.dumps(payload).encode(),
                                         headers=_gh_headers(), method="PUT")) as r:
        return json.loads(r.read().decode())

def get_file(path: str, ref: str):
    obj = gh_get(f"contents/{path}", params={"ref": ref})
    if not obj: return None, None
    if obj.get("encoding") == "base64" and obj.get("content"):
        return obj.get("sha"), base64.b64decode(obj["content"])
    return obj.get("sha"), None

def upsert_file(path: str, content: bytes, msg: str, branch: str):
    sha, existing = get_file(path, branch)
    if existing == content: return {"skipped": True, "path": path}
    p = {"message": msg, "content": base64.b64encode(content).decode(), "branch": branch}
    if sha: p["sha"] = sha
    return gh_put(f"contents/{path}", p)

def read_bytes(path: str, ref: str) -> bytes | None:
    _, b = get_file(path, ref); return b

def list_dir(path: str, ref: str):
    obj = gh_get(f"contents/{path}", params={"ref": ref})
    return obj if isinstance(obj, list) else []

def file_exists(path: str, ref: str) -> bool:
    try:
        sha, b = get_file(path, ref)
        return bool(sha or b is not None)
    except Exception:
        return False

# --- aliases/slugs ---
def load_aliases(ref: str) -> dict:
    b = read_bytes(f"{SKELETONS_ROOT}/aliases.json", ref)
    if not b: return {}
    try: return json.loads(b.decode())
    except Exception: return {}

def to_slug(label: str) -> str:
    x = label.strip().lower()
    x = re.sub(r"^(aws|amazon)\s+", "", x)
    x = x.replace("&", "and")
    x = re.sub(r"[^a-z0-9/_]+", "-", x)
    return re.sub(r"-+", "-", x).strip("-")

def label_to_slug(label: str, aliases: dict) -> str:
    for k, v in aliases.items():
        if k == label or k.lower() == label.lower(): return v
    return to_slug(label)

# --- deps + rules ---
def load_deps(ref: str) -> dict:
    b = read_bytes(f"{SKELETONS_ROOT}/dependencies.json", ref)
    if not b: return {}
    try: return json.loads(b.decode())
    except Exception: return {}

def is_virtual(slug: str, deps: dict) -> bool:
    d = deps.get(slug, {})
    return bool(d.get("rules")) and not d.get("enable") and not d.get("copy")

def expand_all(user_set: set, deps: dict) -> set:
    E = set(user_set)
    while True:
        size = len(E)
        for s in list(E):
            E.update(deps.get(s, {}).get("enable", []))
        add = set()
        for s in list(E):
            for rule in deps.get(s, {}).get("rules", []):
                if set(rule.get("any_of", [])) & E:
                    add.update(rule.get("enable", []))
        E |= add
        if len(E) == size: break
    return E

def collect_copy_helpers(E: set, deps: dict) -> set:
    out = set()
    for s in E:
        out.update(deps.get(s, {}).get("copy", []))
    return out

# --- event/input ---
def _resolve_event(event):
    if isinstance(event, dict) and "Records" in event:
        rec = event["Records"][0]; bkt = rec["s3"]["bucket"]["name"]; key = parse.unquote(rec["s3"]["object"]["key"])
        body = s3.get_object(Bucket=bkt, Key=key)["Body"].read()
        return json.loads(body.decode()), key
    if "s3_bucket" in event and "s3_key" in event:
        bkt = event["s3_bucket"]; key = event["s3_key"]
        body = s3.get_object(Bucket=bkt, Key=key)["Body"].read()
        return json.loads(body.decode()), key
    if "payload" in event:
        p = event["payload"]; 
        if isinstance(p, str): p = json.loads(p)
        return p, p.get("source_key", "")
    raise RuntimeError("Unsupported event format")

def version_tag(payload: dict) -> str:
    v = payload.get("version")
    if isinstance(v, int): return f"V{v}"
    if isinstance(v, str) and v.strip().upper().startswith("V"): return v.strip().upper()
    return "V" + datetime.utcnow().strftime("%Y%m%d%H%M%S")

def enabled_from_payload(payload: dict, aliases: dict) -> set:
    out = set()
    for label, cfg in (payload.get("modules") or {}).items():
        if bool(cfg.get("enabled", False)):
            out.add(label_to_slug(label, aliases))
    return out

# --- repo discover + state ---
def discover_repo_slugs(intake_dir: str) -> set:
    found = set()
    for item in list_dir(intake_dir, DEFAULT_BRANCH):
        if item.get("type") != "dir": continue
        d = item["name"]
        # direct module folder
        if file_exists(f"{intake_dir}/{d}/terragrunt.hcl", DEFAULT_BRANCH):
            found.add(d)
            continue
        # nested (e.g., iam/instance_profile)
        for sub in list_dir(f"{intake_dir}/{d}", DEFAULT_BRANCH):
            if sub.get("type") != "dir": continue
            s = sub["name"]
            if file_exists(f"{intake_dir}/{d}/{s}/terragrunt.hcl", DEFAULT_BRANCH):
                found.add(f"{d}/{s}")
    return found

def read_state(intake_dir: str) -> dict:
    b = read_bytes(f"{intake_dir}/state.json", DEFAULT_BRANCH)
    if not b: return {"current_enabled": [], "ever_provisioned": [], "history": []}
    try: return json.loads(b.decode())
    except Exception: return {"current_enabled": [], "ever_provisioned": [], "history": []}

def write_state(intake_dir: str, state: dict, msg: str):
    upsert_file(f"{intake_dir}/state.json", (json.dumps(state, indent=2)+"\n").encode(), msg, DEFAULT_BRANCH)

# --- ensure/copy ---
def ensure_root_tg(intake_dir: str):
    b = read_bytes(f"{SKELETONS_ROOT}/terragrunt.hcl", DEFAULT_BRANCH)
    if not b: raise RuntimeError("Missing skeletons/terragrunt.hcl")
    upsert_file(f"{intake_dir}/terragrunt.hcl", b, f"ensure root TG {intake_dir}", DEFAULT_BRANCH)

def ensure_component_tg(slug: str, intake_dir: str, deps_map: dict):
    b = read_bytes(f"{SKELETONS_ROOT}/{slug}/terragrunt.hcl", DEFAULT_BRANCH)
    if not b:
        if is_virtual(slug, deps_map): return {"skipped": True, "virtual": True, "slug": slug}
        raise RuntimeError(f"Missing skeleton {SKELETONS_ROOT}/{slug}/terragrunt.hcl")
    return upsert_file(f"{intake_dir}/{slug}/terragrunt.hcl", b, f"ensure TG {slug}", DEFAULT_BRANCH)

def write_json(path: str, obj: dict, msg: str):
    upsert_file(path, (json.dumps(obj, indent=2)+"\n").encode(), msg, DEFAULT_BRANCH)

# --- handler ---
def lambda_handler(event, context):
    try:
        payload, _ = _resolve_event(event)

        req_id = payload.get("request_id") or payload.get("requestId")
        if not req_id: raise RuntimeError("payload.request_id missing")

        flags = {
            "is_modified": bool(payload.get("is_modified", False)),
            "is_extended": bool(payload.get("is_extended", False)),
            "is_decom": bool(payload.get("is_decommissioned", False) or
                             payload.get("is_decommission", False) or
                             payload.get("is_decomission", False))
        }

        aliases  = load_aliases(DEFAULT_BRANCH)
        deps_map = load_deps(DEFAULT_BRANCH)

        intake_dir   = f"{LIVE_ROOT}/{req_id.strip().lower()}"
        version      = version_tag(payload)
        versions_dir = f"{intake_dir}/versions/{version}"

        state = read_state(intake_dir)
        prev_enabled = set(state.get("current_enabled", []))

        user_enabled = enabled_from_payload(payload, aliases)

        # snapshots first
        raw = (json.dumps(payload, indent=2)+"\n").encode()
        write_json(f"{versions_dir}/inputs.json", json.loads(raw.decode()), f"{req_id}: snapshot {version}")
        upsert_file(f"{intake_dir}/inputs.json", raw, f"{req_id}: inputs {version}", DEFAULT_BRANCH)

        # expansion
        expanded = expand_all(user_enabled, deps_map)
        helpers  = collect_copy_helpers(expanded, deps_map)
        non_virtual = {s for s in (expanded | helpers) if not is_virtual(s, deps_map)}

        # copy skeletons
        ensure_root_tg(intake_dir)
        for slug in sorted(non_virtual):
            ensure_component_tg(slug, intake_dir, deps_map)

        # full decommission union base
        repo_seen = discover_repo_slugs(intake_dir)
        base_for_full = set(state.get("ever_provisioned", [])) | repo_seen | prev_enabled | user_enabled

        # destroy plan
        modules_to_destroy = []
        if flags["is_decom"]:
            modules_to_destroy = sorted({m for m in expand_all(base_for_full, deps_map) if not is_virtual(m, deps_map)})
        elif flags["is_modified"] or flags["is_extended"]:
            removed = prev_enabled - non_virtual
            if removed:
                removed_closure   = expand_all(removed, deps_map)
                remaining_closure = expand_all(non_virtual, deps_map)
                modules_to_destroy = sorted({m for m in removed_closure - remaining_closure if not is_virtual(m, deps_map)})

        # write decom logs (versioned + latest)
        if modules_to_destroy:
            decom_obj = {"modules_to_destroy": modules_to_destroy,
                         "requested_at": datetime.utcnow().isoformat()+"Z",
                         "version": version}
            write_json(f"{versions_dir}/decommission.inputs.json", decom_obj, f"{req_id}: decom list {version}")
            write_json(f"{intake_dir}/decommission.inputs.json", decom_obj, f"{req_id}: decom latest {version}")

        # update state (idempotent)
        ever = set(state.get("ever_provisioned", [])) | set(non_virtual)
        state_update = {
            "current_enabled": sorted(non_virtual),
            "ever_provisioned": sorted(ever),
            "history": state.get("history", []) + [{
                "version": version,
                "timestamp": datetime.utcnow().isoformat()+"Z",
                "enabled_now": sorted(non_virtual),
                "added": sorted(non_virtual - prev_enabled),
                "removed": sorted(prev_enabled - non_virtual),
                "destroy_plan": modules_to_destroy
            }]
        }
        write_state(intake_dir, state_update, f"{req_id}: state update {version}")

        return {
            "status": "ok",
            "branch": DEFAULT_BRANCH,
            "intake_dir": intake_dir,
            "version": version,
            "copied": sorted(non_virtual),
            "destroy": modules_to_destroy
        }

    except Exception as e:
        LOG.exception("Lambda failed")
        return {"status": "error", "error": str(e)}
