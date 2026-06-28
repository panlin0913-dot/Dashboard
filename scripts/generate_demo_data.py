#!/usr/bin/env python3
import argparse
import datetime as dt
import random
from pathlib import Path


MCC_POOL = [
    "5411",  # Grocery Stores
    "5732",  # Electronics Stores
    "5812",  # Eating Places
    "5999",  # Misc Retail
    "4111",  # Transportation
    "7399",  # Business Services
]

CURRENCY_POOL = ["USD"]

CHARGEBACK_REASONS = [
    "FRAUD_CARD_NOT_PRESENT",
    "PRODUCT_NOT_RECEIVED",
    "CREDIT_NOT_PROCESSED",
    "DUPLICATE_PROCESSING",
    "SUBSCRIPTION_CANCELLED",
]


def sql_quote(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "''") + "'"


def batch_insert_lines(table: str, cols: list[str], rows: list[tuple], batch_size: int = 1000) -> list[str]:
    lines: list[str] = []
    if not rows:
        return lines

    col_sql = ", ".join(cols)
    for i in range(0, len(rows), batch_size):
        part = rows[i : i + batch_size]
        values = []
        for row in part:
            encoded = []
            for item in row:
                if item is None:
                    encoded.append("NULL")
                elif isinstance(item, (int, float)):
                    encoded.append(str(item))
                else:
                    encoded.append(sql_quote(str(item)))
            values.append("(" + ", ".join(encoded) + ")")
        lines.append(f"INSERT INTO {table} ({col_sql}) VALUES")
        lines.append(",\n".join(values) + ";")
        lines.append("")
    return lines


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate demo SQL data for payment monitoring.")
    parser.add_argument("--merchants", type=int, default=50, help="Number of merchants.")
    parser.add_argument("--days", type=int, default=90, help="How many days of history to generate.")
    parser.add_argument("--tx-per-day", type=int, default=1000, help="Total platform transactions per day.")
    parser.add_argument("--refund-rate", type=float, default=0.06, help="Refund probability on successful tx.")
    parser.add_argument("--chargeback-rate", type=float, default=0.012, help="Chargeback probability on successful tx.")
    parser.add_argument("--fraud-rate", type=float, default=0.008, help="Fraud probability on successful tx.")
    parser.add_argument("--start-date", type=str, default="", help="Start date, format YYYY-MM-DD.")
    parser.add_argument(
        "--output",
        type=str,
        default=str(Path("sql") / "03_seed_demo.sql"),
        help="Output SQL file path.",
    )
    parser.add_argument("--seed", type=int, default=20260626, help="Random seed for reproducible data.")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    random.seed(args.seed)

    if args.start_date:
        start_date = dt.datetime.strptime(args.start_date, "%Y-%m-%d").date()
    else:
        start_date = dt.date.today() - dt.timedelta(days=args.days - 1)

    merchants = []
    for i in range(1, args.merchants + 1):
        merchant_id = f"M{i:05d}"
        merchants.append(
            (
                merchant_id,
                f"Demo Merchant {i:03d}",
                random.choice(MCC_POOL),
                f"{start_date} 00:00:00",
            )
        )

    tx_rows: list[tuple] = []
    refund_rows: list[tuple] = []
    chargeback_rows: list[tuple] = []
    fraud_rows: list[tuple] = []

    order_seq = 1
    tx_status_choices = ["SUCCESS", "FAILED", "PENDING"]
    tx_status_weights = [0.90, 0.08, 0.02]
    refund_status_choices = ["SUCCESS", "FAILED", "PENDING"]
    refund_status_weights = [0.90, 0.08, 0.02]

    for d in range(args.days):
        current_day = start_date + dt.timedelta(days=d)
        for _ in range(args.tx_per_day):
            merchant_id, _, merchant_mcc, _ = random.choice(merchants)
            order_id = f"ORD{current_day.strftime('%Y%m%d')}{order_seq:08d}"
            order_seq += 1

            currency = random.choice(CURRENCY_POOL)
            amount = round(random.uniform(5, 1500), 2)
            tx_status = random.choices(tx_status_choices, weights=tx_status_weights, k=1)[0]

            tx_hour = random.randint(0, 23)
            tx_minute = random.randint(0, 59)
            tx_second = random.randint(0, 59)
            txn_time = dt.datetime(
                current_day.year, current_day.month, current_day.day, tx_hour, tx_minute, tx_second
            )

            tx_rows.append(
                (
                    merchant_id,
                    order_id,
                    currency,
                    amount,
                    merchant_mcc,
                    tx_status,
                    txn_time.strftime("%Y-%m-%d %H:%M:%S"),
                )
            )

            if tx_status != "SUCCESS":
                continue

            if random.random() < args.refund_rate:
                refund_status = random.choices(refund_status_choices, weights=refund_status_weights, k=1)[0]
                refund_ratio = random.uniform(0.1, 1.0)
                refund_amount = round(min(amount, max(0.01, amount * refund_ratio)), 2)
                refund_time = txn_time + dt.timedelta(days=random.randint(0, 20), minutes=random.randint(1, 1439))
                refund_rows.append(
                    (
                        order_id,
                        currency,
                        refund_amount,
                        refund_status,
                        refund_time.strftime("%Y-%m-%d %H:%M:%S"),
                    )
                )

            if random.random() < args.chargeback_rate:
                cb_time = txn_time + dt.timedelta(days=random.randint(7, 60), minutes=random.randint(1, 1439))
                chargeback_rows.append(
                    (
                        order_id,
                        merchant_id,
                        merchant_mcc,
                        currency,
                        amount,
                        random.choice(CHARGEBACK_REASONS),
                        cb_time.strftime("%Y-%m-%d %H:%M:%S"),
                    )
                )

            if random.random() < args.fraud_rate:
                fraud_time = txn_time + dt.timedelta(days=random.randint(0, 10), minutes=random.randint(1, 1439))
                fraud_rows.append(
                    (
                        order_id,
                        merchant_id,
                        merchant_mcc,
                        currency,
                        amount,
                        fraud_time.strftime("%Y-%m-%d %H:%M:%S"),
                    )
                )

    sql_lines: list[str] = [
        "USE demo_payments;",
        "",
        "SET FOREIGN_KEY_CHECKS = 0;",
        "TRUNCATE TABLE fraud_events;",
        "TRUNCATE TABLE chargebacks;",
        "TRUNCATE TABLE refunds;",
        "TRUNCATE TABLE transactions;",
        "TRUNCATE TABLE merchants;",
        "SET FOREIGN_KEY_CHECKS = 1;",
        "",
    ]

    sql_lines.extend(
        batch_insert_lines(
            "merchants",
            ["merchant_id", "merchant_name", "mcc", "created_at"],
            merchants,
            batch_size=500,
        )
    )
    sql_lines.extend(
        batch_insert_lines(
            "transactions",
            ["merchant_id", "order_id", "currency", "amount", "mcc", "payment_status", "txn_time"],
            tx_rows,
            batch_size=1000,
        )
    )
    sql_lines.extend(
        batch_insert_lines(
            "refunds",
            ["original_order_id", "refund_currency", "refund_amount", "refund_status", "refund_time"],
            refund_rows,
            batch_size=1000,
        )
    )
    sql_lines.extend(
        batch_insert_lines(
            "chargebacks",
            [
                "original_order_id",
                "merchant_id",
                "mcc",
                "chargeback_currency",
                "chargeback_amount",
                "chargeback_reason",
                "chargeback_time",
            ],
            chargeback_rows,
            batch_size=1000,
        )
    )
    sql_lines.extend(
        batch_insert_lines(
            "fraud_events",
            ["original_order_id", "merchant_id", "mcc", "currency", "amount", "fraud_time"],
            fraud_rows,
            batch_size=1000,
        )
    )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(sql_lines), encoding="utf-8")

    print("Demo data SQL generated.")
    print(f"Output: {output_path}")
    print(f"Merchants: {len(merchants)}")
    print(f"Transactions: {len(tx_rows)}")
    print(f"Refunds: {len(refund_rows)}")
    print(f"Chargebacks: {len(chargeback_rows)}")
    print(f"Fraud events: {len(fraud_rows)}")


if __name__ == "__main__":
    main()
