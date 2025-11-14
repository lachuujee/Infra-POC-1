# lambda_event_orchestrator.py
import base64, json, logging, os, re
from urllib import request, error, parse
from datetime import datetime
import boto3

# --- Env ---
SECRET_ARN     = os.environ["SECRET_ARN"]                 # Secrets Manager secret with PAT
GITHUB_REPO    = os.environ["GITHUB_REPO"]                # e.g. "lachuujee/Infra-POC-1"
DEFAULT_BRANCH = os.environ.get("DEFAULT_BRANCH", "main")
SKELETONS_ROOT = os.environ.get("SKELETONS_ROOT", "skeletons")
LIVE_ROOT      = os.environ.get("LIVE_ROOT", "live/sandbox")

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)
s3, secm = boto3.client("s3"), boto3.client("secretsmanager")

# --------------------------------------------------------------------------------------
# GitHub helpers (Contents API; directory ops done by listing + copy + delete per file)
# --------------------------------------------------------------------------------------
def _github_token() -> str:
    r = secm.get_secret_value(SecretId=SECRET_ARN)
    raw = r.get("SecretString") or base64.b64decode(r["SecretBinary"]).decode()
    try:
        j = json.loads(raw)
        return j.get("token") or j.get("github_token") or j.get("GITHUB_TOKEN") or ""
    except Exception:
        return raw.strip()

def _gh_headers():
    return {
        "Authorization": f"token {_github_token()}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "intake-lambda",
    }

def _gh_url(path, params=None):
    base = f"https://api.github.com/repos/{GITHUB_REPO}/{path.lstrip('/')}"
    return base + ("?" + parse.urlencode(params) if params else "")

def gh_get(path, params=None, raise_404=False):
    try:
        with request.urlopen(request.Request(_gh_url(path, params), headers=_gh_headers(), method="GET")) as r:
            return json.loads(r.read().decode())
    except error.HTTPError as e:
        if e.code == 404 and not raise_404:
            return None
        raise RuntimeError(f"GET {path} -> {e.code} {e.read().decode()}")

def gh_put(path, payload):
    with request.urlopen(request.Request(_gh_url(path), data=json.dumps(payload).encode(), headers=_gh_headers(), method="PUT")) as r:
        return json.loads(r.read().decode())

def gh_delete(path, sha, message, branch):
    payload = {"message": message, "sha": sha, "branch": branch}
    with request.urlopen(request.Request(_gh_url(path), data=json.dumps(payload).encode(), headers=_gh_headers(), method="DELETE")) as r:
        return json.loads(r.read().decode())

def gh_list_dir(path, ref):
    obj = gh_get(f"contents/{path}", params={"ref": ref})
    if obj is None:
        return []
    if isinstance(obj, list):
        return obj
    return [obj]

def get_file(path, ref):
    obj = gh_get(f"contents/{path}", params={"ref": ref})
    if not obj:
        return None, None
    if obj.get("encoding") == "base64" and obj.get("content") is not None:
        return obj.get("sha"), base64.b64decode(obj["content"])
    return obj.get("sha"), None

def read_bytes(path, ref):
    _, b = get_file(path, ref)
    return b

def upsert_file(path, content_bytes, message, branch):
    sha, existing = get_file(path, branch)
    if existing == content_bytes:
        return {"skipped": True, "path": path, "commit": None}
    payload = {
        "message": message,
        "content": base64.b64encode(content_bytes).decode(),
        "branch": branch,
    }
    if sha:
        payload["sha"] = sha
    res = gh_put(f"contents/{path}", payload)
    return {"skipped": False, "path": path, "commit": (res.get("commit", {}) or {}).get("sha")}

def copy_file(src_path, dest_path, ref_src, branch_dest, message):
    sha, b = get_file(src_path, ref_src)
    if b is None:
        items = gh_list_dir(src_path, ref_src)
        if items and isinstance(items, list) and items[0].get("download_url"):
            with request.urlopen(items[0]["download_url"]) as r:
                b = r.read()
    if b is None:
        return {"copied": False, "path": dest_path, "reason": "no-bytes"}
    return upsert_file(dest_path, b, message, branch_dest)

def list_files_recursive(dir_path, ref):
    out = []
    stack = [dir_path.rstrip("/")]
    while stack:
        p = stack.pop()
        items = gh_list_dir(p, ref)
        for it in items:
            t = it.get("type")
            if t == "dir":
                stack.append(it["path"])
            elif t == "file":
                out.append({"path": it["path"], "sha": it.get("sha"), "type": "file"})
    return out

def move_tree(src_dir, dst_dir, branch, message_prefix):
    moved, skipped = [], []
    files = list_files_recursive(src_dir, branch)
    if not files:
        return moved, skipped
    for f in files:
        src_file = f["path"]
        rel = src_file[len(src_dir.rstrip("/"))+1:] if src_file.startswith(src_dir.rstrip("/") + "/") else os.path.basename(src_file)
        dst_file = f"{dst_dir.rstrip('/')}/{rel}"
        try:
            copy_file(src_file, dst_file, branch, branch, f"{message_prefix}: move {src_file} -> {dst_file}")
            sha = f.get("sha")
            if sha:
                gh_delete(f"contents/{src_file}", sha, f"{message_prefix}: delete {src_file}", branch)
            moved.append(dst_file)
        except Exception as e:
            LOG.warning("move failed for %s -> %s: %s", src_file, dst_file, e)
            skipped.append(src_file)
    return moved, skipped

# ---------------------------------------------------------------------
# Aliases / slug
# ---------------------------------------------------------------------
def load_aliases(ref):
    b = read_bytes(f"{SKELETONS_ROOT}/aliases.json", ref)
    if not b:
        return {}
    try:
        return json.loads(b.decode())
    except Exception:
        return {}

def to_slug(label: str) -> str:
    x = label.strip().lower()
    x = re.sub(r"^(aws|amazon)\s+", "", x)
    x = x.replace("&", "and")
    x = re.sub(r"[^a-z0-9/_]+", "-", x)
    return re.sub(r"-+", "-", x).strip("-")

def label_to_slug(label, aliases):
    for k, v in aliases.items():
        if k == label or k.lower() == label.lower():
            return v
    return to_slug(label)

# ---------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------
def load_deps(ref):
    b = read_bytes(f"{SKELETONS_ROOT}/dependencies.json", ref)
    if not b:
        return {}
    try:
        return json.loads(b.decode())
    except Exception:
        return {}

def expand_enable_closure(seeds: set, deps_map: dict) -> set:
    out, q = set(), list(seeds)
    while q:
        s = q.pop()
        if s in out:
            continue
        out.add(s)
        for nxt in deps_map.get(s, {}).get("enable", []):
            if nxt not in out:
                q.append(nxt)
    return out

def expand_copy_helpers(seeds: set, deps_map: dict) -> set:
    out = set()
    for s in seeds:
        for nxt in deps_map.get(s, {}).get("copy", []):
            out.add(nxt)
    return out

def apply_rules(active: set, deps_map: dict) -> set:
    add = set()
    for k, v in deps_map.items():
        rules = v.get("rules", [])
        for r in rules:
            any_of = set(r.get("any_of", []))
            if any_of and active.intersection(any_of):
                add.update(r.get("enable", []))
    return add

# ---------------------------------------------------------------------
# Event parsing
# ---------------------------------------------------------------------
def _resolve_event(event):
    if isinstance(event, dict) and "Records" in event:
        rec = event["Records"][0]
        bkt = rec["s3"]["bucket"]["name"]
        key = parse.unquote(rec["s3"]["object"]["key"])
        body = s3.get_object(Bucket=bkt, Key=key)["Body"].read()
        return json.loads(body.decode()), key
    if "s3_bucket" in event and "s3_key" in event:
        body = s3.get_object(Bucket=event["s3_bucket"], Key=event["s3_key"])["Body"].read()
        return json.loads(body.decode()), event["s3_key"]
    if "payload" in event:
        p = event["payload"]
        p = json.loads(p) if isinstance(p, str) else p
        return p, p.get("source_key", "")
    raise RuntimeError("Unsupported event")

# ---------------------------------------------------------------------
# Small utils
# ---------------------------------------------------------------------
def version_tag(payload):
    v = payload.get("version")
    if isinstance(v, int):
        return f"V{v}"
    if isinstance(v, str) and v.strip():
        return v.strip().upper()
    return "V" + datetime.utcnow().strftime("%Y%m%d%H%M%S")

def enabled_from_payload(payload: dict, aliases: dict) -> set:
    out = set()
    for label, cfg in (payload.get("modules") or {}).items():
        if bool((cfg or {}).get("enabled", False)):
            out.add(label_to_slug(label, aliases))
    return out

def disabled_from_payload(payload: dict, aliases: dict) -> set:
    out = set()
    for label, cfg in (payload.get("modules") or {}).items():
        if (cfg or {}).get("enabled") is False:
            out.add(label_to_slug(label, aliases))
    return out

def explicit_decom_from_payload(payload: dict, aliases: dict) -> set:
    out = set()
    for key in ("decommission", "decommissioned", "decom"):
        if isinstance(payload.get(key), list):
            for label in payload[key]:
                out.add(label_to_slug(str(label), aliases))
    for label, cfg in (payload.get("modules") or {}).items():
        c = cfg or {}
        if c.get("decommission") is True:
            out.add(label_to_slug(label, aliases))
        st = str(c.get("state", "")).lower()
        if st.startswith("decom") or st in ("remove", "deleted"):
            out.add(label_to_slug(label, aliases))
    return out

def ensure_root_tg(intake_dir):
    b = read_bytes(f"{SKELETONS_ROOT}/terragrunt.hcl", DEFAULT_BRANCH)
    if not b:
        raise RuntimeError("Missing skeletons/terragrunt.hcl")
    upsert_file(f"{intake_dir}/terragrunt.hcl", b, f"ensure root TG {intake_dir}", DEFAULT_BRANCH)

def ensure_component_tg(slug, intake_dir):
    b = read_bytes(f"{SKELETONS_ROOT}/{slug}/terragrunt.hcl", DEFAULT_BRANCH)
    if not b:
        LOG.info("virtual or missing skeleton skipped: %s", slug)
        return
    upsert_file(f"{intake_dir}/{slug}/terragrunt.hcl", b, f"ensure TG {slug}", DEFAULT_BRANCH)

def write_json(path, obj, msg):
    return upsert_file(path, (json.dumps(obj, indent=2) + "\n").encode(), msg, DEFAULT_BRANCH)

def append_state(intake_dir, entry_obj):
    p = f"{intake_dir}/state.json"
    sha, existing = get_file(p, DEFAULT_BRANCH)
    prefix = b""
    if existing:
        prefix = existing
        if not prefix.endswith(b"\n"):
            prefix += b"\n"
    line = (json.dumps(entry_obj, separators=(",", ":")) + "\n").encode()
    return upsert_file(p, prefix + line, f"{entry_obj.get('request_id')} {entry_obj.get('version')}: append state", DEFAULT_BRANCH)

# ---------------------------------------------------------------------
# inputs.json merge helpers
# ---------------------------------------------------------------------
def _ci_key_map(d):
    return {k.lower(): k for k in d.keys()}

def deep_merge_inputs(prev_obj: dict, new_obj: dict, aliases: dict, decomm_slugs: set):
    prev = prev_obj.copy() if isinstance(prev_obj, dict) else {}
    incoming = new_obj.copy() if isinstance(new_obj, dict) else {}

    res = prev.copy()
    for k, v in incoming.items():
        if k == "modules":
            continue
        res[k] = v

    prev_mod = (prev.get("modules") or {})
    new_mod = (incoming.get("modules") or {})

    result_mod = {k: (v.copy() if isinstance(v, dict) else v) for k, v in prev_mod.items()}
    prev_map = _ci_key_map(prev_mod)

    for label, cfg in new_mod.items():
        tgt_label = prev_map.get(label.lower(), label)
        cur = result_mod.get(tgt_label, {})
        cur = cur.copy() if isinstance(cur, dict) else {}
        inc = cfg.copy() if isinstance(cfg, dict) else {}
        for kk, vv in inc.items():
            cur[kk] = vv
        cur["slug"] = label_to_slug(tgt_label, aliases)
        result_mod[tgt_label] = cur

    for label in list(result_mod.keys()):
        cfg = result_mod[label] if isinstance(result_mod[label], dict) else {}
        slug = cfg.get("slug") or label_to_slug(label, aliases)
        if slug in decomm_slugs:
            if "previous_config" not in cfg:
                snap = {k: v for k, v in cfg.items() if k != "previous_config"}
                cfg["previous_config"] = snap
            cfg["status"] = "decommissioned"
            cfg["enabled"] = False
            cfg["slug"] = slug
            result_mod[label] = cfg

    res["modules"] = result_mod
    return res

def pick_modules_by_slugs(full_inputs_obj: dict, slugs: set, aliases: dict):
    modules = full_inputs_obj.get("modules") or {}
    out = {}
    for label, cfg in modules.items():
        slug = (cfg or {}).get("slug") or label_to_slug(label, aliases)
        if slug in slugs:
            out[label] = cfg
    res = full_inputs_obj.copy()
    res["modules"] = out
    return res

# ---------------------------------------------------------------------
# Core handler
# ---------------------------------------------------------------------
def lambda_handler(event, context):
    try:
        payload, _ = _resolve_event(event)
        req_id = payload.get("request_id") or payload.get("requestId")
        if not req_id:
            raise RuntimeError("payload.request_id missing")

        flags = {
            "is_modified": bool(payload.get("is_modified", False)),
            "is_extended": bool(payload.get("is_extended", False)),
            "is_decom":    bool(payload.get("is_decommissioned", False) or
                                payload.get("is_decommission", False)   or
                                payload.get("is_decomission", False))
        }

        aliases  = load_aliases(DEFAULT_BRANCH)
        deps_map = load_deps(DEFAULT_BRANCH)

        intake_dir = f"{LIVE_ROOT}/{req_id.strip().lower()}"
        version    = version_tag(payload)
        # >>> CHANGE: put full-decommission snapshots under versions/decommissioned/<Vn> <<<
        versions_dir = (
            f"{intake_dir}/versions/decommissioned/{version}"
            if flags["is_decom"] else
            f"{intake_dir}/versions/{version}"
        )
        decom_dir  = f"{intake_dir}/decommission"

        # --- Read previous BEFORE writing new ---
        prev_bytes = read_bytes(f"{intake_dir}/inputs.json", DEFAULT_BRANCH)
        prev_payload, prev_enabled = {}, set()
        if prev_bytes:
            try:
                prev_payload = json.loads(prev_bytes.decode())
                prev_enabled = enabled_from_payload(prev_payload, aliases)
            except Exception:
                prev_enabled = set()

        # --- New state from payload ---
        new_enabled       = enabled_from_payload(payload, aliases)
        explicit_disabled = disabled_from_payload(payload, aliases)
        explicit_decom    = explicit_decom_from_payload(payload, aliases)

        # --- Expand deps for copy ---
        seeds = set(new_enabled)
        seeds |= apply_rules(seeds, deps_map)
        hard  = expand_enable_closure(seeds, deps_map)
        soft  = expand_copy_helpers(seeds, deps_map)
        to_copy = set(new_enabled) | hard | soft

        # --- Materialize skeletons ---
        ensure_root_tg(intake_dir)
        for slug in sorted(to_copy):
            ensure_component_tg(slug, intake_dir)

        # --- Decide decommission set ---
        modules_to_destroy = []
        if flags["is_decom"]:
            base = prev_enabled if prev_enabled else new_enabled
            modules_to_destroy = sorted(expand_enable_closure(base, deps_map))
        else:
            removed = set(explicit_disabled) | set(explicit_decom)
            if prev_enabled:
                removed |= (prev_enabled - new_enabled)
            if removed:
                removed_closure   = expand_enable_closure(removed, deps_map)
                remaining_closure = expand_enable_closure(new_enabled, deps_map)
                modules_to_destroy = sorted(removed_closure - remaining_closure)

        # --- Deep-merge inputs (root) & snapshot ---
        merged_inputs = deep_merge_inputs(prev_payload, payload, aliases, set(modules_to_destroy))
        merged_inputs["version"] = version

        # Snapshot the ORIGINAL payload under versions_dir as inputs.json
        raw_snapshot = (json.dumps(payload, indent=2) + "\n").encode()
        upsert_file(f"{versions_dir}/inputs.json", raw_snapshot, f"{req_id} {version}: snapshot", DEFAULT_BRANCH)

        # Persist merged inputs at root
        write_json(f"{intake_dir}/inputs.json", merged_inputs, f"{req_id} {version}: merged inputs")

        # --- Move skeleton folders for partial/full decommission ---
        moved, skipped = [], []
        if modules_to_destroy:
            EXCLUDE_ROOT_DIRS = {"versions", "decommission", ".github"}
            root_items = gh_list_dir(intake_dir, DEFAULT_BRANCH)
            name_is_module_dir = {it.get("name"): True for it in root_items if it.get("type") == "dir" and it.get("name") not in EXCLUDE_ROOT_DIRS}

            if flags["is_decom"]:
                targets = sorted(name_is_module_dir.keys())
            else:
                targets = [d for d in name_is_module_dir.keys() if d in set(modules_to_destroy)]

            for mod in sorted(targets):
                src = f"{intake_dir}/{mod}"
                dst = f"{decom_dir}/{mod}"
                mm, ss = move_tree(src, dst, DEFAULT_BRANCH, f"{req_id} {version}")
                moved.extend(mm); skipped.extend(ss)

            # Scoped inputs under /decommission
            decom_inputs = pick_modules_by_slugs(merged_inputs, set(modules_to_destroy), aliases)
            write_json(f"{decom_dir}/decommission.inputs.json", decom_inputs, f"{req_id} {version}: decommission inputs")

        # --- State log ---
        added_modules = sorted((new_enabled - prev_enabled)) if prev_enabled else sorted(new_enabled)
        state_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "request_id": req_id,
            "version": version,
            "mode": "full_decom" if flags["is_decom"] else ("partial_decom" if modules_to_destroy else "normal"),
            "branch": DEFAULT_BRANCH,
            "added_modules": sorted(added_modules),
            "decommissioned_modules": sorted(modules_to_destroy),
            "copied": sorted(to_copy),
            "moved": moved,
            "skipped": skipped,
        }
        append_state(intake_dir, state_entry)

        return {
            "status": "ok",
            "branch": DEFAULT_BRANCH,
            "intake_dir": intake_dir,
            "version": version,
            "copied": sorted(to_copy),
            "destroy": sorted(modules_to_destroy),
            "moved": moved,
            "skipped": skipped,
            "mode": state_entry["mode"],
        }

    except Exception as e:
        LOG.exception("Lambda failed")
        return {"status": "error", "error": str(e)}
