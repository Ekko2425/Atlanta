#!/usr/bin/env python3
"""Atlanta DayZ ADM reader. No raw ADM lines or credentials are logged."""

import base64
import hashlib
import json
import os
import posixpath
import re
import sys
from datetime import datetime
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import paramiko

UID = r"[A-Za-z0-9_=-]{44}"
UID_RE = re.compile(UID)
CHAT_RE = re.compile(
    r'Chat\("([^"]+)"\(id=(' + UID + r')\)\):\s*\+(?:\d+\+)?ATLANTA\s+([A-Fa-f0-9]{12})\b',
    re.IGNORECASE,
)
FILE_DATE_RE = re.compile(r"DayZServer_(\d{4}-\d{2}-\d{2})_\d{2}-\d{2}-\d{2}\.ADM$")
TIME_RE = re.compile(r"^(\d{2}:\d{2}:\d{2})\s*\|\s*(.*)$")
MAX_BYTES_PER_FILE = 4 * 1024 * 1024


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError("Falta configurar una variable secreta requerida.")
    return value


def api_request(base_url, service_key, path, payload=None, method=None):
    url = base_url.rstrip("/") + path
    headers = {
        "apikey": service_key,
        "Authorization": "Bearer " + service_key,
        "Accept": "application/json",
    }
    data = None
    if payload is not None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(url, data=data, headers=headers, method=method or ("POST" if data else "GET"))
    try:
        with urlopen(request, timeout=30) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else None
    except HTTPError as exc:
        # Mostrar solo metadatos de error de PostgREST; nunca credenciales ni payloads.
        detail = ""
        try:
            body = json.loads(exc.read().decode("utf-8", errors="replace"))
            parts = [str(body.get(k, "")) for k in ("code", "message", "hint")]
            detail = " | ".join(part[:240] for part in parts if part)
        except Exception:
            pass
        suffix = (" Detalle: " + detail) if detail else ""
        raise RuntimeError("Supabase rechazó %s (HTTP %s).%s" % (path, exc.code, suffix)) from None
    except URLError:
        raise RuntimeError("No se pudo conectar con Supabase.") from None


class PinnedHostKeyPolicy(paramiko.MissingHostKeyPolicy):
    def __init__(self, expected):
        self.expected = expected.strip()

    def missing_host_key(self, client, hostname, key):
        digest = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode("ascii").rstrip("=")
        actual = "SHA256:" + digest
        if actual != self.expected:
            raise paramiko.SSHException("La huella SSH del servidor no coincide con la configurada.")
        client.get_host_keys().add(hostname, key.get_name(), key)


def parse_event(line, file_date, file_path, byte_offset):
    match = TIME_RE.match(line)
    if not match:
        return None
    clock, body = match.groups()
    try:
        occurred_at = datetime.strptime(file_date + " " + clock, "%Y-%m-%d %H:%M:%S").isoformat(sep=" ")
    except ValueError:
        occurred_at = None

    uids = UID_RE.findall(body)
    names = re.findall(r'Player "([^"]+)"', body)
    event_type = None
    # En líneas de conexión DayZ, el BI UID aparece inmediatamente después
    # del nombre: Player "Nombre" UID pos=<...>) is connected.
    connection_match = re.search(
        r'Player "([^"]+)"\\s+(' + UID + r')\\s+pos=<', body
    )
    player_uid = connection_match.group(2) if connection_match else (uids[0] if uids else None)
    actor_uid = None
    payload = {}

    if " killed by Player " in body and len(uids) >= 2:
        event_type = "pvp_kill"
        player_uid, actor_uid = uids[0], uids[1]
        payload = {
            "victim_name": names[0] if names else None,
            "killer_name": names[1] if len(names) > 1 else None,
        }
        weapon = re.search(r" with (.+?) from ([0-9.]+) meters?\.", body)
        if weapon:
            payload["weapon"] = weapon.group(1)
            payload["distance_m"] = float(weapon.group(2))
    elif " placed " in body:
        event_type = "object_placed"
        placed = re.search(r" placed (.+)$", body)
        if placed:
            payload["object"] = placed.group(1)[:180]
    elif " Built " in body:
        event_type = "construction_completed"
        built = re.search(r" Built (.+)$", body)
        if built:
            payload["construction"] = built.group(1)[:180]
    elif " performed Emote" in body:
        event_type = "emote"
        emote = re.search(r" performed (.+)$", body)
        if emote:
            payload["emote"] = emote.group(1)[:120]
    elif " is connecting" in body:
        event_type = "connected"
    elif " is connected" in body:
        event_type = "connected"
    elif " has been disconnected" in body:
        event_type = "disconnected"
    elif " is unconscious" in body:
        event_type = "unconscious"
    elif " regained consciousness" in body:
        event_type = "regained_consciousness"
    elif " hit by " in body:
        event_type = "damage"
        hit = re.search(r" hit by (.+)$", body)
        if hit:
            payload["cause"] = hit.group(1)[:180]
    else:
        return None

    if not player_uid:
        return None
    if names:
        payload["player_name"] = names[0][:64]

    event_key = hashlib.sha256(
        file_path.encode("utf-8") + b"\0" + str(byte_offset).encode("ascii") + b"\0" + line.encode("utf-8")
    ).hexdigest()
    return {
        "event_key": event_key,
        "event_type": event_type,
        "occurred_at": occurred_at,
        "player_uid": player_uid,
        "actor_uid": actor_uid,
        "payload": payload,
    }


def main():
    base_url = required("SUPABASE_URL")
    service_key = required("SUPABASE_SERVICE_ROLE_KEY")
    host = required("DAYZ_SFTP_HOST")
    port = int(os.environ.get("DAYZ_SFTP_PORT", "22"))
    username = required("DAYZ_SFTP_USERNAME")
    password = required("DAYZ_SFTP_PASSWORD")
    profiles_path = required("DAYZ_SFTP_PROFILES_PATH").rstrip("/")
    fingerprint = required("DAYZ_SFTP_HOST_KEY_SHA256")
    bootstrap = os.environ.get("DAYZ_INITIAL_SCAN", "tail").lower()
    if bootstrap not in ("tail", "from_start"):
        raise RuntimeError("DAYZ_INITIAL_SCAN debe ser tail o from_start.")

    cursor_rows = api_request(
        base_url, service_key, "/rest/v1/dayz_file_cursors?select=file_path,byte_offset"
    ) or []
    cursors = {row["file_path"]: int(row["byte_offset"]) for row in cursor_rows}
    # Solo el primer escaneo global puede empezar al final de los ADM existentes.
    # Cuando ya hay cursores, todo ADM nuevo debe leerse desde el byte cero.
    has_existing_cursors = bool(cursors)

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(PinnedHostKeyPolicy(fingerprint))
    try:
        ssh.connect(
            hostname=host,
            port=port,
            username=username,
            password=password,
            timeout=20,
            banner_timeout=20,
            auth_timeout=20,
            look_for_keys=False,
            allow_agent=False,
        )
        sftp = ssh.open_sftp()
        attrs = sftp.listdir_attr(profiles_path)
        adm_files = sorted(
            (a for a in attrs if a.filename.endswith(".ADM") and FILE_DATE_RE.match(a.filename)),
            key=lambda a: a.filename,
        )
        if not adm_files:
            raise RuntimeError("No se encontraron archivos ADM con el formato esperado en profiles.")

        events = []
        new_cursors = []
        link_attempts = []
        for attr in adm_files:
            remote_path = posixpath.join(profiles_path, attr.filename)
            size = int(attr.st_size)
            known = remote_path in cursors
            initial_offset = size if (bootstrap == "tail" and not has_existing_cursors) else 0
            offset = cursors.get(remote_path, initial_offset)
            if offset > size:
                offset = 0

            if size <= offset:
                if not known:
                    new_cursors.append({"file_path": remote_path, "byte_offset": offset})
                continue

            read_size = min(size - offset, MAX_BYTES_PER_FILE)
            with sftp.open(remote_path, "rb") as remote:
                remote.seek(offset)
                chunk = remote.read(read_size)

            complete = []
            consumed = 0
            for raw_line in chunk.splitlines(keepends=True):
                if not raw_line.endswith((b"\n", b"\r")):
                    break
                complete.append((raw_line, consumed))
                consumed += len(raw_line)

            if consumed == 0:
                continue

            file_match = FILE_DATE_RE.match(attr.filename)
            file_date = file_match.group(1)
            for raw_line, relative_offset in complete:
                try:
                    line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
                except Exception:
                    continue

                chat = CHAT_RE.search(line)
                if chat:
                    link_attempts.append({"code": chat.group(3).upper(), "uid": chat.group(2)})

                parsed = parse_event(line, file_date, remote_path, offset + relative_offset)
                if parsed:
                    events.append(parsed)

            new_cursors.append({"file_path": remote_path, "byte_offset": offset + consumed})

        # Procesar verificaciones antes de avanzar cursores: si falla la API,
        # el mensaje queda pendiente y se reintentará en la siguiente ejecución.
        for attempt in link_attempts:
            result = api_request(
                base_url,
                service_key,
                "/rest/v1/rpc/dayz_confirm_link",
                {"p_code": attempt["code"], "p_bi_uid": attempt["uid"]},
            )
            if isinstance(result, dict) and result.get("ok"):
                print("Se confirmó una vinculación de cuenta DayZ.")
            elif isinstance(result, dict) and result.get("reason") not in ("invalid_or_expired", "invalid_format"):
                print("Un intento de vinculación no pudo completarse.")

        result = api_request(
            base_url,
            service_key,
            "/rest/v1/rpc/dayz_ingest_batch",
            {"p_events": events, "p_cursors": new_cursors},
        )
        print(
            "Lectura completada: %s evento(s) nuevo(s), %s archivo(s) actualizado(s)."
            % (result.get("inserted_events", 0), result.get("updated_cursors", 0))
        )
        sftp.close()
    finally:
        ssh.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # Avoid printing remote lines, tokens, host credentials, or API response bodies.
        print("Error en el lector ADM: " + str(exc), file=sys.stderr)
        sys.exit(1)
