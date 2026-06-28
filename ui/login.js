const DEMO_USER = "admin";
const DEMO_PASS = "admin123";
const AUTH_KEY = "pay_monitor_auth";

function setMessage(text, isError = false) {
  const el = document.getElementById("loginMessage");
  el.textContent = text;
  el.classList.toggle("error", isError);
}

function handleLogin(event) {
  event.preventDefault();
  const username = document.getElementById("usernameInput").value.trim();
  const password = document.getElementById("passwordInput").value;

  if (username === DEMO_USER && password === DEMO_PASS) {
    sessionStorage.setItem(
      AUTH_KEY,
      JSON.stringify({
        username,
        loginAt: new Date().toISOString(),
      })
    );
    window.location.href = "/dashboard";
    return;
  }

  setMessage("用户名或密码错误，请重试。", true);
}

function init() {
  const existing = sessionStorage.getItem(AUTH_KEY);
  if (existing) {
    window.location.href = "/dashboard";
    return;
  }

  document.getElementById("loginForm").addEventListener("submit", handleLogin);
}

init();
