#!/bin/bash
#
# Kilosort Cluster Pipeline Orchestrator
# Workflow: upload (if needed) -> submit (if needed) -> monitor -> download -> cleanup
#
# Resumable: re-running this script will pick up any jobs already on the cluster.
#

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    # shellcheck source=config.sh
    source "${SCRIPT_DIR}/config.sh"
fi

CLUSTER_HOST="${CLUSTER_HOST:-front.migale.inrae.fr}"
CLUSTER_USER="${CLUSTER_USER:-ecordina}"
CLUSTER_BASE="${CLUSTER_BASE_DIR:-/home/ecordina/work/kilosort_pipeline}"
EMAIL="${EMAIL:-emmanuel.cordina@inrae.fr}"
LOCAL_DATA_DIR="${LOCAL_DATA_DIR:-./local_data}"
LOCAL_RESULTS_DIR="${LOCAL_RESULTS_DIR:-./local_results}"
MAX_CONCURRENT="${MAX_CONCURRENT_UPLOADS:-3}"
POLL_INTERVAL="${POLL_INTERVAL:-60}"
CPU_CORES="${CPU_CORES:-8}"
QUEUE_NAME="${QUEUE_NAME:-long.q,infinit.q,highmem.q,bigmem.q,maiage.q}"
THREAD_PE="${THREAD_PE:-thread}"
MAX_RETRIES="${MAX_RETRY_ATTEMPTS:-5}"

# State file: maps filename -> job_id (one entry per file, overwritten on resubmit)
STATE_FILE="${LOCAL_DATA_DIR}/.kilosort_state.tsv"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
info()    { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

ssh_cluster() { ssh -o BatchMode=yes -o ConnectTimeout=10 -n "${CLUSTER_USER}@${CLUSTER_HOST}" "$@"; }

notify() {
    local subject="$1" body="$2"
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$EMAIL" 2>/dev/null || warn "mail failed"
    fi
}

# ---------------------------------------------------------------------------
# State file helpers  (tab-separated: filename <TAB> job_id)
# ---------------------------------------------------------------------------
state_set() {
    local filename="$1" job_id="$2"
    mkdir -p "$(dirname "$STATE_FILE")"
    # Always create .tmp (touch first so mv never fails on empty grep result)
    touch "${STATE_FILE}.tmp"
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${filename}"$'\t' "$STATE_FILE" > "${STATE_FILE}.tmp" || true
    fi
    echo -e "${filename}\t${job_id}" >> "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

state_get_job_id() {
    local filename="$1"
    [[ -f "$STATE_FILE" ]] || return
    awk -F'\t' -v f="$filename" '$1==f {print $2}' "$STATE_FILE" | tail -n1
}

state_remove() {
    local filename="$1"
    [[ -f "$STATE_FILE" ]] || return
    grep -v "^${filename}"$'\t' "$STATE_FILE" > "${STATE_FILE}.tmp" || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Cluster queries  (single SSH call each — no redundant connections)
# ---------------------------------------------------------------------------

# Returns the qstat state string (qw, r, Eqw, …) or empty string if not found.
get_job_state() {
    local job_id="$1"
    ssh_cluster "
        source /etc/profile >/dev/null 2>&1
        qstat 2>/dev/null | awk -v jid='${job_id}' '\$1==jid {print \$5; found=1} END{if(!found) exit 1}'
    " 2>/dev/null | tr -d '[:space:]'
}

# Returns 0 if the job is known to qstat (queued OR running), 1 if not.
# Retries a few times to handle the brief propagation delay after qsub.
job_exists_on_cluster() {
    local job_id="$1"
    local attempts=0
    while (( attempts < 5 )); do
        if ssh_cluster "source /etc/profile >/dev/null 2>&1; qstat -j ${job_id} >/dev/null 2>&1"; then
            return 0
        fi
        (( attempts++ ))
        sleep 3
    done
    return 1
}

# Returns 0 if the COMPLETED flag exists on the cluster for this file.
results_ready_on_cluster() {
    local filename="$1"
    local basename="${filename%.brw}"
    ssh_cluster "test -f '${CLUSTER_BASE}/results/${basename}_results/COMPLETED'"
}

# Returns 0 if the input file already exists on the cluster.
file_exists_on_cluster() {
    local filename="$1"
    ssh_cluster "test -f '${CLUSTER_BASE}/data/input/${filename}'"
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
setup_cluster() {
    log "Setting up cluster directories..."
    ssh_cluster "
        mkdir -p ${CLUSTER_BASE}/{data/input,data/output,scripts,logs,results}
        echo 'Cluster dirs OK'
    " || die "Failed to set up cluster directories"

    log "Syncing scripts to cluster..."
    rsync -az --checksum \
        "${SCRIPT_DIR}/kilosort_cluster.sh" \
        "${SCRIPT_DIR}/run_kilosort.py" \
        "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE}/scripts/" \
        || die "Failed to sync scripts"

    log "Cluster ready."
}

# ---------------------------------------------------------------------------
# Upload  (skips if file already present on cluster)
# ---------------------------------------------------------------------------
upload_file() {
    local local_file="$1"
    local filename
    filename="$(basename "$local_file")"

    if file_exists_on_cluster "$filename"; then
        info "  Already on cluster, skipping upload: $filename"
        return 0
    fi

    log "  Uploading: $filename"
    rsync -az --info=progress2 "$local_file" \
        "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE}/data/input/" \
        || { error "Upload failed: $filename"; return 1; }

    log "  Upload done: $filename"
}

# ---------------------------------------------------------------------------
# Submit
# ---------------------------------------------------------------------------
submit_job() {
    local filename="$1"
    local safe_name
    safe_name="ks_$(echo "${filename%.brw}" | tr '.' '_')"

    log "  Submitting job for: $filename" >&2

    local qsub_out
    qsub_out=$(ssh_cluster "
        source /etc/profile 2>/dev/null
        cd ${CLUSTER_BASE}
        qsub \
            -v INPUT_FILE='${CLUSTER_BASE}/data/input/${filename}' \
            -N '${safe_name}' \
            -pe ${THREAD_PE} ${CPU_CORES} \
            -q ${QUEUE_NAME} \
            -M ${EMAIL} \
            -m bes \
            -j y \
            -o logs/${safe_name}.\$JOB_ID.log \
            scripts/kilosort_cluster.sh
    ") || { error "qsub SSH call failed for $filename" >&2; return 1; }

    local job_id
    job_id=$(echo "$qsub_out" | sed -n 's/.*Your job \([0-9]\+\).*/\1/p' | head -n1)

    if [[ -z "$job_id" ]]; then
        error "Could not parse job ID. qsub said: $qsub_out" >&2
        return 1
    fi

    state_set "$filename" "$job_id"
    log "  Submitted job $job_id for $filename" >&2
    notify "Kilosort submitted: $filename" "Job $job_id queued on ${CLUSTER_HOST}."
    echo "$job_id"   # only this goes to stdout
}

# ---------------------------------------------------------------------------
# Monitor  (blocks until job leaves the queue — success, error, or deletion)
# Returns 0 on clean finish, 1 on error state.
# ---------------------------------------------------------------------------
monitor_job() {
    local job_id="$1" filename="$2"
    local last_state=""

    log "  Monitoring job $job_id ($filename) — polling every ${POLL_INTERVAL}s"

    while true; do
        local state
        state=$(get_job_state "$job_id")

        # Job has left qstat — either finished or deleted
        if [[ -z "$state" ]]; then
            # Confirm it's really gone (get_job_state returns empty on SSH errors too)
            if ! job_exists_on_cluster "$job_id"; then
                log "  Job $job_id no longer in queue — checking results..."
                return 0
            fi
            # Transient SSH glitch; keep polling
            warn "  Could not reach cluster, retrying..."
            sleep 30
            continue
        fi

        if [[ "$state" != "$last_state" ]]; then
            case "$state" in
                qw)   info "  Job $job_id: QUEUED"
                      if [[ "$last_state" == "" ]]; then
                          notify "Kilosort queued: $filename" "Job $job_id is waiting in queue."
                      fi ;;
                r)    info "  Job $job_id: RUNNING"
                      notify "Kilosort started: $filename" "Job $job_id is now running." ;;
                Eqw)  error "Job $job_id entered ERROR state (Eqw)"
                      notify "Kilosort ERROR: $filename" "Job $job_id is in Eqw state. Check cluster logs."
                      return 1 ;;
                *)    info "  Job $job_id: state=$state" ;;
            esac
            last_state="$state"
        fi

        sleep "$POLL_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_results() {
    local filename="$1"
    local basename="${filename%.brw}"
    local result_dir="${basename}_results"
    local local_dest="${LOCAL_RESULTS_DIR}/${result_dir}"

    log "  Downloading results: $result_dir"
    mkdir -p "$local_dest"

    rsync -az --info=progress2 \
        "${CLUSTER_USER}@${CLUSTER_HOST}:${CLUSTER_BASE}/results/${result_dir}/" \
        "${local_dest}/" \
        || { error "Download failed: $result_dir"; return 1; }

    log "  Download complete: $result_dir -> $local_dest"
    notify "Kilosort done: $filename" "Results downloaded to ${local_dest}."
}

# ---------------------------------------------------------------------------
# Cleanup  (scoped to this file only — safe for concurrent runs)
# ---------------------------------------------------------------------------
cleanup_cluster() {
    local filename="$1"
    local basename="${filename%.brw}"

    log "  Cleaning cluster files for: $filename"
    ssh_cluster "
        rm -f  '${CLUSTER_BASE}/data/input/${filename}'
        rm -rf '${CLUSTER_BASE}/data/output/${basename}'
        echo 'Cleanup done: ${filename}'
    " && state_remove "$filename"
}

# ---------------------------------------------------------------------------
# Per-file pipeline  (runs in a subshell via &)
# ---------------------------------------------------------------------------
process_file() {
    local local_file="$1"
    local filename
    filename="$(basename "$local_file")"
    local basename="${filename%.brw}"
    local result_dir="${basename}_results"

    log "====== $filename ======"

    # 1. ALWAYS check for a live cluster job first — this wins over all local state.
    #    A job can be alive while local result dirs exist (partial/old runs).
    local job_id
    job_id=$(state_get_job_id "$filename")

    if [[ -n "$job_id" ]]; then
        if job_exists_on_cluster "$job_id"; then
            info "  Live job $job_id found on cluster — resuming monitoring"
            # Jump straight to monitoring; skip all local/cluster-result checks
            if ! monitor_job "$job_id" "$filename"; then
                error "Job $job_id failed for $filename"
                return 1
            fi
            # Fall through to download after monitor exits
            local attempt=0
            while (( attempt < MAX_RETRIES )); do
                if results_ready_on_cluster "$filename"; then
                    download_results "$filename" && cleanup_cluster "$filename" && return 0
                fi
                (( attempt++ ))
                warn "  Results not ready yet (attempt $attempt/$MAX_RETRIES), waiting 30s..."
                sleep 30
            done
            error "Results never appeared for $filename after $MAX_RETRIES attempts"
            return 1
        else
            info "  Saved job $job_id is no longer on cluster"
            job_id=""
        fi
    fi

    # 2. No live job — check if results are ready on cluster (job finished before we polled)
    if results_ready_on_cluster "$filename"; then
        log "  Results ready on cluster, downloading..."
        download_results "$filename" && cleanup_cluster "$filename"
        return $?
    fi

    # 3. Results already complete locally — truly done, nothing to do
    if [[ -f "${LOCAL_RESULTS_DIR}/${result_dir}/COMPLETED" ]]; then
        log "  Already complete locally, skipping: $filename"
        return 0
    fi

    # 4. Nothing anywhere — upload + submit + monitor + download
    upload_file "$local_file" || return 1
    job_id=$(submit_job "$filename") || return 1

    if ! monitor_job "$job_id" "$filename"; then
        error "Job $job_id failed for $filename"
        return 1
    fi

    local attempt=0
    while (( attempt < MAX_RETRIES )); do
        if results_ready_on_cluster "$filename"; then
            download_results "$filename" && cleanup_cluster "$filename" && return 0
        fi
        (( attempt++ ))
        warn "  Results not ready yet (attempt $attempt/$MAX_RETRIES), waiting 30s..."
        sleep 30
    done

    error "Results never appeared for $filename after $MAX_RETRIES attempts"
    return 1
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "========== Kilosort Pipeline Starting =========="
    mkdir -p "$LOCAL_DATA_DIR" "$LOCAL_RESULTS_DIR"

    setup_cluster

    # Collect .brw files
    mapfile -t brw_files < <(find "$LOCAL_DATA_DIR" -maxdepth 1 -name "*.brw" -type f | sort)

    if (( ${#brw_files[@]} == 0 )); then
        die "No .brw files found in $LOCAL_DATA_DIR"
    fi

    log "Found ${#brw_files[@]} .brw file(s)"
    notify "Kilosort pipeline started" "Processing ${#brw_files[@]} files from ${LOCAL_DATA_DIR}."

    # Concurrency control using a simple slot semaphore
    local running=0
    declare -a pids=()

    for brw_file in "${brw_files[@]}"; do
        process_file "$brw_file" &
        pids+=($!)
        (( running++ ))

        if (( running >= MAX_CONCURRENT )); then
            wait -n       # wait for any one child to finish
            (( running-- ))
        fi
    done

    # Wait for all remaining children and collect exit codes
    local total=${#brw_files[@]} ok=0 fail=0
    for pid in "${pids[@]}"; do
        if wait "$pid"; then (( ok++ )); else (( fail++ )); fi
    done

    log "=========================================="
    log "Pipeline finished."
    log "  Total : $total"
    log "  OK    : $ok"
    log "  Failed: $fail"
    log "=========================================="

    notify "Kilosort pipeline finished" \
        "Total: $total | OK: $ok | Failed: $fail — Results in: $LOCAL_RESULTS_DIR"

    (( fail == 0 ))   # exit 0 only if everything succeeded
}

# Graceful shutdown on Ctrl-C / TERM
_shutdown() {
    warn "Interrupted — waiting for active subshells to exit..."
    kill 0          # send SIGTERM to the entire process group
    wait
    exit 130
}
trap _shutdown INT TERM

main "$@"