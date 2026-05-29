#!/bin/bash
# =============================================================================
# Money-Making Monitor — Install / Configure / Uninstall
# =============================================================================
# Interactive setup wizard for the Money-Making Monitor script.
# Configures which services to monitor, Discord webhook URL, and settings.
#
# Usage: bash install.sh
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

SYM_CHECK="✔"
SYM_CROSS="✘"
SYM_WARN="⚠"
SYM_ARROW="▶"
SYM_BOX_TL="╔"
SYM_BOX_TR="╗"
SYM_BOX_BL="╚"
SYM_BOX_BR="╝"
SYM_BOX_H="═"
SYM_BOX_V="║"
SYM_CHECKBOX_ON="[✔]"
SYM_CHECKBOX_OFF="[ ]"

# ─────────────────────────────────────────────────────────────────────────────
# OS Detection & Path Setup
# ─────────────────────────────────────────────────────────────────────────────

OS_TYPE=""
CONFIG_DIR=""
CONFIG_FILE=""
LOG_DIR=""

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
}

# ─────────────────────────────────────────────────────────────────────────────
# Configuration Defaults
# ─────────────────────────────────────────────────────────────────────────────

MONITOR_EARNAPP=true
MONITOR_HONEYGAIN=true
MONITOR_GRASS=true
DISCORD_WEBHOOK_URL=""
MONITOR_INTERVAL=30
RESTART_COOLDOWN=60
MAX_RESTART_ATTEMPTS=3
AUTO_RESTART_ENABLED=true

# ─────────────────────────────────────────────────────────────────────────────
# Config File I/O
# ─────────────────────────────────────────────────────────────────────────────

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source the config file safely by reading key=value pairs
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            # Trim whitespace
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
    fi
    return 1
}

save_config() {
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    cat > "$CONFIG_FILE" <<EOF
# ─────────────────────────────────────────────────────────────────
# Money-Making Monitor — Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
# ─────────────────────────────────────────────────────────────────

# Services to monitor (true/false)
MONITOR_EARNAPP=${MONITOR_EARNAPP}
MONITOR_HONEYGAIN=${MONITOR_HONEYGAIN}
MONITOR_GRASS=${MONITOR_GRASS}

# Discord webhook URL for notifications
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}

# Monitoring settings
MONITOR_INTERVAL=${MONITOR_INTERVAL}
RESTART_COOLDOWN=${RESTART_COOLDOWN}
MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS}
AUTO_RESTART_ENABLED=${AUTO_RESTART_ENABLED}
EOF

    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    tput cnorm 2>/dev/null
    echo -e "\n${RED}${SYM_CROSS} Setup cancelled.${NC}"
    exit 0
}
trap cleanup SIGINT SIGTERM

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
# Discord Webhook Test
# ─────────────────────────────────────────────────────────────────────────────

test_webhook() {
    local url="$1"

    if [ -z "$url" ]; then
        echo -e "  ${RED}${SYM_CROSS} No webhook URL provided.${NC}"
        return 1
    fi

    echo -e "  ${CYAN}Sending test message to Discord...${NC}"

    local payload
    payload=$(cat <<ENDJSON
{
  "embeds": [{
    "title": "🟢 Money-Making Monitor — Test",
    "description": "If you see this, your webhook is configured correctly!",
    "color": 5763719,
    "fields": [
      { "name": "Status", "value": "Webhook connection successful", "inline": true },
      { "name": "OS", "value": "${OS_TYPE}", "inline": true }
    ],
    "footer": { "text": "Money-Making Monitor" },
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2024-01-01T00:00:00Z")"
  }]
}
ENDJSON
)

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$url" 2>/dev/null)

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo -e "  ${GREEN}${SYM_CHECK} Test message sent successfully! (HTTP ${http_code})${NC}"
        echo -e "  ${DIM}Check your Discord channel for the message.${NC}"
        return 0
    elif [ "$http_code" = "000" ]; then
        echo -e "  ${RED}${SYM_CROSS} Failed to connect. Check your internet and URL.${NC}"
        return 1
    else
        echo -e "  ${RED}${SYM_CROSS} Webhook returned HTTP ${http_code}. Check the URL.${NC}"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Service Selection (Multi-Select Checkboxes)
# ─────────────────────────────────────────────────────────────────────────────

step_service_selection() {
    local svc_names=("EarnApp" "Honeygain" "Grass")
    local svc_vars=("MONITOR_EARNAPP" "MONITOR_HONEYGAIN" "MONITOR_GRASS")
    local svc_enabled=()

    # Initialize from current config
    svc_enabled+=("$MONITOR_EARNAPP")
    svc_enabled+=("$MONITOR_HONEYGAIN")
    svc_enabled+=("$MONITOR_GRASS")

    local svc_selected=0

    tput civis 2>/dev/null

    while true; do
        clear
        draw_header "SERVICE SELECTION" "Toggle services to monitor"
        echo ""

        local os_label
        case "$OS_TYPE" in
            linux)   os_label="Linux (Docker for Honeygain & Grass)" ;;
            macos)   os_label="macOS (Native apps)" ;;
            windows) os_label="Windows (Native apps)" ;;
            *)       os_label="Unknown" ;;
        esac
        echo -e "  ${DIM}Platform: ${os_label}${NC}"
        echo -e "  ${DIM}[↑/↓] Move  |  [Space] Toggle  |  [Enter] Confirm${NC}"
        draw_line "─" 56
        echo ""

        for i in "${!svc_names[@]}"; do
            local checkbox
            if [ "${svc_enabled[$i]}" = "true" ]; then
                checkbox="${GREEN}${SYM_CHECKBOX_ON}${NC}"
            else
                checkbox="${RED}${SYM_CHECKBOX_OFF}${NC}"
            fi

            local mode_tag=""
            if [ "$OS_TYPE" = "linux" ]; then
                case "$i" in
                    0) mode_tag="${DIM} (Native/systemd)${NC}" ;;
                    1) mode_tag="${DIM} (Docker container)${NC}" ;;
                    2) mode_tag="${DIM} (Docker container)${NC}" ;;
                esac
            else
                mode_tag="${DIM} (Native app)${NC}"
            fi

            if [ "$i" -eq "$svc_selected" ]; then
                echo -e "  ${GREEN}${SYM_ARROW}${NC} ${BG_SELECT} ${checkbox} ${svc_names[$i]}${mode_tag} ${NC}"
            else
                echo -e "    ${checkbox} ${svc_names[$i]}${mode_tag}"
            fi
        done

        echo ""

        # Show summary
        local enabled_count=0
        for e in "${svc_enabled[@]}"; do
            [ "$e" = "true" ] && ((enabled_count++))
        done
        echo -e "  ${DIM}${enabled_count}/${#svc_names[@]} services selected${NC}"
        draw_line "─" 56

        read -rsn1 key
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn2 -t 0.01 arrow
            if [[ "$arrow" == "[A" ]]; then
                ((svc_selected--))
                if [ "$svc_selected" -lt 0 ]; then svc_selected=$((${#svc_names[@]} - 1)); fi
            elif [[ "$arrow" == "[B" ]]; then
                ((svc_selected++))
                if [ "$svc_selected" -ge "${#svc_names[@]}" ]; then svc_selected=0; fi
            else
                # Esc pressed — cancel
                tput cnorm 2>/dev/null
                return 1
            fi
        elif [[ "$key" == " " ]]; then
            # Toggle checkbox
            if [ "${svc_enabled[$svc_selected]}" = "true" ]; then
                svc_enabled[$svc_selected]="false"
            else
                svc_enabled[$svc_selected]="true"
            fi
        elif [[ "$key" == "" ]]; then
            # Confirm selection
            MONITOR_EARNAPP="${svc_enabled[0]}"
            MONITOR_HONEYGAIN="${svc_enabled[1]}"
            MONITOR_GRASS="${svc_enabled[2]}"
            tput cnorm 2>/dev/null
            return 0
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Discord Webhook URL
# ─────────────────────────────────────────────────────────────────────────────

step_discord_webhook() {
    clear
    draw_header "DISCORD WEBHOOK" "Get notified when services go down"
    echo ""

    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        # Mask the URL for display (show first 40 chars + ...)
        local masked
        if [ ${#DISCORD_WEBHOOK_URL} -gt 45 ]; then
            masked="${DISCORD_WEBHOOK_URL:0:45}..."
        else
            masked="$DISCORD_WEBHOOK_URL"
        fi
        echo -e "  ${DIM}Current webhook:${NC}"
        echo -e "  ${CYAN}${masked}${NC}"
        echo ""
    fi

    echo -e "  ${WHITE}Paste your Discord webhook URL below.${NC}"
    echo -e "  ${DIM}(Press Enter to keep current, or type 'none' to remove)${NC}"
    echo ""
    echo -ne "  ${CYAN}Webhook URL: ${NC}"

    tput cnorm 2>/dev/null
    read -r input_url

    if [ -z "$input_url" ]; then
        # Keep current
        echo -e "\n  ${DIM}Keeping current webhook.${NC}"
    elif [ "$input_url" = "none" ] || [ "$input_url" = "NONE" ]; then
        DISCORD_WEBHOOK_URL=""
        echo -e "\n  ${YELLOW}${SYM_WARN} Webhook removed. No notifications will be sent.${NC}"
    else
        # Validate URL format
        if [[ "$input_url" == https://discord.com/api/webhooks/* ]] || \
           [[ "$input_url" == https://discordapp.com/api/webhooks/* ]] || \
           [[ "$input_url" == https://canary.discord.com/api/webhooks/* ]] || \
           [[ "$input_url" == https://ptb.discord.com/api/webhooks/* ]]; then
            DISCORD_WEBHOOK_URL="$input_url"
            echo -e "\n  ${GREEN}${SYM_CHECK} Webhook URL saved.${NC}"
        else
            echo -e "\n  ${YELLOW}${SYM_WARN} URL doesn't look like a Discord webhook.${NC}"
            echo -ne "  ${DIM}Save anyway? (y/N): ${NC}"
            read -rsn1 confirm
            echo ""
            if [[ "$confirm" == "y" ]] || [[ "$confirm" == "Y" ]]; then
                DISCORD_WEBHOOK_URL="$input_url"
                echo -e "  ${GREEN}${SYM_CHECK} Webhook URL saved.${NC}"
            else
                echo -e "  ${DIM}Webhook not changed.${NC}"
            fi
        fi
    fi

    # Offer to test
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        echo ""
        echo -ne "  ${WHITE}Test webhook now? (Y/n): ${NC}"
        read -rsn1 test_confirm
        echo ""
        if [[ "$test_confirm" != "n" ]] && [[ "$test_confirm" != "N" ]]; then
            echo ""
            test_webhook "$DISCORD_WEBHOOK_URL"
        fi
    fi

    echo ""
    echo -e "  ${DIM}Press any key to continue...${NC}"
    read -rsn1
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Monitor Settings
# ─────────────────────────────────────────────────────────────────────────────

step_monitor_settings() {
    local set_selected=0

    tput civis 2>/dev/null

    while true; do
        local set_options=(
            "Monitor Interval:      ${MONITOR_INTERVAL}s"
            "Restart Cooldown:      ${RESTART_COOLDOWN}s"
            "Max Restart Attempts:  ${MAX_RESTART_ATTEMPTS}"
            "Auto-Restart:          $([ "$AUTO_RESTART_ENABLED" = "true" ] && echo "${GREEN}Enabled${NC}" || echo "${RED}Disabled${NC}")"
            "✔ Done — Save and continue"
        )

        clear
        draw_header "MONITOR SETTINGS" "Fine-tune monitoring behavior"
        echo ""
        echo -e "  ${DIM}[↑/↓] Move  |  [Enter] Edit  |  [Esc] Skip${NC}"
        draw_line "─" 56
        echo ""

        for i in "${!set_options[@]}"; do
            if [ "$i" -eq "$set_selected" ]; then
                printf "  ${GREEN}${SYM_ARROW}${NC} ${BG_SELECT} %-48s ${NC}\n" "$(echo -e "${set_options[$i]}" | sed 's/\x1b\[[0-9;]*m//g')"
            else
                echo -e "    ${set_options[$i]}"
            fi
        done

        echo ""
        draw_line "─" 56

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
                    echo -ne "  ${CYAN}Monitor interval in seconds (min 5): ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 5 ]; then
                        MONITOR_INTERVAL=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Set to ${val}s${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid (must be ≥ 5)${NC}"
                    fi
                    sleep 1
                    ;;
                1)
                    echo ""
                    echo -ne "  ${CYAN}Restart cooldown in seconds (min 10): ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 10 ]; then
                        RESTART_COOLDOWN=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Set to ${val}s${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid (must be ≥ 10)${NC}"
                    fi
                    sleep 1
                    ;;
                2)
                    echo ""
                    echo -ne "  ${CYAN}Max restart attempts (min 1): ${NC}"
                    read -r val
                    if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 1 ]; then
                        MAX_RESTART_ATTEMPTS=$val
                        echo -e "  ${GREEN}${SYM_CHECK} Set to ${val}${NC}"
                    else
                        echo -e "  ${RED}${SYM_CROSS} Invalid (must be ≥ 1)${NC}"
                    fi
                    sleep 1
                    ;;
                3)
                    # Toggle auto-restart
                    if [ "$AUTO_RESTART_ENABLED" = "true" ]; then
                        AUTO_RESTART_ENABLED="false"
                    else
                        AUTO_RESTART_ENABLED="true"
                    fi
                    ;;
                4)
                    # Done
                    tput civis 2>/dev/null
                    return
                    ;;
            esac
            tput civis 2>/dev/null
        fi
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Installation Summary & Save
# ─────────────────────────────────────────────────────────────────────────────

step_summary_and_save() {
    clear
    draw_header "CONFIGURATION SUMMARY" "Review before saving"
    echo ""

    echo -e "  ${WHITE}${BOLD}Services to Monitor:${NC}"
    echo -e "    EarnApp:    $([ "$MONITOR_EARNAPP" = "true" ] && echo "${GREEN}${SYM_CHECK} Enabled${NC}" || echo "${RED}${SYM_CROSS} Disabled${NC}")"
    echo -e "    Honeygain:  $([ "$MONITOR_HONEYGAIN" = "true" ] && echo "${GREEN}${SYM_CHECK} Enabled${NC}" || echo "${RED}${SYM_CROSS} Disabled${NC}")"
    echo -e "    Grass:      $([ "$MONITOR_GRASS" = "true" ] && echo "${GREEN}${SYM_CHECK} Enabled${NC}" || echo "${RED}${SYM_CROSS} Disabled${NC}")"
    echo ""

    echo -e "  ${WHITE}${BOLD}Discord Webhook:${NC}"
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        local masked
        if [ ${#DISCORD_WEBHOOK_URL} -gt 50 ]; then
            masked="${DISCORD_WEBHOOK_URL:0:50}..."
        else
            masked="$DISCORD_WEBHOOK_URL"
        fi
        echo -e "    ${GREEN}${SYM_CHECK}${NC} ${masked}"
    else
        echo -e "    ${YELLOW}${SYM_WARN} Not configured — no notifications${NC}"
    fi
    echo ""

    echo -e "  ${WHITE}${BOLD}Settings:${NC}"
    echo -e "    Interval:      ${MONITOR_INTERVAL}s"
    echo -e "    Cooldown:      ${RESTART_COOLDOWN}s"
    echo -e "    Max Restarts:  ${MAX_RESTART_ATTEMPTS}"
    echo -e "    Auto-Restart:  $([ "$AUTO_RESTART_ENABLED" = "true" ] && echo "${GREEN}Enabled${NC}" || echo "${RED}Disabled${NC}")"
    echo ""

    echo -e "  ${WHITE}${BOLD}Paths:${NC}"
    echo -e "    Config: ${DIM}${CONFIG_FILE}${NC}"
    echo -e "    Logs:   ${DIM}${LOG_DIR}/monitor.log${NC}"
    echo ""
    draw_line "═" 56

    echo ""
    echo -ne "  ${WHITE}Save this configuration? (Y/n): ${NC}"
    tput cnorm 2>/dev/null
    read -rsn1 confirm
    echo ""

    if [[ "$confirm" == "n" ]] || [[ "$confirm" == "N" ]]; then
        echo -e "  ${YELLOW}${SYM_WARN} Configuration not saved.${NC}"
        echo -e "  ${DIM}Press any key to return to menu...${NC}"
        read -rsn1
        return 1
    fi

    # Create directories and save
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    mkdir -p "$LOG_DIR" 2>/dev/null

    if save_config; then
        echo -e "  ${GREEN}${SYM_CHECK} Configuration saved to:${NC}"
        echo -e "    ${CYAN}${CONFIG_FILE}${NC}"
        echo ""
        echo -e "  ${WHITE}To start monitoring, run:${NC}"
        echo -e "    ${GREEN}bash monitor.sh${NC}"
    else
        echo -e "  ${RED}${SYM_CROSS} Failed to save configuration.${NC}"
    fi

    echo ""
    echo -e "  ${DIM}Press any key to return to menu...${NC}"
    read -rsn1
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Full Install Wizard (runs all steps sequentially)
# ─────────────────────────────────────────────────────────────────────────────

run_install_wizard() {
    # Step 1: Service selection
    if ! step_service_selection; then
        echo -e "  ${YELLOW}${SYM_WARN} Setup cancelled.${NC}"
        sleep 1
        return
    fi

    # Step 2: Discord webhook
    step_discord_webhook

    # Step 3: Monitor settings
    step_monitor_settings

    # Step 4: Summary and save
    step_summary_and_save
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

run_uninstall() {
    clear
    draw_header "UNINSTALL" "Remove Money-Making Monitor"
    echo ""

    echo -e "  ${WHITE}This will remove:${NC}"
    echo ""

    local items_found=0
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "    ${RED}${SYM_CROSS}${NC} Config: ${DIM}${CONFIG_FILE}${NC}"
        ((items_found++))
    fi
    if [ -d "$CONFIG_DIR" ]; then
        echo -e "    ${RED}${SYM_CROSS}${NC} Config dir: ${DIM}${CONFIG_DIR}${NC}"
        ((items_found++))
    fi
    if [ -d "$LOG_DIR" ]; then
        echo -e "    ${RED}${SYM_CROSS}${NC} Logs: ${DIM}${LOG_DIR}${NC}"
        ((items_found++))
    fi

    if [ "$items_found" -eq 0 ]; then
        echo -e "    ${DIM}Nothing to remove — monitor is not installed.${NC}"
        echo ""
        echo -e "  ${DIM}Press any key to return...${NC}"
        read -rsn1
        return
    fi

    echo ""
    echo -e "  ${RED}${BOLD}${SYM_WARN} This action cannot be undone.${NC}"
    echo ""
    echo -ne "  ${WHITE}Type '${RED}UNINSTALL${WHITE}' to confirm: ${NC}"

    tput cnorm 2>/dev/null
    read -r confirmation

    if [ "$confirmation" = "UNINSTALL" ]; then
        echo ""

        # Remove config
        if [ -f "$CONFIG_FILE" ]; then
            rm -f "$CONFIG_FILE" 2>/dev/null
            echo -e "  ${RED}${SYM_CROSS}${NC} Removed config file"
        fi

        # Remove config directory (only if empty or ours)
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR" 2>/dev/null
            echo -e "  ${RED}${SYM_CROSS}${NC} Removed config directory"
        fi

        # Remove log directory
        if [ -d "$LOG_DIR" ]; then
            rm -rf "$LOG_DIR" 2>/dev/null
            echo -e "  ${RED}${SYM_CROSS}${NC} Removed log directory"
        fi

        echo ""
        echo -e "  ${GREEN}${SYM_CHECK} Uninstall complete.${NC}"
        echo -e "  ${DIM}The monitor script files (monitor.sh, install.sh) remain"
        echo -e "  in this directory. Delete them manually if desired.${NC}"
    else
        echo -e "\n  ${YELLOW}${SYM_WARN} Uninstall cancelled.${NC}"
    fi

    echo ""
    echo -e "  ${DIM}Press any key to return...${NC}"
    read -rsn1
}

# ─────────────────────────────────────────────────────────────────────────────
# View Current Config
# ─────────────────────────────────────────────────────────────────────────────

view_current_config() {
    clear
    draw_header "CURRENT CONFIGURATION" ""
    echo ""

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${DIM}File: ${CONFIG_FILE}${NC}"
        draw_line "─" 56
        echo ""

        while IFS= read -r line; do
            if [[ "$line" =~ ^#.* ]]; then
                echo -e "  ${DIM}${line}${NC}"
            elif [[ "$line" =~ ^[A-Z] ]]; then
                local key="${line%%=*}"
                local val="${line#*=}"
                if [ "$key" = "DISCORD_WEBHOOK_URL" ] && [ -n "$val" ]; then
                    if [ ${#val} -gt 40 ]; then
                        val="${val:0:40}..."
                    fi
                fi
                echo -e "  ${CYAN}${key}${NC} = ${WHITE}${val}${NC}"
            else
                echo -e "  ${line}"
            fi
        done < "$CONFIG_FILE"
    else
        echo -e "  ${YELLOW}${SYM_WARN} No configuration file found.${NC}"
        echo -e "  ${DIM}Run the installer first to create one.${NC}"
    fi

    echo ""
    draw_line "─" 56
    echo -e "  ${DIM}Press any key to return...${NC}"
    read -rsn1
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Menu
# ─────────────────────────────────────────────────────────────────────────────

main() {
    detect_os

    if [ "$OS_TYPE" = "unknown" ]; then
        echo -e "${RED}${SYM_CROSS} Unsupported operating system.${NC}"
        exit 1
    fi

    # Try loading existing config
    local config_exists=false
    if load_config; then
        config_exists=true
    fi

    local options=(
        "Install / Configure Monitor"
        "View Current Configuration"
        "Test Discord Webhook"
        "Uninstall"
    )
    local selected=0

    tput civis 2>/dev/null

    while true; do
        clear
        draw_header "MONEY-MAKING MONITOR" "Setup Wizard"
        echo ""

        local os_label
        case "$OS_TYPE" in
            linux)   os_label="Linux" ;;
            macos)   os_label="macOS" ;;
            windows) os_label="Windows" ;;
        esac

        local status_label
        if [ "$config_exists" = true ]; then
            status_label="${GREEN}${SYM_CHECK} Configured${NC}"
        else
            status_label="${YELLOW}${SYM_WARN} Not configured${NC}"
        fi

        echo -e "  ${DIM}OS: ${os_label}  |  Status: ${NC}${status_label}"
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
                echo -e "${RED}${SYM_CROSS} Setup closed.${NC}"
                exit 0
            fi
        elif [[ "$key" == "" ]]; then
            tput cnorm 2>/dev/null

            case $selected in
                0)
                    run_install_wizard
                    # Reload config state
                    if [ -f "$CONFIG_FILE" ]; then
                        config_exists=true
                    fi
                    ;;
                1) view_current_config ;;
                2)
                    clear
                    draw_header "WEBHOOK TEST" ""
                    echo ""
                    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
                        test_webhook "$DISCORD_WEBHOOK_URL"
                    else
                        echo -e "  ${YELLOW}${SYM_WARN} No webhook URL configured.${NC}"
                        echo -e "  ${DIM}Run the installer first.${NC}"
                    fi
                    echo ""
                    echo -e "  ${DIM}Press any key to return...${NC}"
                    read -rsn1
                    ;;
                3) run_uninstall ;;
            esac

            tput civis 2>/dev/null
        fi
    done
}

# Run
main "$@"
