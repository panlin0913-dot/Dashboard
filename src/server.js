require("dotenv").config();

const express = require("express");
const { initializeDatabase, query } = require("./config/db");

const app = express();
const port = Number(process.env.PORT || 3000);

app.use(express.json());

app.get("/", (_req, res) => {
  res.json({
    message: "Web project is running.",
  });
});

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
  });
});

app.get("/api/users", async (_req, res) => {
  try {
    const users = await query(
      "SELECT id, name, email, created_at FROM users ORDER BY id DESC",
    );
    res.json(users);
  } catch (error) {
    res.status(500).json({ error: "Failed to fetch users." });
  }
});

app.post("/api/users", async (req, res) => {
  const { name, email } = req.body;

  if (!name || !email) {
    return res.status(400).json({ error: "name and email are required." });
  }

  try {
    const result = await query("INSERT INTO users (name, email) VALUES (?, ?)", [
      name,
      email,
    ]);
    return res.status(201).json({
      id: result.insertId,
      name,
      email,
    });
  } catch (error) {
    if (error && error.code === "ER_DUP_ENTRY") {
      return res.status(409).json({ error: "Email already exists." });
    }
    return res.status(500).json({ error: "Failed to create user." });
  }
});

async function bootstrap() {
  try {
    await initializeDatabase();
    app.listen(port, () => {
      console.log(`Server started on http://localhost:${port}`);
    });
  } catch (error) {
    console.error("Failed to start application:", error.message);
    process.exit(1);
  }
}

bootstrap();
