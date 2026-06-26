# Payment Merchant Health Dashboard

支付平台商户健康度看板后端工程（Node.js + Express + MySQL）。

核心目标：
- 记录每个商户的交易订单、退款、拒付、欺诈事件
- 聚合平台级和商户级 KPI
- 计算商户健康分（health score）用于监控风险与经营质量

## 1. 快速启动

### 安装依赖

```bash
npm install
```

### 启动 MySQL

```bash
docker compose up -d
```

> 首次启动会自动执行 `database/init.sql`：创建数据库、建表，并写入演示数据。

### 配置环境变量

```bash
cp .env.example .env
```

默认配置：
- 服务端口：`3000`
- 数据库：`payment_dashboard_db`
- 用户：`app_user`
- 密码：`app_password`

### 启动服务

```bash
npm run dev
```

## 2. 数据模型

- `merchants`：商户主数据（状态、风险等级）
- `transaction_orders`：交易订单主表
- `order_refunds`：退款事件
- `order_chargebacks`：拒付事件
- `order_fraud_cases`：欺诈事件

### 字段要求（已按你的需求落地）

#### 交易订单（`transaction_orders`）
- 商户名称 `merchant_name`
- 卡号前六后四 `card_number_first6_last4`
- 渠道名称 `channel_name`
- 订单金额 `order_amount`
- 订单币种 `order_currency`
- 付款人邮箱 `payer_email`
- 付款人姓名 `payer_name`
- 支付状态 `payment_status`

#### 退款（`order_refunds`）
- 原交易订单号 `original_order_no`
- 退款币种 `refund_currency`
- 退款金额 `refund_amount`
- 退款状态 `refund_status`

#### 拒付（`order_chargebacks`）
- 原交易订单号 `original_order_no`
- 拒付金额 `chargeback_amount`
- 拒付状态 `chargeback_status`
- 拒付原因 `chargeback_reason`

#### 欺诈（`order_fraud_cases`）
- 原交易订单号 `original_order_no`
- 币种 `currency`
- 金额 `amount`
- 欺诈原因 `fraud_reason`

## 3. 核心看板接口

### 平台看板

`GET /api/dashboard/platform?startDate=2026-06-01&endDate=2026-06-30`

返回：
- 商户覆盖（总商户、活跃商户、有成功交易商户）
- 平台 KPI（订单、交易、GMV、退款、拒付、欺诈）
- 健康度分数与等级（healthy/watch/critical）

### 商户看板列表

`GET /api/dashboard/merchants?startDate=2026-06-01&endDate=2026-06-30`

返回每个商户的健康度聚合指标。

### 单商户看板

`GET /api/dashboard/merchants/:merchantId?startDate=2026-06-01&endDate=2026-06-30`

## 4. 数据写入接口（模拟上游流水）

- `POST /api/merchants`
- `POST /api/transaction-orders`（`POST /api/orders` 为兼容别名）
- `POST /api/refunds`
- `POST /api/chargebacks`
- `POST /api/fraud-cases`

示例：新增交易订单

```bash
curl -X POST "http://localhost:3000/api/transaction-orders" \
  -H "Content-Type: application/json" \
  -d '{
    "merchantId": 1,
    "orderNo": "ORD-DEMO-10001",
    "cardNumberFirst6Last4": "6222021234",
    "channelName": "card",
    "orderAmount": 520.88,
    "orderCurrency": "CNY",
    "payerEmail": "alice@example.com",
    "payerName": "Alice",
    "paymentStatus": "paid"
  }'
```

## 5. 健康分说明

接口返回 `healthScore`（0-100）和 `healthLevel`：
- `healthy`：>= 85
- `watch`：70 - 84.99
- `critical`：< 70

评分受以下指标影响：
- 交易成功率（successRate）
- 退款率（refundRate）
- 拒付率（chargebackRate）
- 欺诈率（fraudRate）
