#!/usr/bin/env bash
set -euo pipefail
#
# guardrails.sh — Apply forensic / failure-mitigation guardrails to a Debian
# system. Idempotent: safe to run repeatedly. Designed for new installs too.
# Run as root (no internal sudo). Self-tests every applied change.
#
# Why this exists:
#   After a 2026-05-12 progressive ext4 metadata corruption incident on
#   encrypted LVM where we lost all kernel-side diagnostic state (system
#   spent 4 hours in remount-ro zombie mode before becoming unbootable),
#   these guardrails ensure the *next* such incident is forensically
#   recoverable: kernel panics on FS error, journald captures the panic,
#   AIDE flags unexpected mutations to /etc /bin /lib /lib64, and
#   journal-watching service surfaces ext4/dm-crypt warnings as crit.
#
# What gets applied:
#   1. /etc/sysctl.d/99-panic-on-corruption.conf — panic on oops/OOM
#   2. /etc/systemd/system/disk-pressure-watch.service — kernel journal grep
#   3. /etc/fstab — errors=panic on every ext4 mount (XFS left alone:
#      xfs_force_shutdown is the default behaviour and is automatic)
#   4. aide — installed, initialized, dailyaidecheck.timer enabled
#   5. memtest86+ — installed and exposed via grub
#   6. /etc/docker/daemon.json — log-rotation caps (only if docker present)
#
# Exit codes:
#   0 = all steps PASS or already-applied
#   1 = at least one step FAILed; details printed to stderr

[ "$(id -u)" -eq 0 ] || { echo "must run as root (no sudo wrapper inside)" >&2; exit 1; }

# ── status counters / helpers ────────────────────────────────────────────────
PASS_COUNT=0; SKIP_COUNT=0; FAIL_COUNT=0; APPLY_COUNT=0

step()    { printf "\n=== %s ===\n" "$*"; }
pass()    { printf "  PASS    : %s\n" "$*"; PASS_COUNT=$((PASS_COUNT+1)); }
applied() { printf "  APPLIED : %s\n" "$*"; APPLY_COUNT=$((APPLY_COUNT+1)); }
skip()    { printf "  SKIP    : %s\n" "$*"; SKIP_COUNT=$((SKIP_COUNT+1)); }
fail()    { printf "  FAIL    : %s\n" "$*" >&2; FAIL_COUNT=$((FAIL_COUNT+1)); }

have_apt() { command -v apt-get >/dev/null 2>&1; }

# Compare a file's contents to a desired blob; return 0 if identical.
file_matches() {
    [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]
}

# ── 1. sysctl: kernel panic preserves forensics ──────────────────────────────
do_sysctl() {
    step "1. sysctl panic-on-corruption"
    local f=/etc/sysctl.d/99-panic-on-corruption.conf
    local want
    want="$(cat <<'EOF'
# Installed by guardrails.sh — kernel panics preserve forensic state across
# a reboot (journald is persistent), instead of letting ext4 remount-ro and
# zombie along while metadata damage spreads silently.
kernel.panic_on_oops = 1
kernel.panic = 10
vm.panic_on_oom = 1
EOF
)"
    if file_matches "$f" "$want"; then
        pass "$f already up to date"
    else
        printf '%s\n' "$want" > "$f"
        applied "wrote $f"
    fi
    sysctl --system >/dev/null 2>&1 || { fail "sysctl --system reload failed"; return; }
    # verify each value took effect
    local kv k v actual
    for kv in "kernel.panic_on_oops=1" "kernel.panic=10" "vm.panic_on_oom=1"; do
        k="${kv%=*}"; v="${kv#*=}"
        actual="$(sysctl -n "$k" 2>/dev/null || echo MISSING)"
        if [ "$actual" = "$v" ]; then
            pass "$k = $v (verified live)"
        else
            fail "$k = $actual (expected $v)"
        fi
    done
}

# ── 2. journal watcher: alert on first ext4/dm-crypt warning ─────────────────
do_fs_watcher() {
    step "2. disk-pressure-watch service"
    local f=/etc/systemd/system/disk-pressure-watch.service
    local want
    want="$(cat <<'EOF'
[Unit]
Description=Promote ext4/dm-crypt/xfs kernel warnings to user.crit
After=systemd-journald.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'journalctl -kf -g "EXT4-fs|dm-crypt|aborting|Buffer I/O error|XFS.*error" --since now | while IFS= read -r line; do logger -p user.crit "FS-WATCH: $line"; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
)"
    local changed=0
    if file_matches "$f" "$want"; then
        pass "$f already up to date"
    else
        printf '%s\n' "$want" > "$f"
        systemctl daemon-reload
        applied "wrote $f"
        changed=1
    fi
    if systemctl is-enabled --quiet disk-pressure-watch.service 2>/dev/null && [ "$changed" -eq 0 ]; then
        pass "service already enabled"
    else
        systemctl enable --quiet disk-pressure-watch.service \
            && pass "service enabled" \
            || fail "could not enable service"
    fi
    if [ "$changed" -eq 1 ]; then
        systemctl restart disk-pressure-watch.service \
            && pass "service restarted" \
            || fail "could not restart service"
    elif ! systemctl is-active --quiet disk-pressure-watch.service; then
        systemctl start disk-pressure-watch.service \
            && pass "service started" \
            || fail "could not start service"
    fi
    if systemctl is-active --quiet disk-pressure-watch.service; then
        pass "service is active (verified)"
    else
        fail "service is not active after enable/start"
    fi
}

# ── 3. fstab: errors=panic on every ext4 mount ───────────────────────────────
do_fstab() {
    step "3. fstab errors=panic on ext4 mounts"
    local fstab=/etc/fstab
    local bak="${fstab}.guardrails.bak"
    local tmp; tmp="$(mktemp)"

    # one-shot backup
    if [ ! -f "$bak" ]; then
        cp -a "$fstab" "$bak"
        applied "backup: $bak"
    fi

    # rewrite — only ext4 lines that don't already have errors=panic
    awk '
        BEGIN { OFS = "\t" }
        /^[[:space:]]*#/ { print; next }
        NF < 4           { print; next }
        {
            fstype = $3
            opts   = $4
            if (fstype == "ext4" && opts !~ /(^|,)errors=panic(,|$)/) {
                # strip any existing errors=* token
                gsub(/(^|,)errors=[^,]+/, "", opts)
                # collapse empty / leading / trailing commas
                gsub(/,,+/, ",", opts)
                sub(/^,/, "", opts); sub(/,$/, "", opts)
                if (opts == "") opts = "defaults"
                opts = opts ",errors=panic"
                $4 = opts
            }
            print
        }
    ' "$fstab" > "$tmp"

    if cmp -s "$fstab" "$tmp"; then
        pass "fstab already has errors=panic on every ext4 line"
        rm -f "$tmp"
    else
        mv "$tmp" "$fstab"
        applied "fstab rewritten (diff vs $bak below)"
        diff -u "$bak" "$fstab" | sed 's/^/        /'
    fi

    # verify: every ext4 line must have errors=panic
    local missing=0 line src mp fs opts rest
    while read -r src mp fs opts rest; do
        [ "$fs" = "ext4" ] || continue
        case ",$opts," in
            *,errors=panic,*) : ;;
            *) fail "$mp ($fs) lacks errors=panic"; missing=$((missing+1)) ;;
        esac
    done < <(grep -vE '^\s*(#|$)' "$fstab")
    [ "$missing" -eq 0 ] && pass "all ext4 lines have errors=panic (verified static)"

    # NOTE: running mounts keep their old options until remount/reboot
    local live_root_opts; live_root_opts="$(findmnt -no OPTIONS /)"
    case ",$live_root_opts," in
        *,errors=panic,*) pass "running / mount also has errors=panic (live)" ;;
        *) printf "  PENDING : reboot or 'mount -o remount,errors=panic /' to apply live\n" ;;
    esac
}

# ── 4. AIDE file integrity baseline + nightly check ──────────────────────────
do_aide() {
    step "4. AIDE file integrity"
    if ! have_apt; then
        skip "no apt-get; install AIDE manually for your distro"
        return
    fi
    if ! command -v aide >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aide aide-common >/dev/null 2>&1 \
            && applied "aide + aide-common installed" \
            || { fail "apt-get install aide failed"; return; }
    else
        pass "aide already installed"
    fi
    # Local AIDE tuning: excludes + checksum scope + multi-threaded hashing.
    # Must be written BEFORE aideinit so the initial DB matches.
    local exclude_f=/etc/aide/aide.conf.d/99_aide_local_excludes
    local exclude_want
    # Detect CPU count for parallel hashing; fall back to 4 if nproc is missing.
    local nworkers; nworkers="$(nproc 2>/dev/null || echo 4)"
    exclude_want="$(cat <<EOF
# Installed by guardrails.sh — runtime tuning + path excludes for AIDE.
# (The 'Checksums' macro override is NOT here — it must be edited inline in
#  /etc/aide/aide.conf because rule attributes resolve at parse time, before
#  any conf.d/* file is loaded. See do_aide() in guardrails.sh.)
#
# num_workers: parallel hashing across CPU cores. Hashing is the dominant
# cost on encrypted LVM; on this host nproc=${nworkers} this is roughly
# ${nworkers}x speedup. Safe to set in conf.d because it's a runtime option,
# not a rule attribute.
#
# Excludes (high-churn / low-security-value trees):
#   /usr/share/{fonts,locale,doc,man,icons,help,zoneinfo,common-licenses}:
#     static data, replaced atomically by apt, no executables, no privilege
#     paths. Monitoring them only produces apt-upgrade noise.
#   /var: high-churn (logs, caches, container layers, VM images, dpkg state).
#     Trade-off: loses signal on /var/lib/dpkg/status and /var/spool/cron
#     tampering. Operator-accepted: not in this threat model.
#   /home: user data; tampering here is below privilege boundary and changes
#     constantly. Operator-accepted as noise.
#   /media, /mnt: transient mount points (USB sticks, network shares, backup
#     drives). The 99_aide_root catch-all '/  0 Full' descends into these
#     and AIDE will hash whatever's mounted there — easily multi-GB or TB
#     of unrelated data. Excluded unconditionally so plugging in a USB
#     drive doesn't poison the next aide --check run.

num_workers = ${nworkers}

!/usr/share/fonts(/.*)?$
!/usr/share/locale(/.*)?$
!/usr/share/doc(/.*)?$
!/usr/share/man(/.*)?$
!/usr/share/icons(/.*)?$
!/usr/share/help(/.*)?$
!/usr/share/zoneinfo(/.*)?$
!/usr/share/common-licenses(/.*)?$
!/var(/.*)?$
!/home(/.*)?$
!/media(/.*)?$
!/mnt(/.*)?$
EOF
)"
    if file_matches "$exclude_f" "$exclude_want"; then
        pass "$exclude_f already up to date"
    else
        printf '%s\n' "$exclude_want" > "$exclude_f"
        applied "wrote $exclude_f"
        # If an old DB exists, it was built without these excludes and the
        # next aide --check will report the now-unmonitored paths as
        # missing. Flag for the operator (don't auto-delete — destructive).
        if [ -s /var/lib/aide/aide.db ]; then
            printf "  ACTION  : existing AIDE DB pre-dates excludes; to apply, run:\n"
            printf "                rm /var/lib/aide/aide.db && %s\n" "$0"
        fi
    fi

    # Checksums override must be edited in /etc/aide/aide.conf directly:
    # rule attributes are resolved at config-parse time (before conf.d/*
    # loads), so a conf.d-side override of 'Checksums' has no effect.
    # Debian default 'H' resolves to 7 hash algorithms per file. sha256+
    # sha512 is sufficient for tamper detection at ~5x less CPU per file.
    local aide_conf=/etc/aide/aide.conf
    local aide_conf_bak="${aide_conf}.guardrails.bak"
    local checksums_want="Checksums = sha256+sha512"
    if grep -qxF "$checksums_want" "$aide_conf"; then
        pass "$aide_conf already has $checksums_want"
    elif grep -qxF "Checksums = H" "$aide_conf"; then
        [ -f "$aide_conf_bak" ] || cp -a "$aide_conf" "$aide_conf_bak"
        sed -i 's|^Checksums = H$|Checksums = sha256+sha512|' "$aide_conf"
        applied "patched $aide_conf: Checksums = H -> sha256+sha512 (backup: $aide_conf_bak)"
        if [ -s /var/lib/aide/aide.db ]; then
            printf "  ACTION  : existing AIDE DB uses old (7-hash) checksums; to apply, run:\n"
            printf "                rm /var/lib/aide/aide.db && %s\n" "$0"
        fi
    else
        skip "$aide_conf has neither 'Checksums = H' nor the override — manual review needed"
    fi
    # Verify final state via aide -D
    if aide -D --config="$aide_conf" >/dev/null 2>&1; then
        pass "aide -D config-check passes"
    else
        fail "aide -D config-check failed; run manually: aide -D --config=$aide_conf"
    fi

    if [ ! -s /var/lib/aide/aide.db ]; then
        # Background aideinit and poll the worker's /proc/<pid>/io for live
        # progress. ETAs are derived from a baseline-bytes file written at
        # the END of the previous successful run — so the first run shows
        # "no baseline" (just live throughput) and subsequent runs show
        # a real %-complete + ETA.
        local baseline=/var/lib/aide/.guardrails-baseline-rchar
        local total_est=""
        [ -s "$baseline" ] && total_est="$(cat "$baseline" 2>/dev/null)"

        local aide_log=/tmp/guardrails-aideinit.$$.log
        # The Debian aideinit wrapper has -y / -f flags on some versions and
        # not others; fall back through the variants.
        ( aideinit -y -f 2>&1 || aideinit -y 2>&1 || aideinit 2>&1 ) >"$aide_log" 2>&1 &
        local wrapper_pid=$!

        # Wait up to 30s for the real worker (the aide --init process) to
        # appear under pgrep. The wrapper spawns a shell which spawns aide.
        local worker_pid="" tries
        for tries in $(seq 1 30); do
            worker_pid="$(pgrep -fx 'aide --config=/etc/aide/aide.conf --init' 2>/dev/null || true)"
            [ -n "$worker_pid" ] && break
            kill -0 "$wrapper_pid" 2>/dev/null || break
            sleep 1
        done

        if [ -z "$worker_pid" ]; then
            wait "$wrapper_pid" || { fail "aideinit failed before worker appeared; log: $aide_log"; return; }
            # Wrapper exited cleanly without us ever seeing the worker
            # (unlikely on Debian, but handle it).
            [ -f /var/lib/aide/aide.db.new ] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
            applied "AIDE database initialized (no progress polled)"
            rm -f "$aide_log"
            # baseline-bytes can't be recorded — worker is gone
        else
            local start_ts; start_ts=$(date +%s)
            printf "  INFO    : aideinit running (wrapper=%s worker=%s, polling /proc/%s/io every 15s)\n" \
                "$wrapper_pid" "$worker_pid" "$worker_pid"
            if [ -n "$total_est" ]; then
                printf "  INFO    : baseline from previous run: %.2f GB\n" \
                    "$(awk -v t=$total_est 'BEGIN{print t/1073741824}')"
            else
                printf "  INFO    : no prior baseline — first-run estimates will be throughput-only\n"
            fi

            local last_rchar=0
            while kill -0 "$wrapper_pid" 2>/dev/null; do
                sleep 15
                # Re-resolve worker PID in case aide forked (shouldn't, but defensive)
                [ -r "/proc/$worker_pid/io" ] || \
                    worker_pid="$(pgrep -fx 'aide --config=/etc/aide/aide.conf --init' 2>/dev/null || true)"
                [ -n "$worker_pid" ] && [ -r "/proc/$worker_pid/io" ] || continue

                local rchar; rchar="$(awk '/^rchar/ {print $2}' "/proc/$worker_pid/io" 2>/dev/null)"
                [ -n "$rchar" ] || continue
                local now elapsed rchar_gb rate
                now=$(date +%s)
                elapsed=$((now - start_ts))
                rchar_gb="$(awk -v r=$rchar 'BEGIN{printf "%.2f", r/1073741824}')"
                rate="$(awk -v r=$rchar -v t=$elapsed 'BEGIN{if(t>0) printf "%.1f", r/t/1048576; else print "?"}')"

                if [ -n "$total_est" ] && [ "$rchar" -gt 0 ]; then
                    local pct eta
                    pct="$(awk -v r=$rchar -v t=$total_est 'BEGIN{p=r*100/t; if(p>100)p=100; printf "%.0f", p}')"
                    eta="$(awk -v r=$rchar -v t=$total_est -v e=$elapsed 'BEGIN{
                        if(r>=t){print "finalizing"}
                        else if(r>0){s=(t-r)/(r/e); printf "%dm%02ds", s/60, s%60}
                        else{print "?"}
                    }')"
                    printf "  PROGRESS: t=%dm%02ds  read=%s GB  rate=%s MB/s  ~%s%% (ETA %s)\n" \
                        $((elapsed/60)) $((elapsed%60)) "$rchar_gb" "$rate" "$pct" "$eta"
                else
                    printf "  PROGRESS: t=%dm%02ds  read=%s GB  rate=%s MB/s  (no baseline — first run)\n" \
                        $((elapsed/60)) $((elapsed%60)) "$rchar_gb" "$rate"
                fi
                last_rchar=$rchar
            done

            # Reap wrapper exit status
            if wait "$wrapper_pid"; then
                [ -f /var/lib/aide/aide.db.new ] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
                # Persist baseline for next run's ETA (best-effort: /proc may
                # already be gone; fall back to last_rchar captured in loop).
                local final_rchar=""
                [ -r "/proc/$worker_pid/io" ] && \
                    final_rchar="$(awk '/^rchar/ {print $2}' "/proc/$worker_pid/io" 2>/dev/null || true)"
                [ -z "$final_rchar" ] && final_rchar="$last_rchar"
                if [ -n "$final_rchar" ] && [ "$final_rchar" -gt 0 ]; then
                    echo "$final_rchar" > "$baseline"
                    printf "  INFO    : baseline saved (%s, %.2f GB) for next run's ETA\n" \
                        "$baseline" "$(awk -v r=$final_rchar 'BEGIN{print r/1073741824}')"
                fi
                applied "AIDE database initialized"
                rm -f "$aide_log"
            else
                fail "aideinit failed; log preserved at $aide_log"
                return
            fi
        fi
    else
        pass "AIDE database already initialized"
    fi
    # The Debian package ships dailyaidecheck.timer; older variants ship a
    # cron.daily script instead. Handle both.
    if systemctl list-unit-files dailyaidecheck.timer >/dev/null 2>&1 \
            && systemctl list-unit-files dailyaidecheck.timer | grep -q dailyaidecheck; then
        systemctl enable --quiet --now dailyaidecheck.timer \
            && pass "dailyaidecheck.timer enabled and started" \
            || fail "could not enable dailyaidecheck.timer"
    elif [ -x /etc/cron.daily/aide ]; then
        pass "/etc/cron.daily/aide present (cron-based variant)"
    else
        skip "neither timer nor cron.daily/aide present — manual scheduling required"
    fi
}

# ── 5. memtest86+ exposed in grub ────────────────────────────────────────────
do_memtest() {
    step "5. memtest86+ available from grub"
    if ! have_apt; then
        skip "no apt-get; install memtest86+ manually"
        return
    fi
    if ! dpkg-query -W -f='${Status}' memtest86+ 2>/dev/null | grep -q "install ok installed"; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq memtest86+ >/dev/null 2>&1 \
            && applied "memtest86+ installed" \
            || { fail "apt-get install memtest86+ failed"; return; }
    else
        pass "memtest86+ already installed"
    fi
    if [ ! -f /boot/grub/grub.cfg ]; then
        skip "/boot/grub/grub.cfg not present (non-grub boot?) — skipping update-grub"
        return
    fi
    if grep -q -i memtest /boot/grub/grub.cfg; then
        pass "memtest entry present in /boot/grub/grub.cfg"
    else
        update-grub >/dev/null 2>&1 \
            && { grep -q -i memtest /boot/grub/grub.cfg \
                    && applied "update-grub: memtest entry added" \
                    || fail "update-grub ran but no memtest entry appeared"; } \
            || fail "update-grub failed"
    fi
}

# ── 6. Docker log-rotate caps (only if docker is present) ────────────────────
do_docker() {
    step "6. docker log-rotation caps"
    if ! command -v docker >/dev/null 2>&1; then
        skip "docker not installed"
        return
    fi
    mkdir -p /etc/docker
    local f=/etc/docker/daemon.json
    local want
    want="$(cat <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF
)"
    if file_matches "$f" "$want"; then
        pass "$f already up to date"
        return
    fi
    if [ ! -f "$f" ]; then
        printf '%s\n' "$want" > "$f"
        applied "wrote $f"
        systemctl restart docker >/dev/null 2>&1 \
            && pass "docker restarted to pick up new daemon.json" \
            || fail "docker restart failed"
        return
    fi
    # daemon.json exists but doesn't match exactly. Try jq-based merge so we
    # don't clobber other user settings. If jq isn't available, leave it and
    # tell the user.
    if ! command -v jq >/dev/null 2>&1; then
        skip "$f already has custom content; install 'jq' for safe merge, or manually add:"
        printf "%s\n" "$want" | sed 's/^/            /'
        return
    fi
    local merged tmp
    tmp="$(mktemp)"
    merged="$(jq -s '.[0] * .[1]' "$f" <(printf '%s' "$want"))" || {
        fail "jq merge failed; $f left unchanged"
        rm -f "$tmp"
        return
    }
    printf '%s\n' "$merged" > "$tmp"
    if cmp -s "$f" "$tmp"; then
        pass "$f already contains the required log-driver settings (merged-equal)"
        rm -f "$tmp"
    else
        cp -a "$f" "${f}.guardrails.bak"
        mv "$tmp" "$f"
        applied "merged log-driver settings into $f (backup: ${f}.guardrails.bak)"
        systemctl restart docker >/dev/null 2>&1 \
            && pass "docker restarted to pick up new daemon.json" \
            || fail "docker restart failed"
    fi
}

# ── main ─────────────────────────────────────────────────────────────────────
do_sysctl
do_fs_watcher
do_fstab
do_aide
do_memtest
do_docker

printf "\n"
printf "%s\n" "════════════════════════════════════════════════════════════════════════"
printf "Summary: %d PASS  /  %d APPLIED  /  %d SKIP  /  %d FAIL\n" \
    "$PASS_COUNT" "$APPLY_COUNT" "$SKIP_COUNT" "$FAIL_COUNT"
printf "%s\n" "════════════════════════════════════════════════════════════════════════"
printf "\n"
printf "Manual follow-up (intentionally not scripted):\n"
printf "  - Reboot at your convenience so errors=panic takes effect on the running mounts.\n"
printf "    (Or 'mount -o remount,errors=panic /' for the root mount only, no reboot.)\n"
printf "  - Reboot into 'Memory test (memtest86+)' from grub once and let it run\n"
printf "    overnight (3+ full passes). This retires the non-ECC RAM hypothesis.\n"
printf "  - Check the next AIDE report:\n"
printf "      journalctl -u dailyaidecheck.service --since '24 hours ago'\n"
printf "    or your root mailbox (if you have a local MTA).\n"
printf "  - Watch for FS-WATCH lines:\n"
printf "      journalctl -p crit -f | grep FS-WATCH\n"
printf "\n"

[ "$FAIL_COUNT" -eq 0 ]
