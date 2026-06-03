#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PY="$ROOT_DIR/.venv/bin/python"
RUN_DIR="$ROOT_DIR/run"
LOG_DIR="$ROOT_DIR/logs"
BOT_PID="$RUN_DIR/telegram_bot.pid"
CLI_PID="$RUN_DIR/cli.pid"
BOT_LOG="$LOG_DIR/telegram_bot.log"
CLI_LOG="$LOG_DIR/cli.log"

mkdir -p "$RUN_DIR" "$LOG_DIR"

ensure_venv_python() {
  if [[ ! -x "$VENV_PY" ]]; then
    echo "Virtual environment belum siap. Jalankan: bash setup.sh"
    exit 1
  fi
}

is_running_pid() {
  local pid_file="$1"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

start_bot() {
  ensure_venv_python
  if is_running_pid "$BOT_PID"; then
    echo "Bot sudah berjalan (PID: $(cat "$BOT_PID"))"
    return
  fi
  (cd "$ROOT_DIR" && nohup "$VENV_PY" telegram_main.py >> "$BOT_LOG" 2>&1 & echo $! > "$BOT_PID")
  echo "Bot started. PID: $(cat "$BOT_PID")"
}

stop_bot() {
  if is_running_pid "$BOT_PID"; then
    kill "$(cat "$BOT_PID")" || true
    rm -f "$BOT_PID"
    echo "Bot stopped."
  else
    echo "Bot tidak berjalan."
  fi
}

start_cli() {
  ensure_venv_python
  if is_running_pid "$CLI_PID"; then
    echo "CLI sudah berjalan (PID: $(cat "$CLI_PID"))"
    return
  fi
  (cd "$ROOT_DIR" && nohup "$VENV_PY" main.py >> "$CLI_LOG" 2>&1 & echo $! > "$CLI_PID")
  echo "CLI started. PID: $(cat "$CLI_PID")"
}

stop_cli() {
  if is_running_pid "$CLI_PID"; then
    kill "$(cat "$CLI_PID")" || true
    rm -f "$CLI_PID"
    echo "CLI stopped."
  else
    echo "CLI tidak berjalan."
  fi
}

status_all() {
  if is_running_pid "$BOT_PID"; then
    echo "Bot   : RUNNING (PID: $(cat "$BOT_PID"))"
  else
    echo "Bot   : STOPPED"
  fi

  if is_running_pid "$CLI_PID"; then
    echo "CLI   : RUNNING (PID: $(cat "$CLI_PID"))"
  else
    echo "CLI   : STOPPED"
  fi
}

setup_bot_token() {
  ensure_venv_python
  if [[ ! -f "$ROOT_DIR/.env" ]]; then
    if [[ -f "$ROOT_DIR/.env.template" ]]; then
      cp "$ROOT_DIR/.env.template" "$ROOT_DIR/.env"
      echo "Membuat file .env baru dari .env.template..."
    else
      touch "$ROOT_DIR/.env"
    fi
  fi

  read -rp "Masukkan Telegram Bot Token baru: " new_token
  if [[ -z "$new_token" ]]; then
    echo "Token tidak boleh kosong."
    return
  fi

  "$VENV_PY" -c "
import os
env_file = '$ROOT_DIR/.env'
lines = []
updated = False
if os.path.exists(env_file):
    with open(env_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
for i, line in enumerate(lines):
    if line.strip().startswith('TELEGRAM_BOT_TOKEN='):
        lines[i] = f'TELEGRAM_BOT_TOKEN=\"{new_token}\"\n'
        updated = True
        break
if not updated:
    lines.append(f'TELEGRAM_BOT_TOKEN=\"{new_token}\"\n')
with open(env_file, 'w', encoding='utf-8') as f:
    f.writelines(lines)
"
  echo "Token bot berhasil disimpan ke .env!"
}

update_panel() {
  echo "Memeriksa pembaruan pada remote repository..."
  if ! command -v git &> /dev/null; then
    echo "Error: git tidak terinstall atau tidak ditemukan di PATH."
    return
  fi

  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    echo "Error: Repositori ini bukan repositori git aktif."
    return
  fi

  git fetch
  local_commit=$(git rev-parse HEAD)
  remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "")

  if [[ -z "$remote_commit" ]]; then
    echo "Error: Tidak dapat melacak upstream branch (remote). Pastikan upstream terkonfigurasi."
    return
  fi

  if [[ "$local_commit" == "$remote_commit" ]]; then
    echo "Panel sudah menggunakan versi terbaru (Up-to-date)."
  else
    echo "⚠️ Versi baru tersedia!"
    echo "Local  Commit: ${local_commit:0:7}"
    echo "Remote Commit: ${remote_commit:0:7}"
    read -rp "Apakah Anda ingin melakukan update (git pull --rebase)? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "Melakukan update..."
      git pull --rebase
      echo "Update selesai."
    else
      echo "Update dibatalkan."
    fi
  fi
}

show_menu() {
  clear
  echo "==============================="
  echo "  Panel Control - paneldor"
  echo "==============================="
  echo "1) Start Telegram Bot"
  echo "2) Stop Telegram Bot"
  echo "3) Start CLI Background"
  echo "4) Stop CLI Background"
  echo "5) Status"
  echo "6) Tail Bot Log"
  echo "7) Tail CLI Log"
  echo "8) Update Dependencies"
  echo "9) Setup Bot Token"
  echo "10) Update Panel"
  echo "0) Exit"
  echo "-------------------------------"
}

while true; do
  show_menu
  read -rp "Pilih menu: " choice
  case "$choice" in
    1) start_bot ;;
    2) stop_bot ;;
    3) start_cli ;;
    4) stop_cli ;;
    5) status_all ;;
    6) tail -n 80 "$BOT_LOG" || true ;;
    7) tail -n 80 "$CLI_LOG" || true ;;
    8)
      ensure_venv_python
      "$VENV_PY" -m pip install --upgrade pip
      "$VENV_PY" -m pip install -r "$ROOT_DIR/requirements.txt"
      ;;
    9) setup_bot_token ;;
    10) update_panel ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
  echo
  read -rp "Tekan Enter untuk lanjut..." _
done
