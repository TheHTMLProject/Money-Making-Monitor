#!/bin/bash
# =============================================================================
# Money-Making Monitor — Cross-Platform Passive Income Service Monitor
# =============================================================================
# Monitors EarnApp, Honeygain, and Grass across Windows, macOS, and Linux.
# On Linux, Honeygain and Grass are monitored as Docker containers.
# On Windows and macOS, all three are monitored as native applications.
#
# Reads configuration from install.sh config file. Run install.sh first.
#
# Usage: bash monitor.sh
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# Color Palette & Symbols
# ─────────────────────────────────────────────────────────────────────────────

BLUE='\e[1;34m'
CYAN='\e[1;36m'
GREEN='\e[1;32m'
RED='\e[1;31m'
YELLOW='\e[1;33m'
MAGENTA='\e[1;35m'
WHITE='\e[1;37m'
DIM='\e[2m'
NC='\e[0m'
BG_SELECT='\e[1;7m'
BOLD='\e[1m'
UNDERLINE='\e[4m'

# Unicode symbols
SYM_CHECK="✔"
SYM_CROSS="✘"
SYM_WARN="⚠"
SYM_ARROW="▶"
SYM_CIRCLE="●"
SYM_DASH="─"
SYM_BOX_TL="╔"
SYM_BOX_TR="╗"
SYM_BOX_BL="╚"
SYM_BOX_BR="╝"
SYM_BOX_H="═"
SYM_BOX_V="║"
SYM_RELOAD="↻"
SYM_CLOCK="◷"

# ─────────────────────────────────────────────────────────────────────────────
# Global Configuration (defaults — overridden by config file)
# ─────────────────────────────────────────────────────────────────────────────

MONITOR_INTERVAL=30
RESTART_COOLDOWN=60
MAX_RESTART_ATTEMPTS=3
AUTO_RESTART_ENABLED=true
LOG_DIR=""
LOG_FILE=""
OS_TYPE=""
DOCKER_AVAILABLE=false
CONFIG_DIR=""
CONFIG_FILE=""

# Service enable flags (from config)
MONITOR_EARNAPP=true
MONITOR_HONEYGAIN=true
MONITOR_GRASS=true

# Discord webhook
DISCORD_WEBHOOK_URL=""

# Service tracking arrays
declare -A SERVICE_STATUS
declare -A SERVICE_UPTIME
declare -A RESTART_COUNTS
declare -A LAST_RESTART_TIME

# Discord notification state — prevents spamming the same alert
declare -A NOTIFIED_DOWN      # Tracks whether we already sent a "down" alert
declare -A NOTIFIED_UP        # Tracks whether we already sent a "recovered" alert

# ─────────────────────────────────────────────────────────────────────────────
# Service Definitions — Process Names & Docker Images
# ─────────────────────────────────────────────────────────────────────────────

EARNAPP_PROC_LINUX="earnapp"
EARNAPP_PROC_MACOS="EarnApp"
EARNAPP_PROC_WINDOWS="earnapp.exe"
EARNAPP_SERVICE_LINUX="earnapp"
EARNAPP_CLI="earnapp"

HONEYGAIN_DOCKER_IMAGE="honeygain/honeygain"
HONEYGAIN_CONTAINER_NAME="honeygain"
HONEYGAIN_PROC_MACOS="Honeygain"
HONEYGAIN_PROC_WINDOWS="Honeygain.exe"

GRASS_DOCKER_IMAGE="mrcolorrain/grass"
GRASS_CONTAINER_NAME="grass"
GRASS_PROC_MACOS="Grass"
GRASS_PROC_WINDOWS="Grass.exe"

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

get_timestamp() {
    date +%s 2>/dev/null || python3 -c "import time; print(int(time.time()))" 2>/dev/null || echo "0"
}

format_duration() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    elif [ "$seconds" -lt 86400 ]; then
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    else
        echo "$((seconds / 86400))d $((seconds % 86400 / 3600))h"
    fi
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    if [ -n "$LOG_FILE" ] && [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null
    fi
}

draw_line() {
    local char="${1:-─}"
    local width="${2:-56}"
    local line=""
    for ((i = 0; i < width; i++)); do
        line="${line}${char}"
    done
    echo -e "${DIM}${line}${NC}"
}

draw_box_line() {
    local text="$1"
    local width="${2:-56}"
    local clean_text
    clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local clean_len=${#clean_text}
    local pad=$((width - clean_len - 4))
    if [ "$pad" -lt 0 ]; then pad=0; fi
    local padding=""
    for ((i = 0; i < pad; i++)); do
        padding="${padding} "
    done
    echo -e "${BLUE}${SYM_BOX_V}${NC} ${text}${padding} ${BLUE}${SYM_BOX_V}${NC}"
}

print_centered() {
    local text="$1"
    local width="${2:-56}"
    local clean_text
    clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_len=${#clean_text}
    local pad_left=$(( (width - text_len) / 2 ))
    local padding=""
    for ((i = 0; i < pad_left; i++)); do
        padding="${padding} "
    done
    echo -e "${padding}${text}"
}

draw_header() {
    local title="$1"
    local subtitle="$2"
    echo ""
    echo -e "${BLUE}${SYM_BOX_TL}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_TR}${NC}"
    draw_box_line ""
    draw_box_line "$(print_centered "${CYAN}${BOLD}${title}${NC}" 52)"
    if [ -n "$subtitle" ]; then
        draw_box_line "$(print_centered "${DIM}${subtitle}${NC}" 52)"
    fi
    draw_box_line ""
    echo -e "${BLUE}${SYM_BOX_BL}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_H}${SYM_BOX_BR}${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# OS Detection & Environment Setup
# ─────────────────────────────────────────────────────────────────────────────

detect_os() {
    local uname_out
    uname_out=$(uname -s 2>/dev/null || echo "Unknown")

    case "$uname_out" in
        Linux*)
            OS_TYPE="linux"
            CONFIG_DIR="${HOME}/.config/money-monitor"
            LOG_DIR="${HOME}/.local/share/money-monitor"
            ;;
        Darwin*)
            OS_TYPE="macos"
            CONFIG_DIR="${HOME}/.config/money-monitor"
            LOG_DIR="${HOME}/Library/Logs/money-monitor"
            ;;
        CYGWIN*|MINGW*|MSYS*|Windows_NT*)
            OS_TYPE="windows"
            if [ -n "$APPDATA" ]; then
                CONFIG_DIR="${APPDATA}/money-monitor"
                LOG_DIR="${APPDATA}/money-monitor/logs"
            else
                CONFIG_DIR="${HOME}/.config/money-monitor"
                LOG_DIR="${HOME}/.money-monitor/logs"
            fi
            ;;
        *)
            OS_TYPE="unknown"
            CONFIG_DIR="${HOME}/.config/money-monitor"
            LOG_DIR="${HOME}/.money-monitor"
            ;;
    esac

    CONFIG_FILE="${CONFIG_DIR}/config.conf"
    mkdir -p "$LOG_DIR" 2>/dev/null
    LOG_FILE="${LOG_DIR}/monitor.log"

    # Check Docker availability
    if command -v docker &>/dev/null; then
        if docker info &>/dev/null; then
            DOCKER_AVAILABLE=true
        fi
    fi

    log_message "INFO" "OS detected: ${OS_TYPE} | Docker: ${DOCKER_AVAILABLE}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Config File Loading
# ─────────────────────────────────────────────────────────────────────────────

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | tr -d ' ')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$key" in
            MONITOR_EARNAPP)      MONITOR_EARNAPP="$value" ;;
            MONITOR_HONEYGAIN)    MONITOR_HONEYGAIN="$value" ;;
            MONITOR_GRASS)        MONITOR_GRASS="$value" ;;
            DISCORD_WEBHOOK_URL)  DISCORD_WEBHOOK_URL="$value" ;;
            MONITOR_INTERVAL)     MONITOR_INTERVAL="$value" ;;
            RESTART_COOLDOWN)     RESTART_COOLDOWN="$value" ;;
            MAX_RESTART_ATTEMPTS) MAX_RESTART_ATTEMPTS="$value" ;;
            AUTO_RESTART_ENABLED) AUTO_RESTART_ENABLED="$value" ;;
        esac
    done < "$CONFIG_FILE"

    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Discord Webhook Notifications
# ─────────────────────────────────────────────────────────────────────────────

# Send a Discord webhook embed message
# $1 = title, $2 = description, $3 = color (decimal), $4 = service name, $5 = status
send_discord_notification() {
    local title="$1"
    local description="$2"
    local color="$3"
    local service_name="$4"
    local status="$5"

    # Skip if no webhook configured
    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        return 0
    fi

    local os_label
    case "$OS_TYPE" in
        linux)   os_label="Linux" ;;
        macos)   os_label="macOS" ;;
        windows) os_label="Windows" ;;
        *)       os_label="Unknown" ;;
    esac

    local hostname_val
    hostname_val=$(hostname 2>/dev/null || echo "unknown")

    local timestamp_iso
    timestamp_iso=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2024-01-01T00:00:00Z")

    local payload
    payload=$(cat <<ENDJSON
{
  "embeds": [{
    "title": "${title}",
    "description": "${description}",
    "color": ${color},
    "fields": [
      { "name": "Service", "value": "${service_name}", "inline": true },
      { "name": "Status", "value": "${status}", "inline": true },
      { "name": "Host", "value": "${hostname_val} (${os_label})", "inline": true }
    ],
    "footer": { "text": "Money-Making Monitor" },
    "timestamp": "${timestamp_iso}"
  }]
}
ENDJSON
)

    # Fire-and-forget with a short timeout, run in background to not block
    curl -s -o /dev/null -w "" \
        --connect-timeout 5 \
        --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DISCORD_WEBHOOK_URL" &>/dev/null &

    log_message "INFO" "Discord notification sent: ${title} — ${service_name} ${status}"
}

# Send a "service down" notification (only once per outage)
notify_service_down() {
    local service="$1"
    local status="${2:-stopped}"

    # Only notify once per outage
    if [ "${NOTIFIED_DOWN[$service]}" = "true" ]; then
        return
    fi

    NOTIFIED_DOWN[$service]="true"
    NOTIFIED_UP[$service]="false"

    local friendly_name
    case "$service" in
        earnapp)   friendly_name="EarnApp" ;;
        honeygain) friendly_name="Honeygain" ;;
        grass)     friendly_name="Grass" ;;
        *)         friendly_name="$service" ;;
    esac

    send_discord_notification \
        "🔴 ${friendly_name} is DOWN" \
        "${friendly_name} has stopped running and is no longer earning. $([ "$AUTO_RESTART_ENABLED" = "true" ] && echo "Auto-restart will be attempted." || echo "Auto-restart is disabled.")" \
        "15548997" \
        "$friendly_name" \
        "$status"

    log_message "WARN" "${friendly_name} went down — Discord notification sent"
}

# Send a "service recovered" notification (only once per recovery)
notify_service_recovered() {
    local service="$1"

    # Only notify if we previously notified about being down
    if [ "${NOTIFIED_DOWN[$service]}" != "true" ]; then
        return
    fi

    # Only notify recovery once
    if [ "${NOTIFIED_UP[$service]}" = "true" ]; then
        return
    fi

    NOTIFIED_DOWN[$service]="false"
    NOTIFIED_UP[$service]="true"

    local friendly_name
    case "$service" in
        earnapp)   friendly_name="EarnApp" ;;
        honeygain) friendly_name="Honeygain" ;;
        grass)     friendly_name="Grass" ;;
        *)         friendly_name="$service" ;;
    esac

    send_discord_notification \
        "🟢 ${friendly_name} is BACK ONLINE" \
        "${friendly_name} has recovered and is running again." \
        "5763719" \
        "$friendly_name" \
        "running"

    log_message "INFO" "${friendly_name} recovered — Discord notification sent"
}

# ─────────────────────────────────────────────────────────────────────────────
# Process / Container Detection (Cross-Platform)
# ─────────────────────────────────────────────────────────────────────────────

is_process_running() {
    local proc_name="$1"

    case "$OS_TYPE" in
        linux)
            pgrep -f "$proc_name" &>/dev/null
            return $?
            ;;
        macos)
            pgrep -f "$proc_name" &>/dev/null
            return $?
            ;;
        windows)
            tasklist.exe 2>/dev/null | grep -qi "$proc_name"
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

get_process_stats() {
    local proc_name="$1"
    local cpu="N/A"
    local mem="N/A"
    local pid=""

    case "$OS_TYPE" in
        linux)
            pid=$(pgrep -f "$proc_name" 2>/dev/null | head -1)
            if [ -n "$pid" ]; then
                cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
                mem=$(ps -p "$pid" -o %mem= 2>/dev/null | tr -d ' ')
            fi
            ;;
        macos)
            pid=$(pgrep -f "$proc_name" 2>/dev/null | head -1)
            if [ -n "$pid" ]; then
                cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
                mem=$(ps -p "$pid" -o %mem= 2>/dev/null | tr -d ' ')
            fi
            ;;
        windows)
            local info
            info=$(tasklist.exe /FI "IMAGENAME eq ${proc_name}" /FO CSV /V 2>/dev/null | tail -1)
            if [ -n "$info" ]; then
                mem=$(echo "$info" | awk -F'","' '{print $5}' | tr -d '"' | tr -d ' ')
                cpu="—"
            fi
            ;;
    esac

    echo "${cpu}|${mem}"
}

is_container_running() {
    local container_name="$1"

    if [ "$DOCKER_AVAILABLE" != true ]; then
        return 1
    fi

    local state
    state=$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)
    if [ "$state" = "true" ]; then
        return 0
    fi

    docker ps --format '{{.Image}}' 2>/dev/null | grep -q "$container_name"
    return $?
}

get_container_stats() {
    local container_name="$1"
    local cpu="N/A"
    local mem="N/A"

    if [ "$DOCKER_AVAILABLE" != true ]; then
        echo "${cpu}|${mem}"
        return
    fi

    local stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}}|{{.MemPerc}}" "$container_name" 2>/dev/null)
    if [ -n "$stats" ]; then
        echo "$stats"
    else
        echo "${cpu}|${mem}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Status Checks
# ─────────────────────────────────────────────────────────────────────────────

check_earnapp() {
    # Skip if disabled in config
    if [ "$MONITOR_EARNAPP" != "true" ]; then
        SERVICE_STATUS[earnapp]="disabled"
        SERVICE_STATUS[earnapp_cpu]="—"
        SERVICE_STATUS[earnapp_mem]="—"
        return
    fi

    local proc_name=""
    case "$OS_TYPE" in
        linux)  proc_name="$EARNAPP_PROC_LINUX" ;;
        macos)  proc_name="$EARNAPP_PROC_MACOS" ;;
        windows) proc_name="$EARNAPP_PROC_WINDOWS" ;;
    esac

    # Primary check: process detection
    if is_process_running "$proc_name"; then
        SERVICE_STATUS[earnapp]="running"
        local stats
        stats=$(get_process_stats "$proc_name")
        SERVICE_STATUS[earnapp_cpu]=$(echo "$stats" | cut -d'|' -f1)
        SERVICE_STATUS[earnapp_mem]=$(echo "$stats" | cut -d'|' -f2)
        notify_service_recovered "earnapp"
        return
    fi

    # Fallback on Linux: try the earnapp CLI or systemd
    if [ "$OS_TYPE" = "linux" ]; then
        if command -v "$EARNAPP_CLI" &>/dev/null; then
            local cli_status
            cli_status=$(earnapp status 2>/dev/null)
            if echo "$cli_status" | grep -qi "running"; then
                SERVICE_STATUS[earnapp]="running"
                SERVICE_STATUS[earnapp_cpu]="—"
                SERVICE_STATUS[earnapp_mem]="—"
                notify_service_recovered "earnapp"
                return
            fi
        fi
        if systemctl is-active --quiet earnapp.service 2>/dev/null; then
            SERVICE_STATUS[earnapp]="running"
            SERVICE_STATUS[earnapp_cpu]="—"
            SERVICE_STATUS[earnapp_mem]="—"
            notify_service_recovered "earnapp"
            return
        fi
    fi

    SERVICE_STATUS[earnapp]="stopped"
    SERVICE_STATUS[earnapp_cpu]="—"
    SERVICE_STATUS[earnapp_mem]="—"
    notify_service_down "earnapp" "stopped"
}

check_honeygain() {
    # Skip if disabled in config
    if [ "$MONITOR_HONEYGAIN" != "true" ]; then
        SERVICE_STATUS[honeygain]="disabled"
        SERVICE_STATUS[honeygain_cpu]="—"
        SERVICE_STATUS[honeygain_mem]="—"
        return
    fi

    if [ "$OS_TYPE" = "linux" ]; then
        # Docker container check
        if is_container_running "$HONEYGAIN_CONTAINER_NAME"; then
            SERVICE_STATUS[honeygain]="running"
            local stats
            stats=$(get_container_stats "$HONEYGAIN_CONTAINER_NAME")
            SERVICE_STATUS[honeygain_cpu]=$(echo "$stats" | cut -d'|' -f1)
            SERVICE_STATUS[honeygain_mem]=$(echo "$stats" | cut -d'|' -f2)
            notify_service_recovered "honeygain"
        else
            local container_id
            container_id=$(docker ps -a --filter "ancestor=${HONEYGAIN_DOCKER_IMAGE}" --format "{{.ID}}" 2>/dev/null | head -1)
            if [ -n "$container_id" ]; then
                local state
                state=$(docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null)
                SERVICE_STATUS[honeygain]="$state"
            else
                SERVICE_STATUS[honeygain]="not found"
            fi
            SERVICE_STATUS[honeygain_cpu]="—"
            SERVICE_STATUS[honeygain_mem]="—"
            notify_service_down "honeygain" "${SERVICE_STATUS[honeygain]}"
        fi
    else
        local proc_name=""
        case "$OS_TYPE" in
            macos)   proc_name="$HONEYGAIN_PROC_MACOS" ;;
            windows) proc_name="$HONEYGAIN_PROC_WINDOWS" ;;
        esac

        if is_process_running "$proc_name"; then
            SERVICE_STATUS[honeygain]="running"
            local stats
            stats=$(get_process_stats "$proc_name")
            SERVICE_STATUS[honeygain_cpu]=$(echo "$stats" | cut -d'|' -f1)
            SERVICE_STATUS[honeygain_mem]=$(echo "$stats" | cut -d'|' -f2)
            notify_service_recovered "honeygain"
        else
            SERVICE_STATUS[honeygain]="stopped"
            SERVICE_STATUS[honeygain_cpu]="—"
            SERVICE_STATUS[honeygain_mem]="—"
            notify_service_down "honeygain" "stopped"
        fi
    fi
}

check_grass() {
    # Skip if disabled in config
    if [ "$MONITOR_GRASS" != "true" ]; then
        SERVICE_STATUS[grass]="disabled"
        SERVICE_STATUS[grass_cpu]="—"
        SERVICE_STATUS[grass_mem]="—"
        return
    fi

    if [ "$OS_TYPE" = "linux" ]; then
        # Docker container check
        if is_container_running "$GRASS_CONTAINER_NAME"; then
            SERVICE_STATUS[grass]="running"
            local stats
            stats=$(get_container_stats "$GRASS_CONTAINER_NAME")
            SERVICE_STATUS[grass_cpu]=$(echo "$stats" | cut -d'|' -f1)
            SERVICE_STATUS[grass_mem]=$(echo "$stats" | cut -d'|' -f2)
            notify_service_recovered "grass"
        else
            local container_id
            container_id=$(docker ps -a --filter "ancestor=${GRASS_DOCKER_IMAGE}" --format "{{.ID}}" 2>/dev/null | head -1)
            if [ -n "$container_id" ]; then
                local state
                state=$(docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null)
                SERVICE_STATUS[grass]="$state"
            else
                SERVICE_STATUS[grass]="not found"
            fi
            SERVICE_STATUS[grass_cpu]="—"
            SERVICE_STATUS[grass_mem]="—"
            notify_service_down "grass" "${SERVICE_STATUS[grass]}"
        fi
    else
        local proc_name=""
        case "$OS_TYPE" in
            macos)   proc_name="$GRASS_PROC_MACOS" ;;
            windows) proc_name="$GRASS_PROC_WINDOWS" ;;
        esac

        if is_process_running "$proc_name"; then
            SERVICE_STATUS[grass]="running"
            local stats
            stats=$(get_process_stats "$proc_name")
            SERVICE_STATUS[grass_cpu]=$(echo "$stats" | cut -d'|' -f1)
            SERVICE_STATUS[grass_mem]=$(echo "$stats" | cut -d'|' -f2)
            notify_service_recovered "grass"
        else
            SERVICE_STATUS[grass]="stopped"
            SERVICE_STATUS[grass_cpu]="—"
            SERVICE_STATUS[grass_mem]="—"
            notify_service_down "grass" "stopped"
        fi
    fi
}

check_all_services() {
    check_earnapp
    check_honeygain
    check_grass
}

# ─────────────────────────────────────────────────────────────────────────────
# Service Restart Logic
# ─────────────────────────────────────────────────────────────────────────────

restart_earnapp() {
    if [ "$MONITOR_EARNAPP" != "true" ]; then
        echo -e "  ${DIM}EarnApp monitoring is disabled — skipping${NC}"
        return 1
    fi

    local now
    now=$(get_timestamp)
    local last_restart="${LAST_RESTART_TIME[earnapp]:-0}"
    local count="${RESTART_COUNTS[earnapp]:-0}"

    if [ $((now - last_restart)) -lt "$RESTART_COOLDOWN" ]; then
        echo -e "  ${YELLOW}${SYM_WARN} EarnApp restart on cooldown (${RESTART_COOLDOWN}s)${NC}"
        return 1
    fi

    if [ "$count" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        echo -e "  ${RED}${SYM_CROSS} EarnApp exceeded max restart attempts (${MAX_RESTART_ATTEMPTS})${NC}"
        log_message "ERROR" "EarnApp exceeded max restart attempts"
        return 1
    fi

    echo -e "  ${YELLOW}${SYM_RELOAD} Attempting to restart EarnApp...${NC}"
    log_message "INFO" "Restarting EarnApp (attempt $((count + 1)))"

    case "$OS_TYPE" in
        linux)
            if systemctl restart earnapp 2>/dev/null; then
                echo -e "  ${GREEN}${SYM_CHECK} EarnApp restarted via systemd${NC}"
            elif [ -x "/opt/earnapp/bin/earnapp" ]; then
                nohup /opt/earnapp/bin/earnapp &>/dev/null &
                echo -e "  ${GREEN}${SYM_CHECK} EarnApp started directly${NC}"
            else
                echo -e "  ${RED}${SYM_CROSS} Could not find EarnApp binary to restart${NC}"
                return 1
            fi
            ;;
        macos)
            if [ -d "/Applications/EarnApp.app" ]; then
                open -a "EarnApp" 2>/dev/null
                echo -e "  ${GREEN}${SYM_CHECK} EarnApp restarted via open command${NC}"
            else
                echo -e "  ${RED}${SYM_CROSS} EarnApp.app not found in /Applications${NC}"
                return 1
            fi
            ;;
        windows)
            local earnapp_path=""
            for path in \
                "${LOCALAPPDATA}/Programs/EarnApp/earnapp.exe" \
                "${PROGRAMFILES}/EarnApp/earnapp.exe" \
                "${PROGRAMFILES} (x86)/EarnApp/earnapp.exe" \
                "${APPDATA}/EarnApp/earnapp.exe"; do
                if [ -f "$path" ]; then
                    earnapp_path="$path"
                    break
                fi
            done
            if [ -n "$earnapp_path" ]; then
                cmd.exe /C "start \"\" \"$(cygpath -w "$earnapp_path")\"" 2>/dev/null
                echo -e "  ${GREEN}${SYM_CHECK} EarnApp restarted${NC}"
            else
                echo -e "  ${RED}${SYM_CROSS} EarnApp executable not found${NC}"
                return 1
            fi
            ;;
    esac

    RESTART_COUNTS[earnapp]=$((count + 1))
    LAST_RESTART_TIME[earnapp]=$now
    return 0
}

restart_honeygain() {
    if [ "$MONITOR_HONEYGAIN" != "true" ]; then
        echo -e "  ${DIM}Honeygain monitoring is disabled — skipping${NC}"
        return 1
    fi

    local now
    now=$(get_timestamp)
    local last_restart="${LAST_RESTART_TIME[honeygain]:-0}"
    local count="${RESTART_COUNTS[honeygain]:-0}"

    if [ $((now - last_restart)) -lt "$RESTART_COOLDOWN" ]; then
        echo -e "  ${YELLOW}${SYM_WARN} Honeygain restart on cooldown (${RESTART_COOLDOWN}s)${NC}"
        return 1
    fi

    if [ "$count" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        echo -e "  ${RED}${SYM_CROSS} Honeygain exceeded max restart attempts (${MAX_RESTART_ATTEMPTS})${NC}"
        log_message "ERROR" "Honeygain exceeded max restart attempts"
        return 1
    fi

    echo -e "  ${YELLOW}${SYM_RELOAD} Attempting to restart Honeygain...${NC}"
    log_message "INFO" "Restarting Honeygain (attempt $((count + 1)))"

    if [ "$OS_TYPE" = "linux" ]; then
        if [ "$DOCKER_AVAILABLE" = true ]; then
            docker restart "$HONEYGAIN_CONTAINER_NAME" &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "  ${GREEN}${SYM_CHECK} Honeygain container restarted${NC}"
            else
                docker start "$HONEYGAIN_CONTAINER_NAME" &>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "  ${GREEN}${SYM_CHECK} Honeygain container started${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Failed to restart Honeygain container${NC}"
                    return 1
                fi
            fi
        else
            echo -e "  ${RED}${SYM_CROSS} Docker is not available${NC}"
            return 1
        fi
    else
        case "$OS_TYPE" in
            macos)
                if [ -d "/Applications/Honeygain.app" ]; then
                    open -a "Honeygain" 2>/dev/null
                    echo -e "  ${GREEN}${SYM_CHECK} Honeygain restarted via open command${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Honeygain.app not found${NC}"
                    return 1
                fi
                ;;
            windows)
                local hg_path=""
                for path in \
                    "${APPDATA}/Honeygain/Honeygain.exe" \
                    "${LOCALAPPDATA}/Programs/Honeygain/Honeygain.exe" \
                    "${PROGRAMFILES}/Honeygain/Honeygain.exe"; do
                    if [ -f "$path" ]; then
                        hg_path="$path"
                        break
                    fi
                done
                if [ -n "$hg_path" ]; then
                    cmd.exe /C "start \"\" \"$(cygpath -w "$hg_path")\"" 2>/dev/null
                    echo -e "  ${GREEN}${SYM_CHECK} Honeygain restarted${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Honeygain executable not found${NC}"
                    return 1
                fi
                ;;
        esac
    fi

    RESTART_COUNTS[honeygain]=$((count + 1))
    LAST_RESTART_TIME[honeygain]=$now
    return 0
}

restart_grass() {
    if [ "$MONITOR_GRASS" != "true" ]; then
        echo -e "  ${DIM}Grass monitoring is disabled — skipping${NC}"
        return 1
    fi

    local now
    now=$(get_timestamp)
    local last_restart="${LAST_RESTART_TIME[grass]:-0}"
    local count="${RESTART_COUNTS[grass]:-0}"

    if [ $((now - last_restart)) -lt "$RESTART_COOLDOWN" ]; then
        echo -e "  ${YELLOW}${SYM_WARN} Grass restart on cooldown (${RESTART_COOLDOWN}s)${NC}"
        return 1
    fi

    if [ "$count" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        echo -e "  ${RED}${SYM_CROSS} Grass exceeded max restart attempts (${MAX_RESTART_ATTEMPTS})${NC}"
        log_message "ERROR" "Grass exceeded max restart attempts"
        return 1
    fi

    echo -e "  ${YELLOW}${SYM_RELOAD} Attempting to restart Grass...${NC}"
    log_message "INFO" "Restarting Grass (attempt $((count + 1)))"

    if [ "$OS_TYPE" = "linux" ]; then
        if [ "$DOCKER_AVAILABLE" = true ]; then
            docker restart "$GRASS_CONTAINER_NAME" &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "  ${GREEN}${SYM_CHECK} Grass container restarted${NC}"
            else
                docker start "$GRASS_CONTAINER_NAME" &>/dev/null
                if [ $? -eq 0 ]; then
                    echo -e "  ${GREEN}${SYM_CHECK} Grass container started${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Failed to restart Grass container${NC}"
                    return 1
                fi
            fi
        else
            echo -e "  ${RED}${SYM_CROSS} Docker is not available${NC}"
            return 1
        fi
    else
        case "$OS_TYPE" in
            macos)
                if [ -d "/Applications/Grass.app" ]; then
                    open -a "Grass" 2>/dev/null
                    echo -e "  ${GREEN}${SYM_CHECK} Grass restarted via open command${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Grass.app not found${NC}"
                    return 1
                fi
                ;;
            windows)
                local grass_path=""
                for path in \
                    "${LOCALAPPDATA}/Programs/Grass/Grass.exe" \
                    "${PROGRAMFILES}/Grass/Grass.exe" \
                    "${APPDATA}/Grass/Grass.exe"; do
                    if [ -f "$path" ]; then
                        grass_path="$path"
                        break
                    fi
                done
                if [ -n "$grass_path" ]; then
                    cmd.exe /C "start \"\" \"$(cygpath -w "$grass_path")\"" 2>/dev/null
                    echo -e "  ${GREEN}${SYM_CHECK} Grass restarted${NC}"
                else
                    echo -e "  ${RED}${SYM_CROSS} Grass executable not found${NC}"
                    return 1
                fi
                ;;
        esac
    fi

    RESTART_COUNTS[grass]=$((count + 1))
    LAST_RESTART_TIME[grass]=$now
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Display Functions
# ─────────────────────────────────────────────────────────────────────────────

status_indicator() {
    local status="$1"
    case "$status" in
        running)
            echo -e "${GREEN}${SYM_CIRCLE} RUNNING${NC}"
            ;;
        stopped)
            echo -e "${RED}${SYM_CIRCLE} STOPPED${NC}"
            ;;
        exited)
            echo -e "${RED}${SYM_CIRCLE} EXITED${NC}"
            ;;
        disabled)
            echo -e "${DIM}${SYM_CIRCLE} DISABLED${NC}"
            ;;
        "not found")
            echo -e "${DIM}${SYM_CIRCLE} NOT FOUND${NC}"
            ;;
        *)
            echo -e "${YELLOW}${SYM_CIRCLE} ${status^^}${NC}"
            ;;
    esac
}

mode_label() {
    local service="$1"
    if [ "$OS_TYPE" = "linux" ] && { [ "$service" = "honeygain" ] || [ "$service" = "grass" ]; }; then
        echo -e "${CYAN}[Docker]${NC}"
    else
        echo -e "${MAGENTA}[Native]${NC}"
    fi
}

# Build the list of monitored services (respecting config)
get_enabled_services() {
    local services=()
    [ "$MONITOR_EARNAPP" = "true" ] && services+=("earnapp")
    [ "$MONITOR_HONEYGAIN" = "true" ] && services+=("honeygain")
    [ "$MONITOR_GRASS" = "true" ] && services+=("grass")
    echo "${services[@]}"
}

display_dashboard() {
    clear
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    local os_label
    case "$OS_TYPE" in
        linux)   os_label="Linux" ;;
        macos)   os_label="macOS" ;;
        windows) os_label="Windows" ;;
        *)       os_label="Unknown" ;;
    esac

    draw_header "MONEY-MAKING MONITOR" "Passive Income Service Dashboard"
    echo ""
    echo -e "  ${DIM}${SYM_CLOCK} ${timestamp}  |  OS: ${os_label}  |  Docker: $([ "$DOCKER_AVAILABLE" = true ] && echo "${GREEN}Yes${NC}" || echo "${RED}No${NC}")${NC}"

    # Webhook status
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        echo -e "  ${DIM}Webhook: ${GREEN}${SYM_CHECK} Configured${NC}"
    else
        echo -e "  ${DIM}Webhook: ${YELLOW}${SYM_WARN} Not configured${NC}"
    fi
    echo ""
    draw_line "─" 56

    # ── EarnApp ──
    echo ""
    local ea_status
    ea_status=$(status_indicator "${SERVICE_STATUS[earnapp]}")
    echo -e "  ${WHITE}${BOLD}EarnApp${NC}  $(mode_label earnapp)  ${ea_status}"
    if [ "${SERVICE_STATUS[earnapp]}" = "running" ]; then
        echo -e "  ${DIM}CPU: ${SERVICE_STATUS[earnapp_cpu]}%  |  MEM: ${SERVICE_STATUS[earnapp_mem]}%${NC}"
    elif [ "${SERVICE_STATUS[earnapp]}" = "disabled" ]; then
        echo -e "  ${DIM}Monitoring disabled in config${NC}"
    fi

    draw_line "─" 56

    # ── Honeygain ──
    echo ""
    local hg_status
    hg_status=$(status_indicator "${SERVICE_STATUS[honeygain]}")
    echo -e "  ${WHITE}${BOLD}Honeygain${NC}  $(mode_label honeygain)  ${hg_status}"
    if [ "${SERVICE_STATUS[honeygain]}" = "running" ]; then
        echo -e "  ${DIM}CPU: ${SERVICE_STATUS[honeygain_cpu]}  |  MEM: ${SERVICE_STATUS[honeygain_mem]}${NC}"
    elif [ "${SERVICE_STATUS[honeygain]}" = "disabled" ]; then
        echo -e "  ${DIM}Monitoring disabled in config${NC}"
    fi

    draw_line "─" 56

    # ── Grass ──
    echo ""
    local gr_status
    gr_status=$(status_indicator "${SERVICE_STATUS[grass]}")
    echo -e "  ${WHITE}${BOLD}Grass${NC}  $(mode_label grass)  ${gr_status}"
    if [ "${SERVICE_STATUS[grass]}" = "running" ]; then
        echo -e "  ${DIM}CPU: ${SERVICE_STATUS[grass_cpu]}  |  MEM: ${SERVICE_STATUS[grass_mem]}${NC}"
    elif [ "${SERVICE_STATUS[grass]}" = "disabled" ]; then
        echo -e "  ${DIM}Monitoring disabled in config${NC}"
    fi

    echo ""
    draw_line "═" 56

    # Summary line
    local running=0
    local monitored=0
    for svc in earnapp honeygain grass; do
        if [ "${SERVICE_STATUS[$svc]}" != "disabled" ]; then
            ((monitored++))
            [ "${SERVICE_STATUS[$svc]}" = "running" ] && ((running++))
        fi
    done

    local summary_color="$GREEN"
    if [ "$running" -eq 0 ] && [ "$monitored" -gt 0 ]; then
        summary_color="$RED"
    elif [ "$running" -lt "$monitored" ]; then
        summary_color="$YELLOW"
    fi

    echo -e "  ${summary_color}${BOLD}${running}/${monitored} services online${NC}  ${DIM}|  Log: ${LOG_FILE}${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Interactive Menu System
# ─────────────────────────────────────────────────────────────────────────────

options=(
    "View Live Dashboard (All Services)"
    "Check Service Status (One-Time)"
    "Start Continuous Monitoring (Auto-Restart)"
    "Restart All Stopped Services"
    "Restart Individual Service"
    "View Monitor Logs"
    "Configure Settings"
)
selected=0

cleanup() {
    tput cnorm 2>/dev/null
    echo -e "\n${RED}${SYM_CROSS} Monitor terminated.${NC}"
    log_message "INFO" "Monitor script terminated by user"
    exit 0
}
trap cleanup SIGINT SIGTERM

print_menu() {
    clear
    draw_header "MONEY-MAKING MONITOR" "EarnApp · Honeygain · Grass"
    echo ""

    local os_label
    case "$OS_TYPE" in
        linux)   os_label="Linux" ;;
        macos)   os_label="macOS" ;;
        windows) os_label="Windows" ;;
        *)       os_label="Unknown" ;;
    esac

    # Show enabled services count
    local enabled=0
    [ "$MONITOR_EARNAPP" = "true" ] && ((enabled++))
    [ "$MONITOR_HONEYGAIN" = "true" ] && ((enabled++))
    [ "$MONITOR_GRASS" = "true" ] && ((enabled++))

    echo -e "  ${DIM}OS: ${os_label} | Docker: $([ "$DOCKER_AVAILABLE" = true ] && echo "Available" || echo "Unavailable") | Services: ${enabled}/3${NC}"

    # Webhook indicator
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        echo -e "  ${DIM}Webhook: ${GREEN}${SYM_CHECK} Active${NC}"
    else
        echo -e "  ${DIM}Webhook: ${YELLOW}${SYM_WARN} Not set — run install.sh${NC}"
    fi

    echo -e "  ${DIM}[↑/↓] Move  |  [Enter] Select  |  [Esc] Exit${NC}"
    draw_line "─" 56
    echo ""

    for i in "${!options[@]}"; do
        if [ "$i" -eq "$selected" ]; then
            printf "  ${GREEN}${SYM_ARROW}${NC} ${BG_SELECT} %-50s ${NC}\n" "${options[$i]}"
        else
            printf "    %-50s \n" "${options[$i]}"
        fi
    done

    echo ""
    draw_line "─" 56
}

# Sub-menu for individual service restart
service_submenu() {
    local svc_options=()
    local svc_keys=()

    # Only show enabled services
    if [ "$MONITOR_EARNAPP" = "true" ]; then
        svc_options+=("EarnApp")
        svc_keys+=("earnapp")
    fi
    if [ "$MONITOR_HONEYGAIN" = "true" ]; then
        svc_options+=("Honeygain")
        svc_keys+=("honeygain")
    fi
    if [ "$MONITOR_GRASS" = "true" ]; then
        svc_options+=("Grass")
        svc_keys+=("grass")
    fi
    svc_options+=("← Back to Main Menu")
    svc_keys+=("back")

    local svc_selected=0

    tput civis 2>/dev/null

    while true; do
        clear
        draw_header "RESTART SERVICE" ""
        echo ""
        echo -e "  ${DIM}[↑/↓] Move  |  [Enter] Select  |  [Esc] Back${NC}"
        draw_line "─" 50
        echo ""

        for i in "${!svc_options[@]}"; do
            if [ "$i" -eq "$svc_selected" ]; then
                printf "  ${GREEN}${SYM_ARROW}${NC} ${BG_SELECT} %-44s ${NC}\n" "${svc_options[$i]}"
            else
                printf "    %-44s \n" "${svc_options[$i]}"
            fi
        done

        echo ""
        draw_line "─" 50

        read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.01 arrow
            if [[ "$arrow" == "[A" ]]; then
                ((svc_selected--))
                if [ "$svc_selected" -lt 0 ]; then svc_selected=$((${#svc_options[@]} - 1)); fi
            elif [[ "$arrow" == "[B" ]]; then
                ((svc_selected++))
                if [ "$svc_selected" -ge "${#svc_options[@]}" ]; then svc_selected=0; fi
            else
                return
            fi
        elif [[ "$key" == "" ]]; then
            local chosen_key="${svc_keys[$svc_selected]}"
            if [ "$chosen_key" = "back" ]; then
                return
            fi

            echo ""
            case "$chosen_key" in
                earnapp)   restart_earnapp ;;
                honeygain) restart_honeygain ;;
                grass)     restart_grass ;;
            esac
            echo ""
            echo -e "  ${DIM}Press any key to continue...${NC}"
            read -rsn1
        fi
    done
}

# Settings configuration sub-menu
settings_menu() {
    local set_selected=0

    tput civis 2>/dev/null

    while true; do
        local set_options=(
            "Monitor Interval: ${MONITOR_INTERVAL}s"
            "Restart Cooldown: ${RESTART_COOLDOWN}s"
            "Max Restart Attempts: ${MAX_RESTART_ATTEMPTS}"
            "Auto-Restart: $([ "$AUTO_RESTART_ENABLED" = "true" ] && echo "Enabled" || echo "Disabled")"
            "Reset Restart Counters"
            "← Back to Main Menu"
        )

        clear
        draw_header "SETTINGS" "Runtime configuration"
        echo ""
        echo -e "  ${DIM}[↑/↓] Move  |  [Enter] Edit  |  [Esc] Back${NC}"
        echo -e "  ${DIM}Note: To change services or webhook, run install.sh${NC}"
        draw_line "─" 50
        echo ""

        for i in "${!set_options[@]}"; do
            if [ "$i" -eq "$set_selected" ]; then
                printf "  ${GREEN}${SYM_ARROW}${NC} ${BG_SELECT} %-44s ${NC}\n" "${set_options[$i]}"
            else
                printf "    %-44s \n" "${set_options[$i]}"
            fi
        done

        echo ""
        draw_line "─" 50

        read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.01 arrow
            if [[ "$arrow" == "[A" ]]; then
                ((set_selected--))
                if [ "$set_selected" -lt 0 ]; then set_selected=$((${#set_options[@]} - 1)); fi
            elif [[ "$arrow" == "[B" ]]; then
                ((set_selected++))
                if [ "$set_selected" -ge "${#set_options[@]}" ]; then set_selected=0; fi
            else
                return
            fi
        elif [[ "$key" == "" ]]; then
            tput cnorm 2>/dev/null
            case $set_selected in
                0)
                    echo ""
                    echo -ne "  ${CYAN}Enter new monitor interval (seconds): ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 5 ]; then
                        MONITOR_INTERVAL=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Interval set to ${val}s${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid value (minimum 5)${NC}"
                    fi
                    sleep 1
                    ;;
                1)
                    echo ""
                    echo -ne "  ${CYAN}Enter new restart cooldown (seconds): ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 10 ]; then
                        RESTART_COOLDOWN=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Cooldown set to ${val}s${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid value (minimum 10)${NC}"
                    fi
                    sleep 1
                    ;;
                2)
                    echo ""
                    echo -ne "  ${CYAN}Enter max restart attempts: ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 1 ]; then
                        MAX_RESTART_ATTEMPTS=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Max attempts set to ${val}${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid value (minimum 1)${NC}"
                    fi
                    sleep 1
                    ;;
                3)
                    if [ "$AUTO_RESTART_ENABLED" = "true" ]; then
                        AUTO_RESTART_ENABLED="false"
                        echo -e "  ${RED}${SYM_CROSS} Auto-restart disabled${NC}"
                    else
                        AUTO_RESTART_ENABLED="true"
                        echo -e "  ${GREEN}${SYM_CHECK} Auto-restart enabled${NC}"
                    fi
                    sleep 1
                    ;;
                4)
                    RESTART_COUNTS=()
                    LAST_RESTART_TIME=()
                    NOTIFIED_DOWN=()
                    NOTIFIED_UP=()
                    echo -e "  ${GREEN}${SYM_CHECK} Restart counters and notification states reset${NC}"
                    sleep 1
                    ;;
                5) return ;;
            esac
            tput civis 2>/dev/null
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Action Handlers
# ─────────────────────────────────────────────────────────────────────────────

# Option 1: Live dashboard with auto-refresh
action_live_dashboard() {
    echo -e "\n  ${CYAN}Starting live dashboard... Press ${WHITE}[Q]${CYAN} to return to menu.${NC}\n"
    sleep 1

    while true; do
        check_all_services
        display_dashboard

        echo -e "  ${DIM}Refreshing in ${MONITOR_INTERVAL}s... Press [Q] to return to menu.${NC}"

        local elapsed=0
        while [ "$elapsed" -lt "$MONITOR_INTERVAL" ]; do
            read -rsn1 -t 1 input
            if [[ "$input" == "q" ]] || [[ "$input" == "Q" ]]; then
                return
            fi
            ((elapsed++))
        done
    done
}

# Option 2: One-time status check
action_status_check() {
    clear
    echo -e "\n  ${CYAN}${SYM_RELOAD} Checking all services...${NC}\n"
    check_all_services
    display_dashboard
    echo -e "  ${DIM}Press any key to return to menu...${NC}"
    read -rsn1
}

# Option 3: Continuous monitoring with auto-restart
action_continuous_monitor() {
    echo -e "\n  ${CYAN}${SYM_RELOAD} Starting continuous monitoring with auto-restart...${NC}"
    echo -e "  ${DIM}Press [Q] to stop monitoring and return to menu.${NC}\n"
    sleep 2

    log_message "INFO" "Continuous monitoring started (auto-restart: ${AUTO_RESTART_ENABLED})"

    while true; do
        check_all_services

        # Auto-restart logic (only if enabled)
        local restarted=false
        if [ "$AUTO_RESTART_ENABLED" = "true" ]; then
            for svc in earnapp honeygain grass; do
                local svc_status="${SERVICE_STATUS[$svc]}"
                if [ "$svc_status" != "running" ] && [ "$svc_status" != "not found" ] && [ "$svc_status" != "disabled" ]; then
                    log_message "WARN" "${svc} is ${svc_status}, attempting restart"
                    case "$svc" in
                        earnapp)   restart_earnapp ;;
                        honeygain) restart_honeygain ;;
                        grass)     restart_grass ;;
                    esac
                    restarted=true
                fi
            done
        fi

        display_dashboard

        if [ "$restarted" = true ]; then
            echo -e "  ${YELLOW}${SYM_WARN} Auto-restart was triggered this cycle${NC}"
        fi

        if [ "$AUTO_RESTART_ENABLED" = "true" ]; then
            echo -e "  ${GREEN}${SYM_CIRCLE} AUTO-RESTART ENABLED${NC}  ${DIM}|  Checking every ${MONITOR_INTERVAL}s${NC}"
        else
            echo -e "  ${YELLOW}${SYM_CIRCLE} AUTO-RESTART DISABLED${NC}  ${DIM}|  Checking every ${MONITOR_INTERVAL}s${NC}"
        fi

        if [ -n "$DISCORD_WEBHOOK_URL" ]; then
            echo -e "  ${DIM}Discord alerts: ${GREEN}Active${NC}"
        fi

        echo -e "  ${DIM}Press [Q] to stop...${NC}"

        local elapsed=0
        while [ "$elapsed" -lt "$MONITOR_INTERVAL" ]; do
            read -rsn1 -t 1 input
            if [[ "$input" == "q" ]] || [[ "$input" == "Q" ]]; then
                log_message "INFO" "Continuous monitoring stopped by user"
                return
            fi
            ((elapsed++))
        done
    done
}

# Option 4: Restart all stopped services
action_restart_all() {
    clear
    echo -e "\n  ${CYAN}Checking services and restarting any that are stopped...${NC}\n"
    check_all_services

    local any_restarted=false

    for svc in earnapp honeygain grass; do
        local svc_status="${SERVICE_STATUS[$svc]}"
        if [ "$svc_status" != "running" ] && [ "$svc_status" != "not found" ] && [ "$svc_status" != "disabled" ]; then
            case "$svc" in
                earnapp)   restart_earnapp; any_restarted=true ;;
                honeygain) restart_honeygain; any_restarted=true ;;
                grass)     restart_grass; any_restarted=true ;;
            esac
            echo ""
        fi
    done

    if [ "$any_restarted" = false ]; then
        echo -e "  ${GREEN}${SYM_CHECK} All monitored services are already running!${NC}"
    fi

    echo ""
    echo -e "  ${DIM}Press any key to return to menu...${NC}"
    read -rsn1
}

# Option 6: View logs
action_view_logs() {
    clear
    draw_header "MONITOR LOGS" ""
    echo ""

    if [ -f "$LOG_FILE" ]; then
        local line_count
        line_count=$(wc -l < "$LOG_FILE" 2>/dev/null)
        echo -e "  ${DIM}Log file: ${LOG_FILE}${NC}"
        echo -e "  ${DIM}Total entries: ${line_count}${NC}"
        echo -e "  ${DIM}Showing last 30 entries:${NC}\n"
        draw_line "─" 56

        tail -30 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
            if echo "$line" | grep -q "\[ERROR\]"; then
                echo -e "  ${RED}${line}${NC}"
            elif echo "$line" | grep -q "\[WARN\]"; then
                echo -e "  ${YELLOW}${line}${NC}"
            elif echo "$line" | grep -q "\[INFO\]"; then
                echo -e "  ${DIM}${line}${NC}"
            else
                echo -e "  ${line}"
            fi
        done

        draw_line "─" 56
    else
        echo -e "  ${DIM}No log file found yet. Run monitoring first.${NC}"
    fi

    echo ""
    echo -e "  ${DIM}Press any key to return to menu...${NC}"
    read -rsn1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # Detect environment
    detect_os

    if [ "$OS_TYPE" = "unknown" ]; then
        echo -e "${RED}${SYM_CROSS} Unsupported operating system detected.${NC}"
        echo -e "${DIM}This script supports Linux, macOS, and Windows (Git Bash/MSYS2).${NC}"
        exit 1
    fi

    # Load configuration
    if load_config; then
        log_message "INFO" "Configuration loaded from ${CONFIG_FILE}"
    else
        echo -e "${YELLOW}${SYM_WARN} No configuration file found.${NC}"
        echo -e "${DIM}Run ${WHITE}bash install.sh${DIM} first to configure services and Discord webhook.${NC}"
        echo ""
        echo -ne "${WHITE}Continue with defaults? (y/N): ${NC}"
        read -rsn1 confirm
        echo ""
        if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
            echo -e "${DIM}Exiting. Run install.sh to set up.${NC}"
            exit 0
        fi
    fi

    log_message "INFO" "Monitor started on ${OS_TYPE} | Services: EA=${MONITOR_EARNAPP} HG=${MONITOR_HONEYGAIN} GR=${MONITOR_GRASS} | Webhook: $([ -n "$DISCORD_WEBHOOK_URL" ] && echo "yes" || echo "no")"

    # Hide cursor for menu
    tput civis 2>/dev/null

    # Main menu loop
    while true; do
        print_menu
        read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.01 arrow
            if [[ "$arrow" == "[A" ]]; then
                ((selected--))
                if [ "$selected" -lt 0 ]; then selected=$((${#options[@]} - 1)); fi
            elif [[ "$arrow" == "[B" ]]; then
                ((selected++))
                if [ "$selected" -ge "${#options[@]}" ]; then selected=0; fi
            else
                tput cnorm 2>/dev/null
                clear
                echo -e "${RED}${SYM_CROSS} Monitor closed via Escape key.${NC}"
                log_message "INFO" "Monitor closed by user (Escape)"
                exit 0
            fi
        elif [[ "$key" == "" ]]; then
            tput cnorm 2>/dev/null

            case $selected in
                0) action_live_dashboard ;;
                1) action_status_check ;;
                2) action_continuous_monitor ;;
                3) action_restart_all ;;
                4) service_submenu ;;
                5) action_view_logs ;;
                6) settings_menu ;;
            esac

            tput civis 2>/dev/null
        fi
    done
}

# Run
main "$@"
