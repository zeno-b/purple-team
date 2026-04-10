#!/bin/bash

################################################################################
# Purple Team Agent - WSL to Windows Host
# Version: 4.0
# Description: Advanced adversary simulation for purple team exercises
#              targeting financial and government sector TTPs
# Usage: ./agent.sh [options]
################################################################################

set -o pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_VERSION="4.0"
readonly WINDOWS_SYSTEM="/mnt/c"
readonly TIMEOUT_SECONDS=30

# Log paths are set once at startup; declare here, assign in init_logs
LOG_FILE=""
JSON_LOG=""

# Terminal color codes
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_MAGENTA='\033[0;35m'
readonly C_CYAN='\033[0;36m'
readonly C_WHITE='\033[1;37m'
readonly C_GRAY='\033[0;90m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RESET='\033[0m'

# Box-drawing characters for structured output
readonly B_TL="┌" B_TR="┐" B_BL="└" B_BR="┘"
readonly B_H="─" B_V="│" B_VR="├" B_VL="┤"

# Track execution statistics
TOTAL_ACTIONS=0
SUCCESSFUL_ACTIONS=0
FAILED_ACTIONS=0
SKIPPED_ACTIONS=0
START_TIME=$(date +%s)
CURRENT_PHASE=""
CURRENT_PHASE_START=0
PHASE_FINDINGS=()

# Environment detection results
WSL_VERSION=""
POWERSHELL_CMD=""
HOSTNAME_DETECTED=""
USERNAME_DETECTED=""

# ============================================================================
# LOGGING SYSTEM
# ============================================================================

init_logs() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="/tmp/purpleteam_${ts}.log"
    JSON_LOG="/tmp/purpleteam_${ts}.json"

    {
        printf '%s\n' "╔═══════════════════════════════════════════════════════════════════════╗"
        printf '%s\n' "║               PURPLE TEAM AGENT v${SCRIPT_VERSION} — EXECUTION LOG                  ║"
        printf '%s\n' "╚═══════════════════════════════════════════════════════════════════════╝"
        printf '\n'
        printf '  %-18s %s\n' "Start Time:" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf '  %-18s %s\n' "Operator:" "$(whoami)"
        printf '  %-18s %s\n' "Hostname:" "$(hostname)"
        printf '  %-18s %s\n' "Log File:" "$LOG_FILE"
        printf '  %-18s %s\n' "JSON Log:" "$JSON_LOG"
        printf '\n'
    } > "$LOG_FILE"

    printf '[\n' > "$JSON_LOG"
}

log_text() {
    local indent="$1"
    shift
    printf '%*s%s\n' "$indent" "" "$*" >> "$LOG_FILE"
}

log_json_event() {
    local status="$1" technique="$2" phase="$3" description="$4" detail="$5"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local elapsed=$(($(date +%s) - START_TIME))

    cat >> "$JSON_LOG" <<JSONEOF
  {
    "timestamp": "$ts",
    "elapsed_seconds": $elapsed,
    "phase": "$phase",
    "status": "$status",
    "technique": "$technique",
    "description": $(printf '%s' "$description" | sed 's/\\/\\\\/g;s/"/\\"/g' | sed 's/.*/  "&"/'),
    "detail": $(printf '%s' "${detail:-}" | sed 's/\\/\\\\/g;s/"/\\"/g' | sed 's/.*/  "&"/')
  },
JSONEOF
}

# ============================================================================
# TERMINAL OUTPUT FUNCTIONS
# ============================================================================

print_success() {
    local message="$1"
    local technique="${2:-}"
    printf '%b[✓]%b %b%s%b\n' "$C_GREEN" "$C_RESET" "$C_WHITE" "$message" "$C_RESET"
    log_text 4 "[SUCCESS] $message"
    log_json_event "SUCCESS" "$technique" "$CURRENT_PHASE" "$message"
    ((SUCCESSFUL_ACTIONS++))
}

print_error() {
    local message="$1"
    local technique="${2:-}"
    printf '%b[✗]%b %b%s%b\n' "$C_RED" "$C_RESET" "$C_RED" "$message" "$C_RESET"
    log_text 4 "[FAILED]  $message"
    log_json_event "FAILED" "$technique" "$CURRENT_PHASE" "$message"
    ((FAILED_ACTIONS++))
}

print_warning() {
    local message="$1"
    local technique="${2:-}"
    printf '%b[!]%b %b%s%b\n' "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$message" "$C_RESET"
    log_text 4 "[WARNING] $message"
}

print_info() {
    local message="$1"
    printf '%b[i]%b %b%s%b\n' "$C_BLUE" "$C_RESET" "$C_GRAY" "$message" "$C_RESET"
    log_text 4 "[INFO]    $message"
}

print_action() {
    local message="$1"
    printf '%b[>]%b %b%s%b\n' "$C_MAGENTA" "$C_RESET" "$C_MAGENTA" "$message" "$C_RESET"
    log_text 4 "[ACTION]  $message"
}

print_detail() {
    local message="$1"
    printf '    %b%s%b\n' "$C_DIM" "$message" "$C_RESET"
    log_text 8 "$message"
}

print_finding() {
    local severity="$1" message="$2"
    local color="$C_WHITE"
    case "$severity" in
        HIGH)     color="$C_RED" ;;
        MEDIUM)   color="$C_YELLOW" ;;
        LOW)      color="$C_CYAN" ;;
        INFO)     color="$C_GRAY" ;;
    esac
    printf '    %b[%s]%b %s\n' "$color" "$severity" "$C_RESET" "$message"
    log_text 8 "[FINDING:$severity] $message"
    PHASE_FINDINGS+=("[$severity] $message")
}

# Phase section header with timing and technique mapping
begin_phase() {
    local number="$1" title="$2" techniques="$3" description="$4"
    CURRENT_PHASE="Phase $number"
    CURRENT_PHASE_START=$(date +%s)
    PHASE_FINDINGS=()

    printf '\n'
    printf '%b╔══════════════════════════════════════════════════════════════════════╗%b\n' "$C_CYAN" "$C_RESET"
    printf '%b║%b  %bPHASE %s: %s%b\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$number" "$title" "$C_RESET"
    printf '%b║%b  %bMITRE ATT&CK: %s%b\n' "$C_CYAN" "$C_RESET" "$C_GRAY" "$techniques" "$C_RESET"
    printf '%b║%b  %b%s%b\n' "$C_CYAN" "$C_RESET" "$C_DIM" "$description" "$C_RESET"
    printf '%b╚══════════════════════════════════════════════════════════════════════╝%b\n' "$C_CYAN" "$C_RESET"
    printf '\n'

    {
        printf '\n'
        printf '  ══════════════════════════════════════════════════════════════════\n'
        printf '  PHASE %s: %s\n' "$number" "$title"
        printf '  Techniques: %s\n' "$techniques"
        printf '  Started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf '  ──────────────────────────────────────────────────────────────────\n'
        printf '\n'
    } >> "$LOG_FILE"
}

end_phase() {
    local phase_duration=$(( $(date +%s) - CURRENT_PHASE_START ))

    if [ ${#PHASE_FINDINGS[@]} -gt 0 ]; then
        printf '\n'
        printf '  %b── Findings (%d) ──%b\n' "$C_WHITE" "${#PHASE_FINDINGS[@]}" "$C_RESET"
        for f in "${PHASE_FINDINGS[@]}"; do
            printf '  %s\n' "$f"
        done
    fi

    printf '\n  %b%s completed in %ds%b\n' "$C_DIM" "$CURRENT_PHASE" "$phase_duration" "$C_RESET"

    {
        printf '\n'
        printf '  ── Phase Findings (%d) ──\n' "${#PHASE_FINDINGS[@]}"
        for f in "${PHASE_FINDINGS[@]}"; do
            printf '    %s\n' "$f"
        done
        printf '  Duration: %ds\n' "$phase_duration"
        printf '  ──────────────────────────────────────────────────────────────────\n'
    } >> "$LOG_FILE"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

safe_find() {
    local path="$1" pattern="$2" max_results="${3:-20}"
    [ ! -d "$path" ] && return 1
    timeout 10 find "$path" -type f -name "$pattern" 2>/dev/null | head -n "$max_results"
}

safe_grep() {
    local pattern="$1" path="$2" max_results="${3:-10}"
    [ ! -d "$path" ] && return 1
    timeout 10 grep -r -i -l "$pattern" "$path" 2>/dev/null | head -n "$max_results"
}

# ============================================================================
# POWERSHELL EXECUTION WRAPPER
# ============================================================================

execute_ps() {
    local command="$1"
    local technique="$2"
    local description="$3"

    ((TOTAL_ACTIONS++))
    print_action "$description"

    local temp_out temp_err exit_code
    temp_out=$(mktemp)
    temp_err=$(mktemp)
    exit_code=0

    if timeout $TIMEOUT_SECONDS $POWERSHELL_CMD -NoProfile -NonInteractive -Command "$command" > "$temp_out" 2> "$temp_err"; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ] && [ -s "$temp_out" ]; then
        print_success "$description" "$technique"

        {
            printf '    %s %s\n' "$B_TL$B_H" "$description"
            printf '    %s  Technique: %s | Status: SUCCESS\n' "$B_V" "$technique"
            printf '    %s\n' "$B_V"
            sed 's/^/    │  /' "$temp_out"
            printf '    %s\n' "$B_BL$B_H"
            printf '\n'
        } >> "$LOG_FILE"

        local line_count
        line_count=$(wc -l < "$temp_out")
        if [ "$line_count" -le 8 ]; then
            while IFS= read -r line; do
                print_detail "$line"
            done < "$temp_out"
        else
            head -6 "$temp_out" | while IFS= read -r line; do
                print_detail "$line"
            done
            print_detail "... ($line_count lines total, see log for full output)"
        fi

        rm -f "$temp_out" "$temp_err"
        return 0
    else
        local error_msg="Failed"
        [ -s "$temp_err" ] && error_msg=$(head -1 "$temp_err")
        [ $exit_code -eq 124 ] && error_msg="Timeout (${TIMEOUT_SECONDS}s)"

        print_error "$description — $error_msg" "$technique"

        {
            printf '    %s %s\n' "$B_TL$B_H" "$description"
            printf '    %s  Technique: %s | Status: FAILED\n' "$B_V" "$technique"
            printf '    %s  Error: %s\n' "$B_V" "$error_msg"
            printf '    %s\n' "$B_BL$B_H"
            printf '\n'
        } >> "$LOG_FILE"

        rm -f "$temp_out" "$temp_err"
        return 1
    fi
}

# ============================================================================
# ENVIRONMENT DETECTION
# ============================================================================

detect_environment() {
    begin_phase "0" "Environment Detection" "T1082" \
        "Verify WSL runtime, Windows filesystem access, and PowerShell availability"

    if grep -qi microsoft /proc/version 2>/dev/null; then
        if grep -qi "WSL2" /proc/version 2>/dev/null; then
            WSL_VERSION="WSL2"
        else
            WSL_VERSION="WSL1"
        fi
        print_success "Running on $WSL_VERSION" "T1082"
    else
        print_error "Not running in WSL environment" "T1082"
        exit 1
    fi

    if [ ! -d "$WINDOWS_SYSTEM" ]; then
        print_warning "Standard mount /mnt/c not found, searching..."
        for mount in /mnt/*; do
            if [ -d "$mount/Windows" ]; then
                WINDOWS_SYSTEM="$mount"
                print_info "Found Windows at: $WINDOWS_SYSTEM"
                break
            fi
        done
        if [ ! -d "$WINDOWS_SYSTEM/Windows" ]; then
            print_error "Cannot locate Windows filesystem" "T1082"
            exit 1
        fi
    fi
    print_success "Windows filesystem accessible: $WINDOWS_SYSTEM" "T1082"

    if command -v powershell.exe &> /dev/null; then
        POWERSHELL_CMD="powershell.exe"
        print_success "PowerShell (Desktop) detected" "T1082"
    elif command -v pwsh.exe &> /dev/null; then
        POWERSHELL_CMD="pwsh.exe"
        print_success "PowerShell Core detected" "T1082"
    else
        print_error "No PowerShell executable found" "T1082"
        exit 1
    fi

    if ! timeout $TIMEOUT_SECONDS $POWERSHELL_CMD -NoProfile -Command "Write-Output 'test'" &> /dev/null; then
        print_error "PowerShell execution test failed" "T1082"
        exit 1
    fi
    print_success "PowerShell execution verified" "T1082"

    HOSTNAME_DETECTED=$($POWERSHELL_CMD -NoProfile -Command "hostname" 2>/dev/null | tr -d '\r')
    USERNAME_DETECTED=$($POWERSHELL_CMD -NoProfile -Command '[System.Environment]::UserName' 2>/dev/null | tr -d '\r')
    print_info "Target: ${USERNAME_DETECTED:-unknown}@${HOSTNAME_DETECTED:-unknown}"

    end_phase
}

# ============================================================================
# PHASE 1: SYSTEM & ENVIRONMENT PROFILING
# APT fingerprinting: OS details, virtualisation, security stack, locale
# ============================================================================

phase_system_discovery() {
    begin_phase 1 "System & Environment Profiling" \
        "T1082, T1497.001, T1614, T1614.001" \
        "Fingerprint the target: OS, hardware, virtualisation, language, security stack"

    execute_ps \
        "[System.Environment]::OSVersion | Format-List; Get-ComputerInfo | Select-Object CsName,WindowsVersion,WindowsBuildLabEx,OsArchitecture,OsTotalVisibleMemorySize,OsLanguage,TimeZone | Format-List" \
        "T1082" \
        "Collecting OS version, architecture, language, and timezone"

    execute_ps \
        "Get-HotFix | Sort-Object -Property InstalledOn -Descending -ErrorAction SilentlyContinue | Select-Object -First 15 HotFixID,Description,InstalledOn | Format-Table -AutoSize" \
        "T1082" \
        "Enumerating recent security patches"

    execute_ps \
        "(Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime | Select-Object Days,Hours,Minutes | Format-List" \
        "T1082" \
        "Checking system uptime"

    execute_ps \
        "Get-WmiObject Win32_ComputerSystem | Select-Object Model,Manufacturer,HypervisorPresent,PartOfDomain,Domain | Format-List" \
        "T1497.001" \
        "Detecting virtualisation and domain membership"

    execute_ps \
        "Get-WmiObject Win32_BIOS | Select-Object SMBIOSBIOSVersion,Manufacturer,SerialNumber | Format-List" \
        "T1497.001" \
        "BIOS fingerprint (sandbox/VM indicator)"

    execute_ps \
        "Get-MpComputerStatus -ErrorAction SilentlyContinue | Select-Object AntivirusEnabled,RealTimeProtectionEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,NISEnabled,AntivirusSignatureLastUpdated | Format-List" \
        "T1518.001" \
        "Windows Defender status and signature age"

    execute_ps \
        "Get-Service | Where-Object {\$_.DisplayName -match 'Defender|CrowdStrike|Carbon Black|SentinelOne|Sophos|Symantec|McAfee|ESET|Kaspersky|Trend Micro|Palo Alto|Cylance|Elastic|Splunk|Sysmon'} | Select-Object Name,DisplayName,Status | Format-Table -AutoSize" \
        "T1518.001" \
        "Enumerating security products (EDR/AV/SIEM agents)"

    execute_ps \
        "Get-WinSystemLocale | Format-List; Get-Culture | Select-Object Name,DisplayName | Format-List; (Get-TimeZone).DisplayName" \
        "T1614.001" \
        "System locale and timezone (geopolitical targeting context)"

    execute_ps \
        "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue | Select-Object EnableLUA,ConsentPromptBehaviorAdmin,FilterAdministratorToken | Format-List" \
        "T1082" \
        "UAC configuration"

    end_phase
}

# ============================================================================
# PHASE 2: ACCOUNT & PRIVILEGE DISCOVERY
# Domain-aware enumeration for lateral movement planning
# ============================================================================

phase_account_discovery() {
    begin_phase 2 "Account & Privilege Discovery" \
        "T1087.001, T1087.002, T1069.001, T1069.002, T1201, T1033" \
        "Enumerate local/domain accounts, groups, privileges, and password policy"

    execute_ps \
        "whoami /all" \
        "T1033" \
        "Current user identity, groups, and privileges"

    execute_ps \
        "Get-LocalUser | Select-Object Name,Enabled,LastLogon,PasswordLastSet,PasswordExpires,AccountExpires,Description | Format-Table -AutoSize" \
        "T1087.001" \
        "Enumerating local user accounts"

    execute_ps \
        "Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | Select-Object Name,ObjectClass,PrincipalSource | Format-Table -AutoSize" \
        "T1069.001" \
        "Members of local Administrators group"

    execute_ps \
        "Get-LocalGroup | Select-Object Name,Description | Format-Table -AutoSize" \
        "T1069.001" \
        "Enumerating all local groups"

    execute_ps \
        "Get-LocalGroupMember -Group 'Remote Desktop Users' -ErrorAction SilentlyContinue | Select-Object Name,ObjectClass | Format-Table -AutoSize" \
        "T1069.001" \
        "Remote Desktop Users (lateral movement targets)"

    execute_ps \
        "net accounts 2>\$null" \
        "T1201" \
        "Local password policy (lockout threshold, min length, history)"

    execute_ps \
        "Get-WmiObject Win32_ComputerSystem | Select-Object PartOfDomain,Domain,DomainRole | Format-List" \
        "T1087.002" \
        "Domain membership and role"

    execute_ps \
        "try { \$searcher = [adsisearcher]'(&(objectCategory=person)(objectClass=user)(adminCount=1))'; \$searcher.FindAll() | ForEach-Object { \$_.Properties['samaccountname'] } | Select-Object -First 20 } catch { Write-Output 'Domain enumeration not available (workgroup or access denied)' }" \
        "T1087.002" \
        "Domain admin accounts (LDAP adminCount=1)"

    execute_ps \
        "try { nltest /dclist:\$env:USERDOMAIN 2>\$null } catch { Write-Output 'Domain controller enumeration not available' }" \
        "T1018" \
        "Domain controller enumeration"

    execute_ps \
        "Get-WmiObject Win32_LoggedOnUser -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Dependent | Select-Object -Property Name -Unique | Select-Object -First 10 | Format-Table" \
        "T1033" \
        "Currently logged-on users"

    execute_ps \
        "try { net accounts /domain 2>\$null } catch { Write-Output 'Domain password policy not available' }" \
        "T1201" \
        "Domain password policy"

    end_phase
}

# ============================================================================
# PHASE 3: PROCESS & SERVICE INTELLIGENCE
# Identify security tools, financial apps, and opportunities
# ============================================================================

phase_process_discovery() {
    begin_phase 3 "Process & Service Intelligence" \
        "T1057, T1007, T1518.001, T1497.001" \
        "Map running processes — security tools, financial applications, analysis tools"

    execute_ps \
        "Get-Process | Select-Object Name,Id,Path,Company,CPU,WorkingSet64 | Sort-Object CPU -Descending | Select-Object -First 30 | Format-Table -AutoSize" \
        "T1057" \
        "Top processes by CPU (anomaly baseline)"

    execute_ps \
        "Get-Process | Where-Object {\$_.Name -match 'MsMpEng|MsSense|SenseIR|SenseCncProxy|WinDefend|csfalcon|CSFalconService|CSFalconContainer|cb|CbDefense|RepMgr|SentinelAgent|SentinelOne|sophos|SAVService|hmpalert|SEP|ccSvcHst|SymCorpUI|mcshield|mfemms|ESET|ekrn|avp|kavfs|TMCCSvc|Traps|CortexXDR|CylanceSvc|elastic-agent|filebeat|winlogbeat|splunkd|ossec'} | Select-Object Name,Id,Path | Format-Table -AutoSize" \
        "T1518.001" \
        "Security software process enumeration (EDR/AV/SIEM)"

    execute_ps \
        "Get-Process | Where-Object {\$_.Name -match 'wireshark|procmon|procexp|x64dbg|x32dbg|ollydbg|ida|ghidra|fiddler|burp|charles|dnspy|pestudio|hxd|sysinternals'} | Select-Object Name,Id | Format-Table" \
        "T1497.001" \
        "Analysis/debugging tools detection (analyst watching?)"

    execute_ps \
        "Get-Process | Where-Object {\$_.Name -match 'outlook|teams|slack|zoom|skype|webex|firefox|chrome|msedge|iexplore|thunderbird'} | Select-Object Name,Id | Format-Table" \
        "T1057" \
        "Communication and browser processes"

    execute_ps \
        "Get-Process | Where-Object {\$_.Name -match 'sql|oracle|swift|bloomberg|reuters|trading|fidelity|schwab|citi|chase|sap|sage|quickbooks|dynamics|navision|workday|peoplesoft'} | Select-Object Name,Id,Path | Format-Table" \
        "T1057" \
        "Financial / ERP / trading application processes"

    execute_ps \
        "Get-Service | Where-Object {\$_.Status -eq 'Running'} | Select-Object Name,DisplayName,StartType | Sort-Object DisplayName | Format-Table -AutoSize" \
        "T1007" \
        "All running services"

    execute_ps \
        "Get-Service | Where-Object {\$_.DisplayName -match 'Defender|Firewall|Update|Sense|SmartScreen|DLP|Endpoint|Audit|Sysmon'} | Select-Object Name,DisplayName,Status,StartType | Format-Table -AutoSize" \
        "T1007" \
        "Security-relevant services status"

    end_phase
}

# ============================================================================
# PHASE 4: FILE & DIRECTORY DISCOVERY
# Sensitive document hunting: financial data, keys, configs, databases
# ============================================================================

phase_file_discovery() {
    begin_phase 4 "Sensitive File & Directory Discovery" \
        "T1083, T1005, T1552.001" \
        "Hunt for financial documents, certificates, configs, credential files, databases"

    ((TOTAL_ACTIONS++))
    print_action "Searching user directories for sensitive documents..."

    local found_files=0
    local search_patterns=(
        "*.pdf" "*.doc" "*.docx" "*.xls" "*.xlsx" "*.pptx"
        "*.csv" "*.mdb" "*.accdb" "*.sqlite" "*.kdbx"
        "*.pfx" "*.p12" "*.pem" "*.cer" "*.key"
        "*.rdp" "*.ovpn" "*.conf" "*.config" "*.ini" "*.env"
    )
    local search_locations=(
        "$WINDOWS_SYSTEM/Users/*/Desktop"
        "$WINDOWS_SYSTEM/Users/*/Documents"
        "$WINDOWS_SYSTEM/Users/*/Downloads"
        "$WINDOWS_SYSTEM/Users/*/OneDrive"
    )

    {
        printf '    %s File Discovery Scan\n' "$B_TL$B_H"
        printf '    %s\n' "$B_V"
    } >> "$LOG_FILE"

    for location in "${search_locations[@]}"; do
        if [ -d "$location" ] 2>/dev/null; then
            for pattern in "${search_patterns[@]}"; do
                while IFS= read -r file; do
                    printf '    %s  [FOUND] %s\n' "$B_V" "$file" >> "$LOG_FILE"
                    ((found_files++))
                done < <(safe_find "$location" "$pattern" 10)
            done
        fi
    done

    {
        printf '    %s\n' "$B_V"
        printf '    %s  Total files found: %d\n' "$B_V" "$found_files"
        printf '    %s\n' "$B_BL$B_H"
        printf '\n'
    } >> "$LOG_FILE"

    if [ $found_files -gt 0 ]; then
        print_success "Found $found_files sensitive files across user directories" "T1083"
        print_finding "MEDIUM" "$found_files sensitive files accessible from WSL"
    else
        print_info "No accessible files found in user directories"
        ((FAILED_ACTIONS++))
    fi

    # SSH keys
    ((TOTAL_ACTIONS++))
    print_action "Hunting for SSH keys and config..."
    local ssh_found=0
    for ssh_dir in "$WINDOWS_SYSTEM/Users/"*/.ssh; do
        if [ -d "$ssh_dir" ]; then
            {
                printf '    %s SSH Directory: %s\n' "$B_TL$B_H" "$ssh_dir"
                ls -la "$ssh_dir" 2>/dev/null | sed "s/^/    $B_V  /"
                printf '    %s\n' "$B_BL$B_H"
            } >> "$LOG_FILE"
            ((ssh_found++))
        fi
    done
    if [ $ssh_found -gt 0 ]; then
        print_success "Found $ssh_found SSH directories" "T1552.004"
        print_finding "HIGH" "SSH key directories accessible — potential lateral movement keys"
    else
        print_info "No SSH directories found"
        ((FAILED_ACTIONS++))
    fi

    # KeePass / password manager databases
    ((TOTAL_ACTIONS++))
    print_action "Searching for password manager databases..."
    local kp_found=0
    while IFS= read -r f; do
        print_detail "Password DB: $f"
        ((kp_found++))
    done < <(safe_find "$WINDOWS_SYSTEM/Users" "*.kdbx" 5)
    if [ $kp_found -gt 0 ]; then
        print_success "Found $kp_found password manager databases" "T1555"
        print_finding "HIGH" "KeePass databases found — master password attack surface"
    else
        print_info "No password manager databases found"
        ((SKIPPED_ACTIONS++))
    fi

    # Certificate files
    execute_ps \
        "Get-ChildItem -Path C:\Users -Recurse -Include *.pfx,*.p12,*.pem,*.cer,*.key -ErrorAction SilentlyContinue | Select-Object -First 15 FullName,Length,LastWriteTime | Format-Table -AutoSize" \
        "T1552.004" \
        "Certificate and private key files"

    # RDP connection files
    execute_ps \
        "Get-ChildItem -Path C:\Users -Recurse -Include *.rdp -ErrorAction SilentlyContinue | Select-Object -First 10 FullName,LastWriteTime | Format-Table" \
        "T1083" \
        "RDP connection files (lateral movement targets)"

    # Recently accessed files
    execute_ps \
        "Get-ChildItem -Path 'C:\Users\*\AppData\Roaming\Microsoft\Windows\Recent' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15 Name,LastWriteTime | Format-Table" \
        "T1083" \
        "Recently accessed files (user activity profiling)"

    end_phase
}

# ============================================================================
# PHASE 5: CREDENTIAL ACCESS RECONNAISSANCE
# Map all credential stores and harvest paths without extraction
# ============================================================================

phase_credential_search() {
    begin_phase 5 "Credential Access Reconnaissance" \
        "T1552.001, T1555.003, T1555.004, T1003.001, T1552.006, T1555" \
        "Map credential stores: browsers, vault, LSASS, SAM, cached creds, cloud tokens"

    # Files containing credential keywords
    ((TOTAL_ACTIONS++))
    print_action "Scanning for plaintext credentials in user files..."
    local cred_keywords=("password" "passwd" "secret" "token" "api_key" "apikey" "connection_string" "jdbc:" "sqlplus")
    local found_creds=0

    {
        printf '    %s Credential Keyword Scan\n' "$B_TL$B_H"
        printf '    %s\n' "$B_V"
    } >> "$LOG_FILE"

    for keyword in "${cred_keywords[@]}"; do
        while IFS= read -r file; do
            printf '    %s  [%s] %s\n' "$B_V" "$keyword" "$file" >> "$LOG_FILE"
            ((found_creds++))
        done < <(safe_grep "$keyword" "$WINDOWS_SYSTEM/Users/*/Documents" 5)
        while IFS= read -r file; do
            printf '    %s  [%s] %s\n' "$B_V" "$keyword" "$file" >> "$LOG_FILE"
            ((found_creds++))
        done < <(safe_grep "$keyword" "$WINDOWS_SYSTEM/Users/*/Desktop" 3)
    done

    {
        printf '    %s\n' "$B_V"
        printf '    %s  Potential credential files: %d\n' "$B_V" "$found_creds"
        printf '    %s\n' "$B_BL$B_H"
    } >> "$LOG_FILE"

    if [ $found_creds -gt 0 ]; then
        print_success "Found $found_creds files containing credential keywords" "T1552.001"
        print_finding "HIGH" "$found_creds files with embedded credentials/tokens"
    else
        print_info "No plaintext credential files found"
        ((FAILED_ACTIONS++))
    fi

    # Browser credential stores
    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Login Data' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table; Get-ChildItem 'C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Cookies' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table" \
        "T1555.003" \
        "Chrome credential and cookie databases"

    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles\*\logins.json' -ErrorAction SilentlyContinue | Select-Object FullName,Length | Format-Table; Get-ChildItem 'C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles\*\key*.db' -ErrorAction SilentlyContinue | Select-Object FullName | Format-Table" \
        "T1555.003" \
        "Firefox credential databases"

    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Local\Microsoft\Edge\User Data\Default\Login Data' -ErrorAction SilentlyContinue | Select-Object FullName,Length,LastWriteTime | Format-Table" \
        "T1555.003" \
        "Edge credential database"

    # Windows Credential Manager
    execute_ps \
        "cmdkey /list 2>\$null" \
        "T1555.004" \
        "Windows Credential Manager stored credentials"

    # PowerShell history
    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output ('History: ' + \$_.FullName + ' (Size: ' + \$_.Length + ')'); Get-Content \$_.FullName -Tail 30 -ErrorAction SilentlyContinue | Select-String -Pattern 'password|secret|token|key|credential|connect' -SimpleMatch }" \
        "T1552.001" \
        "PowerShell history — credential keywords"

    # LSASS accessibility check
    execute_ps \
        "Get-Process lsass -ErrorAction SilentlyContinue | Select-Object Id,HandleCount,WorkingSet64 | Format-List; \$lsass = Get-Process lsass -ErrorAction SilentlyContinue; if (\$lsass) { Write-Output \"LSASS PID: \$(\$lsass.Id) — credential extraction target\" }" \
        "T1003.001" \
        "LSASS process accessibility (credential dump target)"

    # SAM / SYSTEM hive accessibility
    execute_ps \
        "Test-Path 'C:\Windows\System32\config\SAM'; Test-Path 'C:\Windows\System32\config\SYSTEM'; icacls 'C:\Windows\System32\config\SAM' 2>\$null | Select-Object -First 5" \
        "T1003.002" \
        "SAM/SYSTEM hive accessibility"

    # Cached domain credentials
    execute_ps \
        "Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue | Select-Object DefaultUserName,DefaultDomainName,AutoAdminLogon,CachedLogonsCount | Format-List" \
        "T1003.005" \
        "Cached logon credentials and auto-logon config"

    # Cloud credential files
    ((TOTAL_ACTIONS++))
    print_action "Scanning for cloud provider credential files..."
    local cloud_found=0
    local cloud_paths=(
        "$WINDOWS_SYSTEM/Users/*/.aws/credentials"
        "$WINDOWS_SYSTEM/Users/*/.azure/accessTokens.json"
        "$WINDOWS_SYSTEM/Users/*/.config/gcloud/credentials.db"
        "$WINDOWS_SYSTEM/Users/*/.config/gcloud/application_default_credentials.json"
    )
    for cpath in "${cloud_paths[@]}"; do
        for f in $cpath; do
            if [ -f "$f" ] 2>/dev/null; then
                print_detail "Cloud cred: $f"
                log_text 8 "[CLOUD CRED] $f"
                ((cloud_found++))
            fi
        done
    done
    if [ $cloud_found -gt 0 ]; then
        print_success "Found $cloud_found cloud credential files" "T1552.001"
        print_finding "HIGH" "Cloud provider credentials accessible (AWS/Azure/GCP)"
    else
        print_info "No cloud credential files found"
        ((SKIPPED_ACTIONS++))
    fi

    # WiFi passwords
    execute_ps \
        "netsh wlan show profiles 2>\$null | Select-String 'All User Profile' | ForEach-Object { \$p = (\$_ -split ':')[1].Trim(); Write-Output \"Profile: \$p\" }" \
        "T1552.006" \
        "Saved WiFi profiles (password extraction targets)"

    end_phase
}

# ============================================================================
# PHASE 6: DEFENSE EVASION RECONNAISSANCE
# Understand what the blue team can see, find blind spots
# ============================================================================

phase_defense_evasion_recon() {
    begin_phase 6 "Defense Evasion Reconnaissance" \
        "T1562.001, T1562.004, T1218, T1036, T1027" \
        "Map security controls, logging config, AMSI, AppLocker, firewall rules"

    # PowerShell logging configuration
    execute_ps \
        "Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -ErrorAction SilentlyContinue | Format-List; Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging' -ErrorAction SilentlyContinue | Format-List; Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription' -ErrorAction SilentlyContinue | Format-List" \
        "T1562.001" \
        "PowerShell logging configuration (ScriptBlock, Module, Transcription)"

    # Sysmon presence and config
    execute_ps \
        "\$svc = Get-Service Sysmon* -ErrorAction SilentlyContinue; if (\$svc) { \$svc | Format-List Name,DisplayName,Status; Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\SysmonDrv' -ErrorAction SilentlyContinue | Select-Object ImagePath | Format-List } else { Write-Output 'Sysmon not installed' }" \
        "T1518.001" \
        "Sysmon presence and driver path"

    # Windows Firewall rules
    execute_ps \
        "Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction,LogAllowed,LogBlocked,LogFileName | Format-Table -AutoSize" \
        "T1562.004" \
        "Windows Firewall profile status"

    execute_ps \
        "Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow -ErrorAction SilentlyContinue | Select-Object -First 20 DisplayName,Profile,Protocol,LocalPort | Format-Table -AutoSize" \
        "T1562.004" \
        "Inbound firewall allow rules (attack surface)"

    # AppLocker policy
    execute_ps \
        "Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RuleCollections | Select-Object -First 10 | Format-Table" \
        "T1562.001" \
        "AppLocker policy (application whitelisting)"

    # AMSI providers
    execute_ps \
        "Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers' -ErrorAction SilentlyContinue | ForEach-Object { Write-Output \"AMSI Provider: \$(\$_.PSChildName)\" }" \
        "T1562.001" \
        "AMSI providers (anti-malware scan interface)"

    # Event log sizes and retention
    execute_ps \
        "Get-WinEvent -ListLog Security,System,Application,'Microsoft-Windows-Sysmon/Operational','Microsoft-Windows-PowerShell/Operational' -ErrorAction SilentlyContinue | Select-Object LogName,IsEnabled,MaximumSizeInBytes,RecordCount,LogMode | Format-Table -AutoSize" \
        "T1562.002" \
        "Event log configuration (size, retention, status)"

    # Audit policy
    execute_ps \
        "auditpol /get /category:* 2>\$null | Select-String -Pattern 'Success|Failure' | Select-Object -First 20" \
        "T1562.002" \
        "Windows audit policy settings"

    # WDAC / Device Guard
    execute_ps \
        "Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction SilentlyContinue | Select-Object * | Format-List" \
        "T1562.001" \
        "Device Guard / WDAC status"

    # Constrained Language Mode check
    execute_ps \
        "\$ExecutionContext.SessionState.LanguageMode" \
        "T1562.001" \
        "PowerShell language mode (constrained = hardened)"

    # LSA protection
    execute_ps \
        "Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue | Select-Object RunAsPPL,LimitBlankPasswordUse,NoLMHash,RestrictAnonymous | Format-List" \
        "T1003" \
        "LSA protection and credential hardening"

    end_phase
}

# ============================================================================
# PHASE 7: NETWORK TOPOLOGY & LATERAL MOVEMENT RECON
# Map the network for pivot points, domain trusts, internal services
# ============================================================================

phase_network_discovery() {
    begin_phase 7 "Network Topology & Lateral Movement Recon" \
        "T1049, T1018, T1016, T1135, T1046, T1482" \
        "Map network interfaces, connections, shares, trusts, and pivot points"

    execute_ps \
        "Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer | Format-List" \
        "T1016" \
        "Network interface configuration"

    execute_ps \
        "Get-NetAdapter | Select-Object Name,Status,MacAddress,LinkSpeed,InterfaceDescription | Format-Table -AutoSize" \
        "T1016" \
        "Network adapter enumeration"

    execute_ps \
        "Get-NetTCPConnection | Where-Object {\$_.State -eq 'Established'} | Select-Object LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess | Format-Table -AutoSize" \
        "T1049" \
        "Established TCP connections"

    execute_ps \
        "Get-NetTCPConnection | Where-Object {\$_.State -eq 'Listen'} | Select-Object LocalAddress,LocalPort,OwningProcess | Sort-Object LocalPort | Format-Table -AutoSize" \
        "T1049" \
        "Listening TCP ports (service exposure)"

    execute_ps \
        "Get-SmbShare -ErrorAction SilentlyContinue | Select-Object Name,Path,Description,CurrentUsers | Format-Table -AutoSize" \
        "T1135" \
        "Local SMB shares"

    execute_ps \
        "Get-SmbMapping -ErrorAction SilentlyContinue | Select-Object LocalPath,RemotePath,Status | Format-Table" \
        "T1135" \
        "Mapped network drives (lateral movement paths)"

    execute_ps \
        "Get-NetNeighbor | Where-Object {\$_.State -ne 'Unreachable'} | Select-Object IPAddress,LinkLayerAddress,State,InterfaceAlias | Format-Table -AutoSize" \
        "T1018" \
        "ARP neighbor table (local network hosts)"

    execute_ps \
        "Get-DnsClientCache -ErrorAction SilentlyContinue | Select-Object -First 25 Entry,RecordName,Data | Format-Table -AutoSize" \
        "T1018" \
        "DNS client cache (recently resolved hosts)"

    execute_ps \
        "Get-NetRoute | Where-Object {\$_.DestinationPrefix -ne '0.0.0.0/0' -and \$_.DestinationPrefix -notlike 'ff*' -and \$_.DestinationPrefix -notlike 'fe*'} | Select-Object -First 15 DestinationPrefix,NextHop,InterfaceAlias,RouteMetric | Format-Table" \
        "T1016" \
        "Routing table (network segmentation map)"

    execute_ps \
        "try { nltest /domain_trusts 2>\$null } catch { Write-Output 'Domain trust enumeration not available' }" \
        "T1482" \
        "Active Directory domain trusts"

    execute_ps \
        "Get-ItemProperty 'HKCU:\Software\Microsoft\Terminal Server Client\Servers\*' -ErrorAction SilentlyContinue | Select-Object PSChildName,UsernameHint | Format-Table" \
        "T1018" \
        "RDP connection history (previous lateral movement targets)"

    execute_ps \
        "netsh interface portproxy show all 2>\$null" \
        "T1090" \
        "Port proxy / forwarding rules"

    end_phase
}

# ============================================================================
# PHASE 8: COLLECTION & STAGING
# Gather high-value data, stage for exfiltration
# ============================================================================

phase_automated_collection() {
    begin_phase 8 "Collection & Staging" \
        "T1119, T1005, T1074.001, T1114.001, T1113" \
        "Collect high-value documents, emails, and stage for exfiltration review"

    ((TOTAL_ACTIONS++))
    local collection_dir
    collection_dir="/tmp/collected_data_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$collection_dir" 2>/dev/null

    if [ ! -d "$collection_dir" ]; then
        print_error "Failed to create collection directory" "T1074.001"
        return 1
    fi

    print_action "Staging directory: $collection_dir"

    local collected_count=0
    local file_size_limit=10240

    {
        printf '    %s Collection & Staging\n' "$B_TL$B_H"
        printf '    %s  Staging directory: %s\n' "$B_V" "$collection_dir"
        printf '    %s  Size limit: %d bytes\n' "$B_V" "$file_size_limit"
        printf '    %s\n' "$B_V"
    } >> "$LOG_FILE"

    for file in $(safe_find "$WINDOWS_SYSTEM/Users/*/Desktop" "*.txt" 5); do
        if [ -f "$file" ] && [ -r "$file" ]; then
            local fsize
            fsize=$(stat -c%s "$file" 2>/dev/null || echo 999999)
            if [ "$fsize" -lt "$file_size_limit" ]; then
                cp "$file" "$collection_dir/" 2>/dev/null && {
                    printf '    %s  [STAGED] %s (%s bytes)\n' "$B_V" "$file" "$fsize" >> "$LOG_FILE"
                    ((collected_count++))
                }
            fi
        fi
    done

    {
        printf '    %s\n' "$B_V"
        printf '    %s  Total staged: %d files\n' "$B_V" "$collected_count"
        printf '    %s\n' "$B_BL$B_H"
    } >> "$LOG_FILE"

    if [ $collected_count -gt 0 ]; then
        print_success "Staged $collected_count files for review" "T1074.001"
    else
        print_info "No files staged (access restrictions or empty directories)"
        rmdir "$collection_dir" 2>/dev/null
        ((FAILED_ACTIONS++))
    fi

    # Email file discovery
    execute_ps \
        "Get-ChildItem -Path C:\Users -Recurse -Include *.pst,*.ost,*.eml,*.msg -ErrorAction SilentlyContinue | Select-Object -First 10 FullName,Length,LastWriteTime | Format-Table -AutoSize" \
        "T1114.001" \
        "Email archive files (.pst, .ost, .eml, .msg)"

    # Clipboard content
    execute_ps \
        "try { Get-Clipboard -ErrorAction SilentlyContinue | Select-Object -First 5 } catch { Write-Output 'Clipboard not accessible' }" \
        "T1115" \
        "Current clipboard contents"

    # Recent Office documents
    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Office\Recent' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15 Name,LastWriteTime | Format-Table" \
        "T1005" \
        "Recently opened Office documents"

    # Downloads folder profiling
    execute_ps \
        "Get-ChildItem 'C:\Users\*\Downloads' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 15 Name,Length,LastWriteTime | Format-Table -AutoSize" \
        "T1005" \
        "Downloads folder contents (recent activity)"

    end_phase
}

# ============================================================================
# PHASE 9: PERSISTENCE MECHANISM RECONNAISSANCE
# Comprehensive persistence vector mapping
# ============================================================================

phase_persistence_recon() {
    begin_phase 9 "Persistence Mechanism Reconnaissance" \
        "T1547.001, T1053.005, T1543.003, T1546.003, T1574.001, T1546.015" \
        "Map all persistence vectors: startup, tasks, services, WMI, COM, DLL hijack"

    # Registry Run keys (comprehensive)
    execute_ps \
        "Write-Output '--- HKLM Run ---'; Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List; Write-Output '--- HKLM RunOnce ---'; Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue | Format-List; Write-Output '--- HKCU Run ---'; Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List; Write-Output '--- HKCU RunOnce ---'; Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue | Format-List" \
        "T1547.001" \
        "Registry Run/RunOnce keys (all hives)"

    # Startup folder
    execute_ps \
        "Get-ChildItem 'C:\Users\*\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup' -ErrorAction SilentlyContinue | Select-Object FullName,LastWriteTime | Format-Table; Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup' -ErrorAction SilentlyContinue | Select-Object FullName,LastWriteTime | Format-Table" \
        "T1547.001" \
        "User and system startup folders"

    # Scheduled tasks (detailed)
    execute_ps \
        "Get-ScheduledTask | Where-Object {\$_.State -eq 'Ready'} | ForEach-Object { [PSCustomObject]@{Name=\$_.TaskName; Path=\$_.TaskPath; State=\$_.State; Author=\$_.Author; Actions=(\$_.Actions | ForEach-Object { \$_.Execute }) -join ', '} } | Select-Object -First 25 | Format-Table -AutoSize -Wrap" \
        "T1053.005" \
        "Active scheduled tasks with action details"

    # Auto-start services with binary paths (writable service binaries = escalation)
    execute_ps \
        "Get-WmiObject Win32_Service | Where-Object {\$_.StartMode -eq 'Auto' -and \$_.State -eq 'Running'} | Select-Object -First 25 Name,DisplayName,PathName,StartMode | Format-Table -AutoSize -Wrap" \
        "T1543.003" \
        "Auto-start services with binary paths"

    # Unquoted service paths (privilege escalation vector)
    execute_ps \
        'Get-WmiObject Win32_Service | Where-Object {$_.PathName -and $_.PathName -notmatch '"'"'^"'"'"' -and $_.PathName -match '"'"' '"'"'} | Select-Object Name,PathName,StartMode | Format-Table -AutoSize -Wrap' \
        "T1574.009" \
        "Unquoted service paths (privilege escalation)"

    # WMI event subscriptions
    execute_ps \
        "Get-WmiObject -Namespace root\Subscription -Class __EventFilter -ErrorAction SilentlyContinue | Select-Object Name,Query | Format-Table; Get-WmiObject -Namespace root\Subscription -Class CommandLineEventConsumer -ErrorAction SilentlyContinue | Select-Object Name,CommandLineTemplate | Format-Table" \
        "T1546.003" \
        "WMI event subscriptions (stealthy persistence)"

    # COM object hijacking opportunities
    execute_ps \
        'Get-ItemProperty "HKCU:\Software\Classes\CLSID\*\InProcServer32" -ErrorAction SilentlyContinue | Where-Object {$_."(default)" -ne $null} | Select-Object -First 10 PSPath,"(default)" | Format-Table' \
        "T1546.015" \
        "COM object registrations (hijack opportunities)"

    # DLL search order hijack — writable directories in PATH
    execute_ps \
        "\$env:PATH -split ';' | ForEach-Object { if (\$_ -and (Test-Path \$_ -ErrorAction SilentlyContinue)) { \$acl = Get-Acl \$_ -ErrorAction SilentlyContinue; [PSCustomObject]@{Path=\$_; Owner=\$acl.Owner} } } | Format-Table -AutoSize" \
        "T1574.001" \
        "PATH directories and ownership (DLL hijack surface)"

    # Boot Execute
    execute_ps \
        "Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue | Select-Object BootExecute | Format-List" \
        "T1547" \
        "Boot execute programs"

    end_phase
}

# ============================================================================
# PHASE 10: IMPACT SIMULATION (Ransomware / Destructive TTPs)
# Reconnaissance only — no encryption, no deletion, no harm
# ============================================================================

phase_impact_simulation() {
    begin_phase 10 "Impact Simulation ${C_YELLOW}(Reconnaissance Only)${C_RESET}" \
        "T1486, T1490, T1489, T1529, T1485" \
        "Simulate ransomware recon: shadow copies, backups, critical services, recovery config"

    print_warning "SIMULATION ONLY — no encryption, deletion, or service disruption"
    printf '\n'

    # Shadow copies
    execute_ps \
        "Get-WmiObject Win32_ShadowCopy -ErrorAction SilentlyContinue | Select-Object ID,VolumeName,InstallDate,DeviceObject | Format-Table -AutoSize" \
        "T1490" \
        "Volume Shadow Copy enumeration"

    # VSS service
    execute_ps \
        "Get-Service VSS -ErrorAction SilentlyContinue | Select-Object Name,DisplayName,Status,StartType | Format-List" \
        "T1490" \
        "Volume Shadow Copy Service status"

    # Windows backup
    execute_ps \
        "Get-WBSummary -ErrorAction SilentlyContinue | Format-List; Get-WBPolicy -ErrorAction SilentlyContinue | Format-List" \
        "T1490" \
        "Windows Backup configuration and last run"

    # Backup and recovery services
    execute_ps \
        "Get-Service | Where-Object {\$_.Name -match 'backup|vss|wbengine|sql|exchange|vmware|veeam|acronis|commvault|netbackup|arcserve'} | Select-Object Name,DisplayName,Status,StartType | Format-Table -AutoSize" \
        "T1489" \
        "Backup and business-critical services"

    # Database services (high-value targets)
    execute_ps \
        "Get-Service | Where-Object {\$_.Name -match 'MSSQL|MySQL|postgres|oracle|mongodb|redis|elasticsearch|MariaDB'} | Select-Object Name,DisplayName,Status,StartType | Format-Table -AutoSize" \
        "T1489" \
        "Database service enumeration"

    # Ransomware target file count
    ((TOTAL_ACTIONS++))
    print_action "Counting potential encryption targets..."

    {
        printf '    %s Ransomware Target Assessment\n' "$B_TL$B_H"
        printf '    %s  NOTE: Enumeration only — NO encryption\n' "$B_V"
        printf '    %s\n' "$B_V"
    } >> "$LOG_FILE"

    local target_extensions=("*.docx" "*.xlsx" "*.pdf" "*.jpg" "*.png" "*.pptx" "*.zip" "*.mdb" "*.accdb" "*.pst" "*.bak" "*.sql")
    local target_count=0

    for ext in "${target_extensions[@]}"; do
        for location in "$WINDOWS_SYSTEM/Users/*/Documents" "$WINDOWS_SYSTEM/Users/*/Desktop" "$WINDOWS_SYSTEM/Users/*/Downloads"; do
            if [ -d "$location" ] 2>/dev/null; then
                while IFS= read -r file; do
                    printf '    %s  [TARGET] %s\n' "$B_V" "$file" >> "$LOG_FILE"
                    ((target_count++))
                done < <(safe_find "$location" "$ext" 10)
            fi
        done
    done

    {
        printf '    %s\n' "$B_V"
        printf '    %s  Potential targets: %d files\n' "$B_V" "$target_count"
        printf '    %s\n' "$B_BL$B_H"
    } >> "$LOG_FILE"

    if [ $target_count -gt 0 ]; then
        print_success "Identified $target_count potential encryption targets" "T1486"
        print_finding "INFO" "$target_count files would be impacted in real ransomware scenario"
    else
        print_info "No target files found"
        ((FAILED_ACTIONS++))
    fi

    # Ransom note indicator
    print_action "Creating simulation ransom note indicator..."
    ((TOTAL_ACTIONS++))

    local ransom_note="/tmp/RANSOMWARE_NOTE_PURPLETEAM.txt"
    cat > "$ransom_note" <<'RANSOMNOTE'
╔══════════════════════════════════════════════════════════════╗
║              PURPLE TEAM EXERCISE INDICATOR                  ║
║               RANSOMWARE NOTE SIMULATION                     ║
╚══════════════════════════════════════════════════════════════╝

  THIS IS A SIMULATED RANSOM NOTE FOR PURPLE TEAM TRAINING.
  NO FILES HAVE BEEN ENCRYPTED. NO DATA WAS HARMED.

  In a real attack, this note would contain:
    - Ransom amount and cryptocurrency wallet
    - Deadline and escalation threats
    - Data leak threats (double extortion)
    - "Support" contact channels

  Blue Team Detection Opportunities:
    - File creation in unusual locations
    - Suspicious naming pattern (RANSOMWARE_NOTE_*)
    - WSL process spawning PowerShell
    - Rapid file enumeration across directories
    - Shadow copy / backup service queries
    - Service stop attempts

  MITRE ATT&CK: T1486 (Data Encrypted for Impact)
RANSOMNOTE

    if [ -f "$ransom_note" ]; then
        print_success "Ransom note indicator created: $ransom_note" "T1486"
    else
        print_error "Failed to create ransom note indicator" "T1486"
    fi

    # Event log clearing capability check (not actually clearing)
    execute_ps \
        "Get-WinEvent -ListLog Security,System,Application -ErrorAction SilentlyContinue | Select-Object LogName,RecordCount,MaximumSizeInBytes | Format-Table" \
        "T1070.001" \
        "Event log sizes (clearing impact assessment)"

    # System recovery configuration
    execute_ps \
        "bcdedit /enum 2>\$null | Select-Object -First 20; Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot' -ErrorAction SilentlyContinue | Format-List" \
        "T1490" \
        "Boot configuration and recovery options"

    # Mapped drives (ransomware lateral spread)
    execute_ps \
        "Get-PSDrive -PSProvider FileSystem | Where-Object {\$_.Root -match '\\\\\\\\' } | Select-Object Name,Root,Used,Free | Format-Table" \
        "T1486" \
        "Network drives (lateral encryption targets)"

    print_warning "Impact simulation complete — no files were harmed, no services disrupted"

    end_phase
}

# ============================================================================
# HELP AND USAGE
# ============================================================================

show_help() {
    printf '%b' "$C_CYAN"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════╗
║                     PURPLE TEAM AGENT v4.0                               ║
║          Advanced Adversary Simulation — Financial / Gov Sector          ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
    printf '%b' "$C_RESET"
    printf '\n'
    printf '%b%s%b\n' "$C_WHITE" "USAGE:" "$C_RESET"
    printf '    %s [OPTIONS]\n' "$0"
    printf '\n'
    printf '%b%s%b\n' "$C_WHITE" "OPTIONS:" "$C_RESET"
    printf '    %b-h, --help%b              Show this help message\n' "$C_GREEN" "$C_RESET"
    printf '    %b-a, --all%b               Run all phases (default)\n' "$C_GREEN" "$C_RESET"
    printf '    %b-p, --phase <N[,N]>%b     Run specific phase(s) (1-10)\n' "$C_GREEN" "$C_RESET"
    printf '    %b-l, --list%b              List available phases\n' "$C_GREEN" "$C_RESET"
    printf '    %b-q, --quiet%b             Minimal terminal output\n' "$C_GREEN" "$C_RESET"
    printf '    %b-v, --verbose%b           Verbose / debug output\n' "$C_GREEN" "$C_RESET"
    printf '\n'
    printf '%b%s%b\n' "$C_WHITE" "PHASES:" "$C_RESET"
    printf '    %bPhase  1%b — System & Environment Profiling     (T1082, T1497, T1614)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  2%b — Account & Privilege Discovery      (T1087, T1069, T1201)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  3%b — Process & Service Intelligence     (T1057, T1007, T1518)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  4%b — Sensitive File Discovery           (T1083, T1005, T1552)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  5%b — Credential Access Reconnaissance   (T1555, T1003, T1552)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  6%b — Defense Evasion Reconnaissance     (T1562, T1218, T1027)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  7%b — Network & Lateral Movement Recon   (T1049, T1018, T1482)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  8%b — Collection & Staging               (T1119, T1074, T1114)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase  9%b — Persistence Mechanism Recon        (T1547, T1053, T1546)\n' "$C_CYAN" "$C_RESET"
    printf '    %bPhase 10%b — Impact Simulation (No Harm)        (T1486, T1490, T1489)\n' "$C_MAGENTA" "$C_RESET"
    printf '\n'
    printf '%b%s%b\n' "$C_WHITE" "EXAMPLES:" "$C_RESET"
    printf '    %s --all                 # Run all phases\n' "$0"
    printf '    %s --phase 1             # System profiling only\n' "$0"
    printf '    %s --phase 5,6,7         # Credentials, defenses, network\n' "$0"
    printf '    %s --list                # Show phase details\n' "$0"
    printf '\n'
    printf '%b%s%b\n' "$C_WHITE" "OUTPUT:" "$C_RESET"
    printf '    Terminal:   Colour-coded with findings severity\n'
    printf '    Text Log:   /tmp/purpleteam_<timestamp>.log\n'
    printf '    JSON Log:   /tmp/purpleteam_<timestamp>.json\n'
    printf '\n'
    printf '%b%s%b\n' "$C_YELLOW" "  FOR AUTHORIZED PURPLE TEAM EXERCISES ONLY" "$C_RESET"
    printf '\n'
}

list_phases() {
    printf '%b' "$C_CYAN"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════╗
║                        AVAILABLE PHASES                                  ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
    printf '%b\n' "$C_RESET"

    local phases=(
        "1|System & Environment Profiling|T1082, T1497.001, T1614, T1614.001|Fingerprint OS, hardware, VM detection, security stack, locale|~20s"
        "2|Account & Privilege Discovery|T1087, T1069, T1201, T1033|Local/domain users, groups, password policy, admin enum|~25s"
        "3|Process & Service Intelligence|T1057, T1007, T1518.001, T1497.001|Running processes, security tools, financial apps, analysis tools|~20s"
        "4|Sensitive File Discovery|T1083, T1005, T1552.001, T1552.004|Documents, certs, keys, configs, password DBs, RDP files|~30s"
        "5|Credential Access Reconnaissance|T1552, T1555, T1003, T1552.006|Browser creds, Credential Manager, LSASS, SAM, cloud tokens|~35s"
        "6|Defense Evasion Reconnaissance|T1562, T1218, T1027|PS logging, Sysmon, firewall, AppLocker, AMSI, audit policy|~25s"
        "7|Network & Lateral Movement Recon|T1049, T1018, T1135, T1482, T1016|Connections, shares, routing, domain trusts, RDP history|~30s"
        "8|Collection & Staging|T1119, T1074.001, T1114.001, T1005|Stage documents, email archives, clipboard, recent files|~25s"
        "9|Persistence Mechanism Recon|T1547, T1053, T1543, T1546, T1574|Run keys, tasks, services, WMI, COM hijack, DLL search order|~25s"
        "10|Impact Simulation (No Harm)|T1486, T1490, T1489, T1529|Shadow copies, backups, DB services, target enumeration|~30s"
    )

    for entry in "${phases[@]}"; do
        IFS='|' read -r num title techniques desc duration <<< "$entry"
        local color="$C_GREEN"
        [ "$num" = "10" ] && color="$C_MAGENTA"
        printf '  %b[%2s]%b  %b%s%b\n' "$C_WHITE" "$num" "$C_RESET" "$color" "$title" "$C_RESET"
        printf '       MITRE ATT&CK: %s\n' "$techniques"
        printf '       %s\n' "$desc"
        printf '       Duration: %s\n\n' "$duration"
    done

    printf '  %bTotal estimated time for all phases: ~5-6 minutes%b\n\n' "$C_GRAY" "$C_RESET"
}

# ============================================================================
# BANNER
# ============================================================================

show_banner() {
    clear
    printf '%b' "$C_CYAN"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                                                                   ║
    ║   ██████╗ ██╗   ██╗██████╗ ██████╗ ██╗     ███████╗              ║
    ║   ██╔══██╗██║   ██║██╔══██╗██╔══██╗██║     ██╔════╝              ║
    ║   ██████╔╝██║   ██║██████╔╝██████╔╝██║     █████╗                ║
    ║   ██╔═══╝ ██║   ██║██╔══██╗██╔═══╝ ██║     ██╔══╝                ║
    ║   ██║     ╚██████╔╝██║  ██║██║     ███████╗███████╗              ║
    ║   ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝              ║
    ║                                                                   ║
    ║   ████████╗███████╗ █████╗ ███╗   ███╗                           ║
    ║   ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║                           ║
    ║      ██║   █████╗  ███████║██╔████╔██║                           ║
    ║      ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║                           ║
    ║      ██║   ███████╗██║  ██║██║ ╚═╝ ██║                           ║
    ║      ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝                           ║
    ║                                                                   ║
    ║            Advanced Adversary Simulation Framework                ║
    ║                    WSL → Windows Host                            ║
    ║             Financial / Government Sector TTPs                   ║
    ║                                                                   ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    printf '%b' "$C_RESET"
    printf '    %bVersion:%b  %b%s%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$SCRIPT_VERSION" "$C_RESET"
    printf '    %bTarget:%b   %bWindows Host via WSL%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '    %bFocus:%b    %bFinancial & Government Sector APT TTPs%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '    %bPurpose:%b  %bAuthorized Purple Team Exercise%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '\n'
    printf '    %b⚠  FOR AUTHORIZED SECURITY TESTING ONLY  ⚠%b\n\n' "$C_YELLOW" "$C_RESET"

    init_logs
}

# ============================================================================
# SUMMARY
# ============================================================================

generate_summary() {
    local end_time duration minutes seconds
    end_time=$(date +%s)
    duration=$((end_time - START_TIME))
    minutes=$((duration / 60))
    seconds=$((duration % 60))

    printf '\n'
    printf '%b╔═══════════════════════════════════════════════════════════════════════╗%b\n' "$C_CYAN" "$C_RESET"
    printf '%b║%b                       %bEXECUTION SUMMARY%b                              %b║%b\n' "$C_CYAN" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '%b╚═══════════════════════════════════════════════════════════════════════╝%b\n' "$C_CYAN" "$C_RESET"
    printf '\n'
    printf '  %-20s %dm %ds\n' "Duration:" "$minutes" "$seconds"
    printf '  %-20s %d\n' "Total Actions:" "$TOTAL_ACTIONS"
    printf '  %b%-20s%b %d\n' "$C_GREEN" "Successful:" "$C_RESET" "$SUCCESSFUL_ACTIONS"
    printf '  %b%-20s%b %d\n' "$C_RED" "Failed:" "$C_RESET" "$FAILED_ACTIONS"
    printf '  %b%-20s%b %d\n' "$C_YELLOW" "Skipped:" "$C_RESET" "$SKIPPED_ACTIONS"

    if [ $TOTAL_ACTIONS -gt 0 ]; then
        local success_rate
        success_rate=$(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_ACTIONS/$TOTAL_ACTIONS)*100}")
        printf '  %-20s %s%%\n' "Success Rate:" "$success_rate"
    fi

    printf '\n'
    printf '  %b── Output Files ──%b\n' "$C_WHITE" "$C_RESET"
    printf '  Text Log:    %s\n' "$LOG_FILE"
    printf '  JSON Log:    %s\n' "$JSON_LOG"

    if [ -f "/tmp/RANSOMWARE_NOTE_PURPLETEAM.txt" ]; then
        printf '  Ransom Note: /tmp/RANSOMWARE_NOTE_PURPLETEAM.txt\n'
    fi
    if ls -d /tmp/collected_data_* &>/dev/null 2>&1; then
        printf '  Staged Data: %s\n' "$(ls -d /tmp/collected_data_* 2>/dev/null | tail -1)"
    fi

    printf '\n'
    printf '  %b── Blue Team Detection Hints ──%b\n' "$C_WHITE" "$C_RESET"
    printf '\n'
    printf '  %bStandard Indicators:%b\n' "$C_WHITE" "$C_RESET"
    printf '    • PowerShell EventID 4104 (Script Block Logging)\n'
    printf '    • Process Creation EventID 4688 (WSL → PowerShell)\n'
    printf '    • File Access EventID 4663\n'
    printf '    • Registry Access EventID 4657\n'
    printf '    • Network Connection EventID 5156\n'
    printf '    • Logon EventID 4624/4625\n'
    printf '\n'
    printf '  %bAPT / Financial Sector Indicators:%b\n' "$C_WHITE" "$C_RESET"
    printf '    • LDAP queries for adminCount=1 (admin enumeration)\n'
    printf '    • Shadow copy enumeration (pre-ransomware)\n'
    printf '    • Credential store access attempts (browser DBs)\n'
    printf '    • Lateral movement recon (RDP history, SMB shares)\n'
    printf '    • WMI subscription queries (stealthy persistence)\n'
    printf '    • Service binary path enumeration (escalation)\n'
    printf '\n'

    {
        printf '\n'
        printf '  ══════════════════════════════════════════════════════════════════\n'
        printf '  EXECUTION SUMMARY\n'
        printf '  ══════════════════════════════════════════════════════════════════\n'
        printf '\n'
        printf '  Completed:    %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf '  Duration:     %dm %ds\n' "$minutes" "$seconds"
        printf '  Actions:      %d total | %d success | %d failed | %d skipped\n' \
            "$TOTAL_ACTIONS" "$SUCCESSFUL_ACTIONS" "$FAILED_ACTIONS" "$SKIPPED_ACTIONS"
        if [ $TOTAL_ACTIONS -gt 0 ]; then
            printf '  Success Rate: %s%%\n' "$(awk "BEGIN {printf \"%.1f\", ($SUCCESSFUL_ACTIONS/$TOTAL_ACTIONS)*100}")"
        fi
        printf '\n'
        printf '  Environment:\n'
        printf '    WSL Version:   %s\n' "$WSL_VERSION"
        printf '    PowerShell:    %s\n' "$POWERSHELL_CMD"
        printf '    Windows Mount: %s\n' "$WINDOWS_SYSTEM"
        printf '    Target Host:   %s\n' "${HOSTNAME_DETECTED:-unknown}"
        printf '    Target User:   %s\n' "${USERNAME_DETECTED:-unknown}"
        printf '\n'
        printf '  Output Files:\n'
        printf '    Text Log: %s\n' "$LOG_FILE"
        printf '    JSON Log: %s\n' "$JSON_LOG"
        printf '\n'
        printf '  ══════════════════════════════════════════════════════════════════\n'
    } >> "$LOG_FILE"

    # Finalize JSON
    printf '  {"summary":{"version":"%s","duration":%d,"total":%d,"successful":%d,"failed":%d,"skipped":%d}}\n]\n' \
        "$SCRIPT_VERSION" "$duration" "$TOTAL_ACTIONS" "$SUCCESSFUL_ACTIONS" "$FAILED_ACTIONS" "$SKIPPED_ACTIONS" >> "$JSON_LOG"

    printf '%b✓ Purple Team exercise completed%b\n\n' "$C_GREEN" "$C_RESET"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local run_all=true
    local phases_to_run=()
    local quiet_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_phases
                exit 0
                ;;
            -a|--all)
                run_all=true
                shift
                ;;
            -p|--phase)
                run_all=false
                IFS=',' read -ra phases_to_run <<< "$2"
                shift 2
                ;;
            -q|--quiet)
                quiet_mode=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                printf '%b%s%b\n' "$C_RED" "Unknown option: $1" "$C_RESET"
                printf 'Use --help for usage information\n'
                exit 1
                ;;
        esac
    done

    if [ "$quiet_mode" = false ]; then
        show_banner
        sleep 1
    else
        init_logs
    fi

    detect_environment
    sleep 1

    if [ "$run_all" = true ]; then
        phase_system_discovery;       sleep 1
        phase_account_discovery;      sleep 1
        phase_process_discovery;      sleep 1
        phase_file_discovery;         sleep 1
        phase_credential_search;      sleep 1
        phase_defense_evasion_recon;  sleep 1
        phase_network_discovery;      sleep 1
        phase_automated_collection;   sleep 1
        phase_persistence_recon;      sleep 1
        phase_impact_simulation;      sleep 1
    else
        for phase in "${phases_to_run[@]}"; do
            case $phase in
                1)  phase_system_discovery ;;
                2)  phase_account_discovery ;;
                3)  phase_process_discovery ;;
                4)  phase_file_discovery ;;
                5)  phase_credential_search ;;
                6)  phase_defense_evasion_recon ;;
                7)  phase_network_discovery ;;
                8)  phase_automated_collection ;;
                9)  phase_persistence_recon ;;
                10) phase_impact_simulation ;;
                *)
                    print_error "Invalid phase number: $phase (valid range: 1-10)"
                    ;;
            esac
            sleep 1
        done
    fi

    generate_summary
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

trap 'print_error "Script interrupted by user"; generate_summary; exit 1' INT TERM

# ============================================================================
# ENTRY POINT
# ============================================================================

main "$@"
exit 0
