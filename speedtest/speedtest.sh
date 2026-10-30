#!/bin/bash

# ============================================
#  SpeedTest - Versão Completa (Corrigida)
# ============================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SPIN_CHARS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Configurações
SHOW_IP=false
FULL_MODE=false
SAVE_HISTORY=true
WATCH_MODE=false
WATCH_INTERVAL=30
SERVER_ID=""
LIST_SERVERS=false
SHOW_STATS=false
CLEAN_HISTORY=false
INSTALL_DESKTOP=false
UNINSTALL_DESKTOP=false
PAUSE_ON_EXIT=false
PLUGIN_MODE=false
SEND_NOTIFICATION=true
HISTORY_DIR=""
SPEEDTEST_CMD=""

# --------------------------------------------
# Funções
# --------------------------------------------

show_help() {
    cat << EOF
SpeedTest - Teste de Velocidade da Internet

Uso: $(basename "$0") [opções]

Teste:
  -f, --full              Resultado completo
  -i, --show-ip           Mostra a linha do provedor (ISP)
  -s, --server ID         Testa em um servidor específico
  -l, --list              Lista servidores próximos
  -w, --watch [min]       Roda o teste repetidamente (padrão: 30 min)

Histórico:
  -H, --history [PASTA]   Define a pasta do histórico
      --no-history        Não salva histórico
      --stats             Mostra estatísticas do histórico
      --clean             Remove históricos antigos (mais de 6 meses)

Sistema:
      --install-desktop   Cria atalho no menu de aplicativos
      --uninstall-desktop Remove o atalho do menu de aplicativos
  -h, --help              Mostra esta ajuda

Padrão: modo simples + dados do provedor ocultos + histórico em Documentos/SpeedTest/
EOF
    exit 0
}

get_documents_dir() {
    if command -v xdg-user-dir &>/dev/null; then
        local dir
        dir=$(xdg-user-dir DOCUMENTS 2>/dev/null)
        if [[ -n "$dir" && -d "$dir" ]]; then
            echo "$dir"
            return
        fi
    fi
    if [[ -d "$HOME/Documentos" ]]; then
        echo "$HOME/Documentos"
    elif [[ -d "$HOME/Documents" ]]; then
        echo "$HOME/Documents"
    else
        echo "$HOME"
    fi
}

header() {
    [[ "$PLUGIN_MODE" == true ]] && return
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║           🚀  TESTE DE VELOCIDADE DA INTERNET        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

spinner() {
    local pid=$1
    local message=$2
    local i=0
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}${SPIN_CHARS[$i]}  ${message}${NC}   "
        i=$(( (i + 1) % ${#SPIN_CHARS[@]} ))
        sleep 0.08
    done
    printf "\r${GREEN}✓  ${message}${NC}                    \n"
    tput cnorm 2>/dev/null
}

extract_value() {
    echo "$1" | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1
}

detect_connection_type() {
    local iface
    iface=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+' | head -n1)
    
    if [[ -z "$iface" ]]; then
        echo "Desconhecido"
        return
    fi

    if [[ -d "/sys/class/net/$iface/wireless" ]] || [[ -L "/sys/class/net/$iface/phy80211" ]]; then
        echo "Wi-Fi ($iface)"
    else
        echo "Cabo ($iface)"
    fi
}

get_quality() {
    local dl=$1
    local lat=$2

    if (( $(echo "$dl >= 200" | bc -l) )) && (( $(echo "$lat <= 20" | bc -l) )); then
        echo -e "${GREEN}Excelente${NC}"
    elif (( $(echo "$dl >= 100" | bc -l) )) && (( $(echo "$lat <= 40" | bc -l) )); then
        echo -e "${GREEN}Boa${NC}"
    elif (( $(echo "$dl >= 40" | bc -l) )) && (( $(echo "$lat <= 80" | bc -l) )); then
        echo -e "${YELLOW}Regular${NC}"
    else
        echo -e "${RED}Ruim${NC}"
    fi
}

draw_bar() {
    local value=$1
    local max=$2
    local width=30
    local filled
    filled=$(echo "scale=0; $value * $width / $max" | bc 2>/dev/null || echo 0)
    [[ $filled -gt $width ]] && filled=$width
    # Use caracteres ASCII para funcionar em terminais sem fonte/locale Unicode.
    local bar empty
    printf -v bar '%*s' "$filled" ''
    printf -v empty '%*s' "$((width - filled))" ''
    bar=${bar// /#}
    empty=${empty// /-}
    printf '%s%s\n' "$bar" "$empty"
}

get_history_files() {
    local month_file="${HISTORY_DIR}/$(date +%Y-%m).log"
    local csv_file="${HISTORY_DIR}/history.csv"
    echo "$month_file|$csv_file"
}

save_to_history() {
    local dl=$1
    local ul=$2
    local lat=$3
    local date_str
    date_str=$(date '+%Y-%m-%d %H:%M:%S')
    local files
    files=$(get_history_files)
    local month_file=${files%%|*}
    local csv_file=${files##*|}

    mkdir -p "$HISTORY_DIR"

    if [[ ! -f "$month_file" ]]; then
        echo "DATA|DOWNLOAD|UPLOAD|LATENCIA" > "$month_file"
    fi
    echo "${date_str}|${dl}|${ul}|${lat}" >> "$month_file"

    if [[ ! -f "$csv_file" ]]; then
        echo "data,download,upload,latencia" > "$csv_file"
    fi
    echo "${date_str},${dl},${ul},${lat}" >> "$csv_file"
}

show_stats() {
    local files
    files=$(get_history_files)
    local csv_file=${files##*|}

    if [[ ! -f "$csv_file" ]]; then
        echo -e "${YELLOW}Nenhum histórico encontrado.${NC}"
        exit 0
    fi

    echo -e "${BOLD}📊 Estatísticas do Histórico${NC}\n"

    local total
    total=$(tail -n +2 "$csv_file" | wc -l)
    echo -e "Total de testes: ${BOLD}$total${NC}"

    if [[ $total -eq 0 ]]; then
        exit 0
    fi

    echo -e "\n${BOLD}Últimos testes:${NC}"
    tail -n 10 "$csv_file" | column -t -s,

    local avg_dl avg_ul avg_lat
    avg_dl=$(tail -n +2 "$csv_file" | cut -d',' -f2 | awk '{s+=$1;n++} END {if(n>0) printf "%.1f", s/n; else print "0"}')
    avg_ul=$(tail -n +2 "$csv_file" | cut -d',' -f3 | awk '{s+=$1;n++} END {if(n>0) printf "%.1f", s/n; else print "0"}')
    avg_lat=$(tail -n +2 "$csv_file" | cut -d',' -f4 | awk '{s+=$1;n++} END {if(n>0) printf "%.1f", s/n; else print "0"}')

    echo -e "\n${BOLD}Médias gerais:${NC}"
    echo -e "  Download: ${GREEN}${avg_dl} Mbps${NC}"
    echo -e "  Upload:   ${BLUE}${avg_ul} Mbps${NC}"
    echo -e "  Latência: ${YELLOW}${avg_lat} ms${NC}"

    if [[ $total -ge 5 ]]; then
        local last5_dl
        last5_dl=$(tail -n +2 "$csv_file" | tail -n 5 | cut -d',' -f2 | awk '{s+=$1;n++} END {if(n) printf "%.1f", s/n; else print "0"}')
        echo -e "\nMédia dos últimos 5 testes (Download): ${CYAN}${last5_dl} Mbps${NC}"
    fi
    if [[ $total -ge 10 ]]; then
        local last10_dl
        last10_dl=$(tail -n +2 "$csv_file" | tail -n 10 | cut -d',' -f2 | awk '{s+=$1;n++} END {if(n) printf "%.1f", s/n; else print "0"}')
        echo -e "Média dos últimos 10 testes (Download): ${CYAN}${last10_dl} Mbps${NC}"
    fi
}

clean_history() {
    if [[ ! -d "$HISTORY_DIR" ]]; then
        echo -e "${YELLOW}Nenhuma pasta de histórico encontrada.${NC}"
        exit 0
    fi

    echo -e "${YELLOW}Removendo históricos com mais de 6 meses...${NC}"
    find "$HISTORY_DIR" -name "*.log" -mtime +180 -delete 2>/dev/null
    echo -e "${GREEN}✓ Limpeza concluída${NC}"
}

compare_with_last() {
    local current_dl=$1
    local current_ul=$2
    local current_lat=$3
    local files
    files=$(get_history_files)
    local month_file=${files%%|*}

    [[ ! -f "$month_file" ]] && return

    local last_line
    last_line=$(tail -n +2 "$month_file" | tail -n1)
    local last_dl last_ul last_lat
    last_dl=$(echo "$last_line" | cut -d'|' -f2)
    last_ul=$(echo "$last_line" | cut -d'|' -f3)
    last_lat=$(echo "$last_line" | cut -d'|' -f4)

    [[ ! "$last_dl" =~ ^[0-9]+([.][0-9]+)?$ || ! "$last_ul" =~ ^[0-9]+([.][0-9]+)?$ ]] && return

    echo -e "\n${BOLD}📊 Comparação com o último teste:${NC}"

    local dl_diff
    dl_diff=$(echo "$current_dl - $last_dl" | bc 2>/dev/null || echo 0)
    if (( $(echo "$dl_diff > 1" | bc -l) )); then
        echo -e "   Download: ${GREEN}+${dl_diff} Mbps${NC}"
    elif (( $(echo "$dl_diff < -1" | bc -l) )); then
        echo -e "   Download: ${RED}${dl_diff} Mbps${NC}"
    else
        echo -e "   Download: ${DIM}sem alteração significativa${NC}"
    fi

    local ul_diff
    ul_diff=$(echo "$current_ul - $last_ul" | bc 2>/dev/null || echo 0)
    if (( $(echo "$ul_diff > 1" | bc -l) )); then
        echo -e "   Upload:   ${GREEN}+${ul_diff} Mbps${NC}"
    elif (( $(echo "$ul_diff < -1" | bc -l) )); then
        echo -e "   Upload:   ${RED}${ul_diff} Mbps${NC}"
    else
        echo -e "   Upload:   ${DIM}sem alteração significativa${NC}"
    fi
}

send_notification() {
    local dl=$1
    local ul=$2
    local lat=$3
    local quality=$4

    command -v notify-send >/dev/null || return

    notify-send -a "SpeedTest" \
        -i network-transmit-receive \
        -u normal \
        "🚀 Teste de Velocidade" \
        "⬇️  ${dl} Mbps   ⬆️  ${ul} Mbps\n⏱️  ${lat} ms   •  Qualidade: ${quality}" 2>/dev/null
}

play_sound() {
    if command -v canberra-gtk-play &>/dev/null; then
        canberra-gtk-play --id=complete 2>/dev/null &
    elif command -v paplay &>/dev/null; then
        paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
    fi
}

install_desktop_entry() {
    local desktop_file="$HOME/.local/share/applications/speedtest.desktop"
    local script_path desktop_exec_path
    script_path=$(readlink -f -- "${BASH_SOURCE[0]}") || {
        echo -e "${RED}✗ Não foi possível determinar o caminho do script.${NC}" >&2
        return 1
    }
    if [[ ! -f "$script_path" ]]; then
        echo -e "${RED}✗ Script não encontrado: $script_path${NC}" >&2
        return 1
    fi

    # Escapa o caminho conforme o formato Exec do arquivo .desktop.
    desktop_exec_path=${script_path//\\/\\\\}
    desktop_exec_path=${desktop_exec_path//\"/\\\"}
    desktop_exec_path=${desktop_exec_path//%/%%}

    mkdir -p "$HOME/.local/share/applications"

    if [[ -f "$desktop_file" ]]; then
        echo -e "${YELLOW}Atalho já existe. Atualizando...${NC}"
    fi

    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=SpeedTest
Comment=Teste de velocidade da internet
Exec="/bin/bash" "$desktop_exec_path" --pause-on-exit
Icon=network-transmit-receive
Terminal=true
Type=Application
Categories=Network;Utility;
StartupNotify=false
EOF

    echo -e "${GREEN}✓ Atalho criado/atualizado com sucesso!${NC}"
    echo -e "  Arquivo: ${DIM}$desktop_file${NC}"
}

uninstall_desktop_entry() {
    local desktop_file="$HOME/.local/share/applications/speedtest.desktop"

    if [[ ! -f "$desktop_file" ]]; then
        echo -e "${YELLOW}Atalho do SpeedTest não encontrado.${NC}"
        return 0
    fi

    if rm -- "$desktop_file"; then
        echo -e "${GREEN}✓ Atalho removido com sucesso.${NC}"
    else
        echo -e "${RED}✗ Não foi possível remover o atalho.${NC}" >&2
        return 1
    fi
}

check_speedtest() {
    if command -v speedtest-go &>/dev/null; then
        SPEEDTEST_CMD="speedtest-go"
    elif command -v speedtest &>/dev/null; then
        SPEEDTEST_CMD="speedtest"
    else
        echo -e "${YELLOW}▶ Instalando speedtest-go...${NC}"
        if command -v go &>/dev/null; then
            if ! go install github.com/showwin/speedtest-go@latest; then
                echo -e "${RED}✗ Falha ao instalar speedtest-go com Go.${NC}" >&2
                exit 1
            fi
            export PATH="$PATH:$(go env GOPATH)/bin"
            SPEEDTEST_CMD="speedtest-go"
        else
            ARCH=$(uname -m)
            case $ARCH in
                x86_64) ARCH="x86_64" ;;
                aarch64|arm64) ARCH="arm64" ;;
                *) echo -e "${RED}Arquitetura não suportada.${NC}"; exit 1 ;;
            esac
            TMP=$(mktemp -d)
            cd "$TMP" || exit 1
            if ! curl -fsSL "https://github.com/showwin/speedtest-go/releases/latest/download/speedtest-go_Linux_${ARCH}.tar.gz" -o st.tar.gz ||
               ! tar -xzf st.tar.gz || [[ ! -f speedtest-go ]]; then
                echo -e "${RED}✗ Falha ao baixar ou extrair speedtest-go.${NC}" >&2
                cd - >/dev/null
                rm -rf "$TMP"
                exit 1
            fi
            mkdir -p "$HOME/.local/bin" || exit 1
            if ! mv speedtest-go "$HOME/.local/bin/"; then
                echo -e "${RED}✗ Falha ao instalar em ~/.local/bin.${NC}" >&2
                cd - >/dev/null
                rm -rf "$TMP"
                exit 1
            fi
            export PATH="$PATH:$HOME/.local/bin"
            SPEEDTEST_CMD="speedtest-go"
            cd - >/dev/null
            rm -rf "$TMP"
        fi
        echo -e "${GREEN}✓ Instalado!${NC}\n"
    fi
}

run_speedtest() {
    local conn_type
    conn_type=$(detect_connection_type)

    echo -e "${YELLOW}▶ Iniciando teste...${NC}"
    echo -e "${DIM}  Tipo de conexão: ${conn_type}${NC}\n"

    local args=()
    # Removido --mask-isp (estava causando o erro)
    [[ -n "$SERVER_ID" ]] && args+=(--server "$SERVER_ID")

    "$SPEEDTEST_CMD" "${args[@]}" > /tmp/speedtest_result.txt 2>&1 &
    local pid=$!

    if [[ "$PLUGIN_MODE" != true ]]; then
        spinner "$pid" "Procurando servidor..."
        if kill -0 "$pid" 2>/dev/null; then
            spinner "$pid" "Testando download e latência..."
        fi
        if kill -0 "$pid" 2>/dev/null; then
            spinner "$pid" "Testando upload..."
        fi
    else
        local plugin_phase=download
        printf 'SPEEDTEST_PHASE|download\n'
        while kill -0 "$pid" 2>/dev/null; do
            if [[ "$plugin_phase" == download ]] && grep -qE 'Download:|✓ Download' /tmp/speedtest_result.txt 2>/dev/null; then
                plugin_phase=upload
                printf 'SPEEDTEST_PHASE|upload\n'
            fi
            sleep 0.15
        done
    fi

    wait "$pid"
    local exit_code=$?

    echo ""
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗ Erro durante o teste${NC}"
        cat /tmp/speedtest_result.txt
        rm -f /tmp/speedtest_result.txt
        return 1
    fi

    local OUTPUT
    OUTPUT=$(cat /tmp/speedtest_result.txt)
    rm -f /tmp/speedtest_result.txt

    # Oculta os dados do provedor junto com a linha ISP.
    if [[ "$SHOW_IP" == false ]]; then
        OUTPUT=$(echo "$OUTPUT" | grep -v -E 'ISP:|✓ ISP')
    fi

    local dl_line ul_line lat_line
    dl_line=$(echo "$OUTPUT" | grep -E 'Download:|✓ Download' | head -n1)
    ul_line=$(echo "$OUTPUT" | grep -E 'Upload:|✓ Upload' | head -n1)
    lat_line=$(echo "$OUTPUT" | grep -E 'Latency:|✓ Latency' | head -n1)

    local DOWNLOAD UPLOAD LATENCY
    DOWNLOAD=$(extract_value "$dl_line")
    UPLOAD=$(extract_value "$ul_line")
    LATENCY=$(extract_value "$lat_line")

    if [[ ! "$DOWNLOAD" =~ ^[0-9]+([.][0-9]+)?$ ||
          ! "$UPLOAD" =~ ^[0-9]+([.][0-9]+)?$ ||
          ! "$LATENCY" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo -e "${RED}✗ Não foi possível interpretar download, upload e latência na saída do speedtest.${NC}"
        echo -e "${DIM}Saída recebida:${NC}"
        printf '%s\n' "$OUTPUT"
        return 1
    fi

    local QUALITY
    QUALITY=$(get_quality "$DOWNLOAD" "$LATENCY")
    if [[ "$PLUGIN_MODE" == true ]]; then
        local plugin_quality
        plugin_quality=$(echo -e "$QUALITY" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
        printf 'SPEEDTEST_RESULT|%s|%s|%s|%s\n' "$DOWNLOAD" "$UPLOAD" "$LATENCY" "$plugin_quality"
    fi

    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${PURPLE}                 RESULTADO DO TESTE${NC}"
    echo -e "${DIM}           $(date '+%d/%m/%Y às %H:%M:%S')  •  $conn_type${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}\n"

    if [[ "$FULL_MODE" == true ]]; then
        echo "$OUTPUT" | while read -r line; do
            [[ $line == *"Test Server:"* || $line == *"✓ Test Server"* ]] && echo -e "${CYAN}🖥️   $line${NC}"
            [[ $line == *"Latency:"* || $line == *"✓ Latency"* ]] && echo -e "${YELLOW}⏱️   $line${NC}"
            [[ $line == *"Download:"* || $line == *"✓ Download"* ]] && echo -e "${GREEN}⬇️   $line${NC}"
            [[ $line == *"Upload:"* || $line == *"✓ Upload"* ]] && echo -e "${BLUE}⬆️   $line${NC}"
            [[ $line == *"Packet Loss:"* || $line == *"✓ Packet Loss"* ]] && echo -e "${PURPLE}📉  $line${NC}"
        done
    else
        echo -e "${GREEN}⬇️   Download:  ${BOLD}${DOWNLOAD} Mbps${NC}"
        echo -e "${BLUE}⬆️   Upload:    ${BOLD}${UPLOAD} Mbps${NC}"
        echo -e "${YELLOW}⏱️   Latência:  ${BOLD}${LATENCY} ms${NC}"
    fi

    echo -e "\n${BOLD}Qualidade da conexão:${NC} $QUALITY"

    if [[ "$SAVE_HISTORY" == true && -n "$DOWNLOAD" ]]; then
        compare_with_last "$DOWNLOAD" "$UPLOAD" "$LATENCY"
        save_to_history "$DOWNLOAD" "$UPLOAD" "$LATENCY"
    fi

    echo -e "\n${GREEN}══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Teste finalizado!${NC}"
    [[ "$SHOW_IP" == false ]] && echo -e "${DIM}Dados do provedor ocultos (use --show-ip)${NC}"
    [[ "$FULL_MODE" == false ]] && echo -e "${DIM}Modo simples (use --full)${NC}"
    [[ "$SAVE_HISTORY" == true ]] && echo -e "${DIM}Histórico: ${HISTORY_DIR}${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════${NC}\n"

    local clean_quality
    clean_quality=$(echo -e "$QUALITY" | sed 's/\x1B\[[0-9;]*[JKmsu]//g')
    if [[ "$SEND_NOTIFICATION" == true ]]; then
        send_notification "$DOWNLOAD" "$UPLOAD" "$LATENCY" "$clean_quality"
    fi
    play_sound
}

# --------------------------------------------
# Parse de argumentos
# --------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--full)
            FULL_MODE=true
            shift
            ;;
        -i|--show-ip)
            SHOW_IP=true
            shift
            ;;
        -s|--server)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                echo -e "${RED}Informe o ID do servidor após $1.${NC}" >&2
                exit 2
            fi
            SERVER_ID="$2"
            shift 2
            ;;
        -l|--list)
            LIST_SERVERS=true
            shift
            ;;
        -w|--watch)
            WATCH_MODE=true
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                WATCH_INTERVAL="$2"
                shift 2
            else
                shift
            fi
            ;;
        -H|--history)
            if [[ -n "$2" && "$2" != -* ]]; then
                HISTORY_DIR="$2"
                shift 2
            else
                shift
            fi
            SAVE_HISTORY=true
            ;;
        --no-history)
            SAVE_HISTORY=false
            shift
            ;;
        --stats)
            SHOW_STATS=true
            shift
            ;;
        --clean)
            CLEAN_HISTORY=true
            shift
            ;;
        --install-desktop)
            INSTALL_DESKTOP=true
            shift
            ;;
        --uninstall-desktop)
            UNINSTALL_DESKTOP=true
            shift
            ;;
        --pause-on-exit)
            PAUSE_ON_EXIT=true
            shift
            ;;
        --plugin-mode)
            PLUGIN_MODE=true
            # O plugin controla notificações pela própria configuração.
            SEND_NOTIFICATION=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Opção desconhecida: $1${NC}"
            exit 1
            ;;
    esac
done

if [[ "$PAUSE_ON_EXIT" == true ]]; then
    trap 'if [[ -t 0 ]]; then echo; read -r -p "Pressione Enter para fechar esta janela..." _; fi' EXIT
fi

# Define pasta padrão para operações de histórico e testes que salvam resultados
if [[ -z "$HISTORY_DIR" ]]; then
    HISTORY_DIR="$(get_documents_dir)/SpeedTest"
fi

# --------------------------------------------
# Execução principal
# --------------------------------------------

if [[ "$INSTALL_DESKTOP" == true ]]; then
    install_desktop_entry
    exit 0
fi

if [[ "$UNINSTALL_DESKTOP" == true ]]; then
    uninstall_desktop_entry
    exit $?
fi

if [[ "$SHOW_STATS" == true ]]; then
    header
    show_stats
    exit 0
fi

if [[ "$CLEAN_HISTORY" == true ]]; then
    header
    clean_history
    exit 0
fi

header
check_speedtest

if [[ "$LIST_SERVERS" == true ]]; then
    echo -e "${YELLOW}▶ Listando servidores próximos...${NC}\n"
    "$SPEEDTEST_CMD" --list
    exit 0
fi

if [[ "$WATCH_MODE" == true ]]; then
    echo -e "${CYAN}Modo watch ativado (intervalo: ${WATCH_INTERVAL} minutos)${NC}"
    echo -e "${DIM}Pressione Ctrl+C para parar${NC}\n"
    while true; do
        run_speedtest
        echo -e "${DIM}Próximo teste em ${WATCH_INTERVAL} minutos...${NC}\n"
        sleep $((WATCH_INTERVAL * 60))
    done
else
    run_speedtest
fi
