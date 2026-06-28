#!/usr/bin/env python3
import argparse
import json
import mimetypes
import os
import re
import subprocess
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse, unquote


ROOT_DIR = Path(__file__).resolve().parent.parent
UI_DIR = ROOT_DIR / "ui"
PERIOD_RE = re.compile(r"^\d{4}-\d{2}$")


@dataclass
class ServerConfig:
    host: str
    port: int
    mysql_host: str
    mysql_port: int
    mysql_user: str
    mysql_password: str
    database: str
    mysql_exe: str


def sql_escape(value: str) -> str:
    return value.replace("'", "''")


def run_mysql_query(config: ServerConfig, query: str) -> list[str]:
    env = os.environ.copy()
    env["MYSQL_PWD"] = config.mysql_password
    cmd = [
        config.mysql_exe,
        f"-h{config.mysql_host}",
        f"-P{config.mysql_port}",
        f"-u{config.mysql_user}",
        f"-D{config.database}",
        "--batch",
        "--raw",
        "--skip-column-names",
        "-e",
        query,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        err = proc.stderr.strip() or proc.stdout.strip()
        raise RuntimeError(f"MySQL query failed: {err}")
    text = proc.stdout.strip()
    return [] if not text else text.splitlines()


def parse_metrics_rows(lines: list[str]) -> list[dict]:
    rows: list[dict] = []
    for line in lines:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 12:
            continue
        rows.append(
            {
                "period": parts[0],
                "txCount": int(parts[1]),
                "volume": float(parts[2]),
                "refundAmount": float(parts[3]),
                "refundCount": int(parts[4]),
                "chargebackAmount": float(parts[5]),
                "chargebackCount": int(parts[6]),
                "fraudAmount": float(parts[7]),
                "fraudCount": int(parts[8]),
                "refundRate": float(parts[9]),
                "chargebackRate": float(parts[10]),
                "fraudRate": float(parts[11]),
            }
        )
    return rows


class RequestHandler(BaseHTTPRequestHandler):
    config: ServerConfig = None  # type: ignore[assignment]

    def _send_json(self, obj: dict, status: int = HTTPStatus.OK) -> None:
        payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _send_file(self, path: Path) -> None:
        if not path.exists() or not path.is_file():
            self._send_json(
                {"error": "NotFound", "message": "File not found."},
                status=HTTPStatus.NOT_FOUND,
            )
            return
        content = path.read_bytes()
        content_type, _ = mimetypes.guess_type(path.name)
        if not content_type:
            content_type = "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def _handle_api(self, parsed) -> None:
        path = parsed.path.lower()
        query = parse_qs(parsed.query)
        get = lambda k, default="": (query.get(k, [default])[0] or default)

        if path == "/api/health":
            self._send_json({"ok": True, "service": "payment-monitor-api"})
            return

        if path == "/api/merchants":
            sql = """
SELECT merchant_id, merchant_name, mcc
FROM merchants
ORDER BY merchant_id;
"""
            lines = run_mysql_query(self.config, sql)
            rows = []
            for line in lines:
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                rows.append(
                    {
                        "merchant_id": parts[0],
                        "merchant_name": parts[1],
                        "mcc": parts[2],
                    }
                )
            self._send_json({"rows": rows})
            return

        if path == "/api/platform":
            sql = """
SELECT DATE_FORMAT(stat_month, '%Y-%m') AS period,
       tx_success_count,
       tx_success_amount,
       refund_amount,
       refund_count,
       chargeback_amount,
       chargeback_count,
       fraud_amount,
       fraud_count,
       refund_rate,
       chargeback_rate,
       fraud_rate
FROM vw_platform_monthly_metrics
ORDER BY stat_month DESC
LIMIT 6;
"""
            rows = parse_metrics_rows(run_mysql_query(self.config, sql))
            self._send_json({"rows": rows})
            return

        if path == "/api/merchant":
            merchant_id = get("merchant_id").strip()
            if not merchant_id:
                self._send_json(
                    {"error": "BadRequest", "message": "merchant_id is required."},
                    status=HTTPStatus.BAD_REQUEST,
                )
                return
            safe_merchant = sql_escape(merchant_id)
            meta_sql = f"""
SELECT merchant_name, mcc
FROM merchants
WHERE merchant_id = '{safe_merchant}'
LIMIT 1;
"""
            meta_lines = run_mysql_query(self.config, meta_sql)
            merchant_name = ""
            merchant_mcc = ""
            if meta_lines:
                parts = meta_lines[0].split("\t")
                if len(parts) >= 2:
                    merchant_name = parts[0]
                    merchant_mcc = parts[1]

            sql = f"""
SELECT DATE_FORMAT(stat_month, '%Y-%m') AS period,
       tx_success_count,
       tx_success_amount,
       refund_amount,
       refund_count,
       chargeback_amount,
       chargeback_count,
       fraud_amount,
       fraud_count,
       refund_rate,
       chargeback_rate,
       fraud_rate
FROM vw_merchant_monthly_metrics
WHERE merchant_id = '{safe_merchant}'
ORDER BY stat_month DESC
LIMIT 6;
"""
            rows = parse_metrics_rows(run_mysql_query(self.config, sql))
            self._send_json(
                {
                    "merchant_id": merchant_id,
                    "merchant_name": merchant_name,
                    "mcc": merchant_mcc,
                    "rows": rows,
                }
            )
            return

        if path == "/api/details":
            detail_type = get("type").strip()
            scope = "merchant" if get("scope").strip() == "merchant" else "platform"
            merchant_id = get("merchant_id").strip()
            period = get("period").strip()
            page = max(int(get("page", "1") or 1), 1)
            page_size = int(get("page_size", "50") or 50)
            if page_size <= 0:
                page_size = 50
            page_size = min(page_size, 50)
            offset = (page - 1) * page_size

            merchant_filter = ""
            if scope == "merchant":
                if not merchant_id:
                    self._send_json(
                        {
                            "error": "BadRequest",
                            "message": "merchant_id is required for merchant scope.",
                        },
                        status=HTTPStatus.BAD_REQUEST,
                    )
                    return
                merchant_filter = f" AND t.merchant_id = '{sql_escape(merchant_id)}' "

            period_filter = ""
            if period and PERIOD_RE.match(period):
                safe_period = sql_escape(period)
                if detail_type == "transaction":
                    period_filter = f" AND DATE_FORMAT(t.txn_time, '%Y-%m') = '{safe_period}' "
                elif detail_type == "refund":
                    period_filter = f" AND DATE_FORMAT(r.refund_time, '%Y-%m') = '{safe_period}' "
                elif detail_type == "chargeback":
                    period_filter = f" AND DATE_FORMAT(c.chargeback_time, '%Y-%m') = '{safe_period}' "
                elif detail_type == "fraud":
                    period_filter = f" AND DATE_FORMAT(f.fraud_time, '%Y-%m') = '{safe_period}' "

            if detail_type == "transaction":
                count_sql = f"""
SELECT COUNT(*)
FROM transactions t
WHERE 1=1
  {merchant_filter}
  {period_filter};
"""
                sql = f"""
SELECT
  t.merchant_id,
  t.order_id,
  t.mcc,
  t.currency,
  t.amount,
  t.payment_status AS detail_status,
  DATE_FORMAT(t.txn_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM transactions t
WHERE 1=1
  {merchant_filter}
  {period_filter}
ORDER BY t.txn_time DESC
LIMIT {offset}, {page_size};
"""
            elif detail_type == "refund":
                count_sql = f"""
SELECT COUNT(*)
FROM refunds r
JOIN transactions t ON t.order_id = r.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter};
"""
                sql = f"""
SELECT
  t.merchant_id,
  t.order_id,
  t.mcc,
  r.refund_currency AS currency,
  r.refund_amount AS amount,
  r.refund_status AS detail_status,
  DATE_FORMAT(r.refund_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM refunds r
JOIN transactions t ON t.order_id = r.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter}
ORDER BY r.refund_time DESC
LIMIT {offset}, {page_size};
"""
            elif detail_type == "chargeback":
                count_sql = f"""
SELECT COUNT(*)
FROM chargebacks c
JOIN transactions t ON t.order_id = c.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter};
"""
                sql = f"""
SELECT
  t.merchant_id,
  t.order_id,
  c.mcc,
  c.chargeback_currency AS currency,
  c.chargeback_amount AS amount,
  c.chargeback_reason AS detail_status,
  DATE_FORMAT(c.chargeback_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM chargebacks c
JOIN transactions t ON t.order_id = c.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter}
ORDER BY c.chargeback_time DESC
LIMIT {offset}, {page_size};
"""
            elif detail_type == "fraud":
                count_sql = f"""
SELECT COUNT(*)
FROM fraud_events f
JOIN transactions t ON t.order_id = f.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter};
"""
                sql = f"""
SELECT
  t.merchant_id,
  t.order_id,
  f.mcc,
  f.currency,
  f.amount,
  'FRAUD' AS detail_status,
  DATE_FORMAT(f.fraud_time, '%Y-%m-%d %H:%i:%s') AS event_time
FROM fraud_events f
JOIN transactions t ON t.order_id = f.original_order_id
WHERE 1=1
  {merchant_filter}
  {period_filter}
ORDER BY f.fraud_time DESC
LIMIT {offset}, {page_size};
"""
            else:
                self._send_json(
                    {
                        "error": "BadRequest",
                        "message": "type must be transaction, refund, chargeback, or fraud.",
                    },
                    status=HTTPStatus.BAD_REQUEST,
                )
                return

            count_lines = run_mysql_query(self.config, count_sql)
            total = int(count_lines[0]) if count_lines else 0
            total_pages = max((total + page_size - 1) // page_size, 1)
            lines = run_mysql_query(self.config, sql)
            rows = []
            for line in lines:
                parts = line.split("\t")
                if len(parts) < 7:
                    continue
                rows.append(
                    {
                        "merchant_id": parts[0],
                        "order_id": parts[1],
                        "mcc": parts[2],
                        "currency": parts[3],
                        "amount": float(parts[4]),
                        "detail_status": parts[5],
                        "event_time": parts[6],
                    }
                )
            self._send_json(
                {
                    "type": detail_type,
                    "scope": scope,
                    "merchant_id": merchant_id,
                    "page": page,
                    "page_size": page_size,
                    "total": total,
                    "total_pages": total_pages,
                    "rows": rows,
                }
            )
            return

        self._send_json(
            {"error": "NotFound", "message": "API route not found."},
            status=HTTPStatus.NOT_FOUND,
        )

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        try:
            if parsed.path.lower().startswith("/api/"):
                self._handle_api(parsed)
                return

            if parsed.path in ("/", ""):
                self._send_file(UI_DIR / "login.html")
                return
            if parsed.path == "/dashboard":
                self._send_file(UI_DIR / "index.html")
                return

            relative = unquote(parsed.path).lstrip("/").replace("/", os.sep)
            static_path = (UI_DIR / relative).resolve()
            if not str(static_path).startswith(str(UI_DIR.resolve())):
                self._send_json(
                    {"error": "NotFound", "message": "File not found."},
                    status=HTTPStatus.NOT_FOUND,
                )
                return
            self._send_file(static_path)
        except Exception as exc:  # pylint: disable=broad-except
            self._send_json(
                {"error": "ServerError", "message": str(exc)},
                status=HTTPStatus.INTERNAL_SERVER_ERROR,
            )

    def log_message(self, fmt, *args):
        # Keep output concise in terminal.
        print(f"{self.address_string()} - - [{self.log_date_time_string()}] {fmt % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Payment monitor local server (Python).")
    parser.add_argument("--host", default="localhost", help="HTTP bind host.")
    parser.add_argument("--port", type=int, default=8788, help="HTTP bind port.")
    parser.add_argument("--mysql-host", default="127.0.0.1", help="MySQL host.")
    parser.add_argument("--mysql-port", type=int, default=3306, help="MySQL port.")
    parser.add_argument("--mysql-user", default="root", help="MySQL user.")
    parser.add_argument("--mysql-password", default="Rm200509", help="MySQL password.")
    parser.add_argument("--database", default="demo_payments", help="MySQL database.")
    parser.add_argument("--mysql-exe", default="mysql", help="mysql client executable path.")
    args = parser.parse_args()

    config = ServerConfig(
        host=args.host,
        port=args.port,
        mysql_host=args.mysql_host,
        mysql_port=args.mysql_port,
        mysql_user=args.mysql_user,
        mysql_password=args.mysql_password,
        database=args.database,
        mysql_exe=args.mysql_exe,
    )

    RequestHandler.config = config
    server = ThreadingHTTPServer((config.host, config.port), RequestHandler)
    print(f"Server started at http://{config.host}:{config.port}/")
    print(f"UI: http://{config.host}:{config.port}/")
    print(f"API health: http://{config.host}:{config.port}/api/health")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
