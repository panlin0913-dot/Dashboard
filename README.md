# Web + MySQL Starter

一个基础的 Web 工程（Node.js + Express），并包含对应的 MySQL 数据库初始化脚本。

## 1. 安装依赖

```bash
npm install
```

## 2. 启动 MySQL

确保本机已安装 Docker，然后运行：

```bash
docker compose up -d
```

该命令会创建并启动 MySQL，自动执行 `database/init.sql` 中的建库建表逻辑。

## 3. 配置环境变量

复制示例环境变量文件：

```bash
cp .env.example .env
```

默认配置如下：

- 数据库：`web_app_db`
- 用户名：`app_user`
- 密码：`app_password`
- 服务端口：`3000`

## 4. 启动 Web 服务

开发模式：

```bash
npm run dev
```

生产模式：

```bash
npm start
```

## 5. API 示例

- `GET /health`：健康检查
- `GET /api/users`：查询用户列表
- `POST /api/users`：新增用户

示例请求：

```bash
curl -X POST "http://localhost:3000/api/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Alice","email":"alice@example.com"}'
```
