# Payment Merchant Health Dashboard

支付平台商户健康度看板后端工程（Node.js + Express + MySQL）。

核心目标：
- 记录每个商户的订单、交易、退款、拒付、欺诈事件
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
- `orders`：订单
- `transactions`：交易结果（成功/失败/待处理）
- `refunds`：退款事件
- `chargebacks`：拒付事件
- `fraud_cases`：欺诈事件

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
- `POST /api/orders`
- `POST /api/transactions`
- `POST /api/refunds`
- `POST /api/chargebacks`
- `POST /api/fraud-cases`

示例：新增交易

```bash
curl -X POST "http://localhost:3000/api/transactions" \
  -H "Content-Type: application/json" \
  -d '{
    "merchantId": 1,
    "orderId": 1,
    "transactionNo": "TXN-DEMO-10001",
    "amount": 520.88,
    "channel": "card",
    "status": "success"
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
- 确认欺诈率（confirmedFraudRate）
