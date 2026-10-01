#!/bin/bash

# ./utils/msi/thermal-check.sh [idle_sec=60] [load_sec=180] [cool_sec=60] [burst_sec=40] [four_sec=60]
#                              [cold_temp=65] [cold_max=180]
#
# Full thermal check of the laptop:
#   system info -> idle -> burst (cold start, 0.5 s step) -> 4 P-cores -> full CPU load -> cooldown.
# Writes ~/thermal-report-<stamp>/report.txt (+ raw logs) and a .tar.gz to hand to service.
# Does not change any fan / shift / power settings: it measures the mode that is set now.
# Before the burst / 4-core / full-load phases it waits until the package is <= cold_temp °C,
# or stops cooling down (< 1 °C drop in 30 s), or cold_max s pass, so that every phase starts
# from a comparable state; the live progress line goes to the terminal only, not to report.txt.
# A phase length of 0 skips that phase. Expect ~10-15 min with the defaults.

set -u

IDLE_SECS=${1:-60}
LOAD_SECS=${2:-180}
COOL_SECS=${3:-60}
BURST_SECS=${4:-40}
FOUR_SECS=${5:-60}
COLD_TEMP=${6:-65}   # start burst / 4-core / full-load phases when Package <= this, °C
COLD_MAX=${7:-180}   # ...but never wait longer than this, s
INTERVAL=2
BURST_INTERVAL=0.5

# Intel Core i7-12700H (ARK, intel.com product 132228): Processor Base Power 45 W,
# Maximum Turbo Power 115 W, Minimum Assured Power 35 W, P-core max turbo 4.70 GHz,
# E-core max turbo 3.50 GHz, TJunction 100 °C. Used only for the comparison section.

for v in "$IDLE_SECS" "$LOAD_SECS" "$COOL_SECS" "$BURST_SECS" "$FOUR_SECS" "$COLD_TEMP" "$COLD_MAX"; do
  [[ $v =~ ^[0-9]+$ ]] || { echo "Usage: $0 [idle_sec] [load_sec] [cool_sec] [burst_sec] [four_sec] [cold_temp] [cold_max]"; exit 1; }
done

if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

if ! command -v turbostat >/dev/null; then
  echo "Нет turbostat: sudo apt install linux-tools-common linux-tools-$(uname -r)"
  exit 1
fi
if ! command -v sensors >/dev/null; then
  echo "Нет sensors: sudo apt install lm-sensors"
  exit 1
fi
modprobe msr 2>/dev/null

# The /usr/bin/turbostat wrapper on Ubuntu refuses to run on a kernel that has no matching
# linux-tools package (e.g. XanMod). Probe every candidate with a real 1-iteration run.
TURBOSTAT=
for cand in "$(command -v turbostat)" $(ls -1 /usr/lib/linux-tools/*/turbostat 2>/dev/null | sort -rV); do
  [ -x "$cand" ] || continue
  if "$cand" --quiet --interval 1 --num_iterations 1 --show Core,PkgTmp --out /dev/null >/dev/null 2>&1; then
    TURBOSTAT=$cand
    break
  fi
done
if [ -z "$TURBOSTAT" ]; then
  echo "turbostat не запускается на ядре $(uname -r). Ошибка:"
  turbostat --quiet --interval 1 --num_iterations 1 --show Core,PkgTmp 2>&1 | head -5
  echo "Подсказка: sudo apt install linux-tools-generic (ищется /usr/lib/linux-tools/*/turbostat)"
  exit 1
fi
# sub-second sampling for the burst phase; fall back to 1 s if this turbostat rejects it
"$TURBOSTAT" --quiet --interval "$BURST_INTERVAL" --num_iterations 1 --show Core,PkgTmp --out /dev/null >/dev/null 2>&1 \
  || BURST_INTERVAL=1

OWNER=${SUDO_USER:-root}
OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$OWNER_HOME/thermal-report-$STAMP"
mkdir -p "$OUT"
REPORT="$OUT/report.txt"
exec > >(tee -a "$REPORT") 2>&1

CPU_SYSFS=${CPU_SYSFS:-/sys/devices/system/cpu}

rd() { [ -r "$1" ] && cat "$1" 2>/dev/null || echo "н/д"; }
kv() { printf '%-34s %s\n' "$1" "$2"; }
section() { echo; echo "=== $* ==="; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

thr_pkg() { rd "$CPU_SYSFS/cpu0/thermal_throttle/package_throttle_count"; }
thr_core() {
  cat "$CPU_SYSFS"/cpu*/thermal_throttle/core_throttle_count 2>/dev/null \
    | awk '{ s += $1 } END { print s + 0 }'
}
fans() { sensors -u 2>/dev/null | awk '/^ *fan[0-9]+_input:/ { printf "%d ", $2 }'; }
temp_now() { sensors 2>/dev/null | awk '/^Package id 0:/ { print $4; exit }'; }
temp_c() { sensors 2>/dev/null | awk '/^Package id 0:/ { gsub(/[+°C]/, "", $4); print $4; exit }'; }

# Live progress: one line rewritten in place on the terminal (kept out of report.txt).
# Without a terminal it falls back to a plain line at most every 30 s.
PROGRESS_TTY=0
{ : > /dev/tty; } 2>/dev/null && PROGRESS_TTY=1
PROGRESS_LAST=-30
progress() {
  if [ "$PROGRESS_TTY" = 1 ]; then
    printf '\r\033[K%s' "$*" > /dev/tty
  elif [ $(( SECONDS - PROGRESS_LAST )) -ge 30 ]; then
    echo "$*"
    PROGRESS_LAST=$SECONDS
  fi
}
progress_end() { [ "$PROGRESS_TTY" = 1 ] && printf '\r\033[K' > /dev/tty; return 0; }

# P-cores are the CPUs that have an SMT sibling, E-cores have a single thread.
# Sets P_SET / E_SET (comma lists of all threads) and FOUR_CPUS (first thread of the first 4 P-cores).
detect_cpus() {
  local cpu s
  local -a p_all=() p_first=() e_all=()
  while read -r cpu; do
    s=$(<"$CPU_SYSFS/cpu$cpu/topology/thread_siblings_list")
    if [[ $s == *[,-]* ]]; then
      p_all+=("$cpu")
      [ "${s%%[,-]*}" = "$cpu" ] && p_first+=("$cpu")
    else
      e_all+=("$cpu")
    fi
  done < <(ls -d "$CPU_SYSFS"/cpu[0-9]* | sed 's|.*/cpu||' | sort -n)

  P_SET=$(IFS=,; echo "${p_all[*]:-}")
  E_SET=$(IFS=,; echo "${e_all[*]:-}")
  [ -z "$P_SET" ] && E_SET=   # no SMT/hybrid split: do not label classes
  if [ "${#p_first[@]}" -ge 4 ]; then
    FOUR_CPUS=$(IFS=,; echo "${p_first[*]:0:4}")
  else
    FOUR_CPUS=0,1,2,3
  fi
}

# ---------------------------------------------------------------- system info

sysinfo() {
  section "1. Система"
  kv "Дата" "$(date '+%F %T %Z')"
  kv "Хост" "$(hostname)"
  kv "Производитель / модель" "$(rd /sys/class/dmi/id/sys_vendor) $(rd /sys/class/dmi/id/product_name)"
  kv "Версия продукта" "$(rd /sys/class/dmi/id/product_version)"
  kv "Серийный номер" "$(rd /sys/class/dmi/id/product_serial)"
  kv "BIOS" "$(rd /sys/class/dmi/id/bios_version) ($(rd /sys/class/dmi/id/bios_date))"
  kv "CPU" "$(lscpu | awk -F: '/Model name/ { gsub(/^ +/, "", $2); print $2; exit }')"
  kv "Логических CPU" "$(nproc)"
  kv "P-ядра (все потоки)" "${P_SET:-не определено}"
  kv "E-ядра" "${E_SET:-не определено}"
  kv "ОС" "$(. /etc/os-release; echo "$PRETTY_NAME")"
  kv "Ядро" "$(uname -r)"
  kv "Аптайм" "$(uptime -p)"
  kv "Load average (1/5/15 мин)" "$(cut -d' ' -f1-3 /proc/loadavg)"
  kv "Zombie-процессов" "$(ps -eo stat | grep -c '^Z')"

  section "2. Питание и режимы"
  AC_ONLINE=0
  local ps
  for ps in /sys/class/power_supply/*; do
    case "$(rd "$ps/type")" in
      Mains) [ "$(rd "$ps/online")" = 1 ] && AC_ONLINE=1 ;;
      Battery) kv "Батарея" "$(rd "$ps/status"), $(rd "$ps/capacity")%" ;;
    esac
  done
  kv "Питание от сети (1 = да)" "$AC_ONLINE"
  command -v powerprofilesctl >/dev/null && kv "power-profiles-daemon" "$(powerprofilesctl get 2>/dev/null)"

  local ec=/sys/devices/platform/msi-ec f
  if [ -d "$ec" ]; then
    for f in fw_version fw_release_date fan_mode shift_mode cooler_boost super_battery; do
      kv "msi-ec/$f" "$(rd "$ec/$f")"
    done
  else
    kv "msi-ec" "не загружен"
  fi

  local cf=$CPU_SYSFS/cpu0/cpufreq
  kv "Governor" "$(rd $cf/scaling_governor)"
  kv "Energy perf preference" "$(rd $cf/energy_performance_preference)"
  kv "Макс. частота (cpuinfo), МГц" "$(rd $cf/cpuinfo_max_freq | awk '{ print ($1 + 0) / 1000 }')"
  kv "Лимит scaling_max_freq, МГц" "$(rd $cf/scaling_max_freq | awk '{ print ($1 + 0) / 1000 }')"
  kv "intel_pstate no_turbo" "$(rd $CPU_SYSFS/intel_pstate/no_turbo)"
  kv "intel_pstate max_perf_pct" "$(rd $CPU_SYSFS/intel_pstate/max_perf_pct)"

  local c n
  for c in /sys/class/powercap/intel-rapl:0/constraint_*_name; do
    [ -r "$c" ] || continue
    n=$(cat "$c")
    kv "RAPL лимит $n, Вт" "$(rd "${c%_name}_power_limit_uw" | awk '{ printf "%.1f", $1 / 1e6 }')"
  done

  section "3. Датчики (sensors)"
  sensors 2>&1
  if command -v nvidia-smi >/dev/null; then
    echo
    echo "GPU (nvidia-smi):"
    nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,pstate,clocks_throttle_reasons.active \
      --format=csv 2>&1
  fi

  section "4. Счётчики троттлинга с момента загрузки"
  kv "package_throttle_count (cpu0)" "$(thr_pkg)"
  kv "core_throttle_count (сумма)" "$(thr_core)"

  section "5. Самые активные процессы перед тестом"
  ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -8
}

# -------------------------------------------------------------------- phases

LOAD_PIDS=()
SAMPLER_PID=
TS_PID=
LOAD_TOOL=

# start_load seconds [ncpu] [cpulist]: stress-ng matrixprod (or sha256sum fallback), optionally pinned
start_load() {
  local secs=$1 n=${2:-$(nproc)} cpus=${3:-} i
  local -a pin=()
  [ -n "$cpus" ] && pin=(taskset -c "$cpus")

  if command -v stress-ng >/dev/null; then
    LOAD_TOOL="${pin[*]:-} stress-ng --cpu $n --cpu-method matrixprod"
    "${pin[@]}" stress-ng --cpu "$n" --cpu-method matrixprod --timeout "${secs}s" >/dev/null 2>&1 &
    LOAD_PIDS+=($!)
  else
    LOAD_TOOL="${pin[*]:-} sha256sum /dev/zero x$n (stress-ng не найден: sudo apt install stress-ng)"
    for i in $(seq "$n"); do
      "${pin[@]}" timeout "$secs" sha256sum /dev/zero >/dev/null 2>&1 &
      LOAD_PIDS+=($!)
    done
  fi
}

stop_load() {
  local p
  for p in "${LOAD_PIDS[@]:-}"; do
    [ -n "$p" ] && kill "$p" 2>/dev/null
  done
  LOAD_PIDS=()
  pkill -f 'sha256sum /dev/zero' 2>/dev/null
}

start_sampler() {
  (
    while :; do
      printf '%s %s %s\n' "$(date +%s)" "$(thr_pkg)" "$(fans)" >> "$1"
      sleep 5
    done
  ) &
  SAMPLER_PID=$!
}

stop_sampler() {
  [ -n "$SAMPLER_PID" ] && kill "$SAMPLER_PID" 2>/dev/null
  SAMPLER_PID=
}

cleanup() {
  stop_load
  stop_sampler
  [ -n "$TS_PID" ] && kill "$TS_PID" 2>/dev/null
}
trap cleanup EXIT
trap 'echo; echo "Прервано."; exit 130' INT TERM

# Wait so burst-type phases start from a comparable state. Stops when Package <= COLD_TEMP,
# or when it stops cooling (< 1 °C drop over the last 30 s), or after COLD_MAX s; says which.
wait_cold() {
  local waited=0 t old reason
  local -a hist=()
  t=$(temp_c)
  while :; do
    if [ -z "$t" ]; then reason="нет данных датчика температуры"; break; fi
    if ! gt "$t" "$COLD_TEMP"; then reason="достигнуто <= ${COLD_TEMP} °C"; break; fi
    if [ "$waited" -ge "$COLD_MAX" ]; then reason="таймаут ${COLD_MAX} с"; break; fi
    hist+=("$t")
    if [ "${#hist[@]}" -gt 6 ]; then
      old=${hist[$(( ${#hist[@]} - 7 ))]}
      if ! gt "$(awk -v a="$old" -v b="$t" 'BEGIN { print a - b }')" 1; then
        reason="температура перестала падать (< 1 °C за 30 с)"
        break
      fi
    fi
    progress "  Остывание перед фазой: Package ${t} °C, цель <= ${COLD_TEMP} °C, прошло ${waited}/${COLD_MAX} с"
    sleep 5
    waited=$(( waited + 5 ))
    t=$(temp_c)
  done
  progress_end
  echo "  Старт с Package ${t:-н/д} °C (ожидание ${waited} с: ${reason})"
}

# stats of the turbostat log: human lines to stdout, key=value to $3 with prefix $2.
# $4 = sampling interval, $5/$6 = comma lists of P / E threads (frequency of busy threads per class)
ts_stats() {
  awk -v interval="${4:-$INTERVAL}" -v pfx="$2" -v out="$3" -v pset="${5:-}" -v eset="${6:-}" '
    BEGIN {
      np = split(pset, pa, ","); for (i = 1; i <= np; i++) isP[pa[i]] = 1
      ne = split(eset, ea, ","); for (i = 1; i <= ne; i++) isE[ea[i]] = 1
    }
    $1 == "Core" { delete h; for (i = 1; i <= NF; i++) h[$i] = i; next }
    $1 == "-" && h["PkgTmp"] {
      n++
      T[n] = $(h["PkgTmp"]); W[n] = $(h["PkgWatt"])
      F[n] = $(h["Bzy_MHz"]); B[n] = $(h["Busy%"])
      next
    }
    $1 != "-" && h["CPU"] && h["Busy%"] && $(h["Busy%"]) >= 50 {
      c = $(h["CPU"]); f = $(h["Bzy_MHz"])
      if (c in isP) { pn++; ps += f; if (pn == 1 || f < pmin) pmin = f; if (f > pmax) pmax = f }
      else if (c in isE) { en++; es += f; if (en == 1 || f < emin) emin = f; if (f > emax) emax = f }
    }
    END {
      if (!n) { print "  нет данных turbostat (проверьте sudo / модуль msr)"; print pfx "n=0" > out; exit }
      t90 = -1; t95 = -1
      for (i = 1; i <= n; i++) {
        ts += T[i]; ws += W[i]; fs += F[i]; bs += B[i]
        if (i == 1 || T[i] < tmin) tmin = T[i]
        if (i == 1 || T[i] > tmax) tmax = T[i]
        if (i == 1 || W[i] < wmin) wmin = W[i]
        if (i == 1 || W[i] > wmax) wmax = W[i]
        if (i == 1 || F[i] < fmin) fmin = F[i]
        if (i == 1 || F[i] > fmax) fmax = F[i]
        if (T[i] >= 85) c85++
        if (T[i] >= 90) c90++
        if (T[i] >= 95) c95++
        if (t90 < 0 && T[i] >= 90) t90 = i * interval
        if (t95 < 0 && T[i] >= 95) t95 = i * interval
      }
      k = (n < 5) ? n : 5
      for (i = 1; i <= k; i++) {
        tf += T[i]; ff += F[i]; wf += W[i]
        tl += T[n - i + 1]; fl += F[n - i + 1]; wl += W[n - i + 1]
      }
      tf /= k; ff /= k; wf /= k; tl /= k; fl /= k; wl /= k
      printf "  Замеров: %d (шаг %.1f с)\n", n, interval
      printf "  Температура пакета, °C : мин %d / сред %.1f / макс %d\n", tmin, ts / n, tmax
      printf "  Мощность пакета, Вт    : мин %.1f / сред %.1f / макс %.1f\n", wmin, ws / n, wmax
      printf "  Частота Bzy_MHz (все)  : мин %d / сред %d / макс %d\n", fmin, fs / n, fmax
      if (pn) printf "  P-потоки при Busy>=50%% : Bzy сред %d / мин %d / макс %d МГц\n", ps / pn, pmin, pmax
      if (en) printf "  E-ядра при Busy>=50%%   : Bzy сред %d / мин %d / макс %d МГц\n", es / en, emin, emax
      printf "  Загрузка Busy%%         : сред %.1f\n", bs / n
      printf "  Замеров с T >= 85 / 90 / 95 °C: %d / %d / %d\n", c85, c90, c95
      printf "  Первые 5 замеров       : T %.1f °C, %d МГц, %.1f Вт\n", tf, ff, wf
      printf "  Последние 5 замеров    : T %.1f °C, %d МГц, %.1f Вт\n", tl, fl, wl
      if (t90 >= 0) printf "  До первых 90 °C        : %.1f с от начала\n", t90
      if (t95 >= 0) printf "  До первых 95 °C        : %.1f с от начала\n", t95
      printf "%sn=%d\n%stmin=%d\n%stavg=%.1f\n%stmax=%d\n%swavg=%.1f\n%swmax=%.1f\n", pfx, n, pfx, tmin, pfx, ts / n, pfx, tmax, pfx, ws / n, pfx, wmax > out
      printf "%sfavg=%d\n%sbavg=%.1f\n%sc85=%d\n%sc90=%d\n%sc95=%d\n", pfx, fs / n, pfx, bs / n, pfx, c85 + 0, pfx, c90 + 0, pfx, c95 + 0 >> out
      printf "%stfirst=%.1f\n%stlast=%.1f\n%sffirst=%d\n%sflast=%d\n%st90=%.1f\n%st95=%.1f\n", pfx, tf, pfx, tl, pfx, ff, pfx, fl, pfx, t90, pfx, t95 >> out
      if (pn) printf "%spfavg=%d\n%spfmin=%d\n%spfmax=%d\n", pfx, ps / pn, pfx, pmin, pfx, pmax >> out
      if (en) printf "%sefavg=%d\n%sefmin=%d\n%sefmax=%d\n", pfx, es / en, pfx, emin, pfx, emax >> out
    }' "$1"
}

# time-windowed table for the burst phase: where the package power goes in the first seconds
# from a cold start; appends key=value to $3 (ts_stats must run first, it truncates the file)
burst_stats() { # file pfx out interval
  awk -v interval="$4" -v pfx="$2" -v out="$3" '
    $1 == "Core" { delete h; for (i = 1; i <= NF; i++) h[$i] = i; next }
    $1 == "-" && h["PkgTmp"] {
      n++
      T[n] = $(h["PkgTmp"]); W[n] = $(h["PkgWatt"]); F[n] = $(h["Bzy_MHz"])
      if (W[n] > pmax) { pmax = W[n]; tpmax = n * interval }
    }
    END {
      if (!n) exit
      split("2 5 10 20 30 40 60 90", edge, " ")
      lo = 0
      printf "  Окна от старта (шаг замера %.1f с):\n", interval
      for (k = 1; k in edge; k++) {
        hi = edge[k]; c = 0; sT = sW = sF = 0; mT = mW = 0
        for (i = 1; i <= n; i++) {
          t = i * interval
          if (t > lo && t <= hi) {
            c++; sT += T[i]; sW += W[i]; sF += F[i]
            if (T[i] > mT) mT = T[i]
            if (W[i] > mW) mW = W[i]
          }
        }
        if (c) printf "   %2d-%2d с: T сред %.1f / макс %d °C, P сред %.1f / макс %.1f Вт, Bzy сред %d МГц\n", lo, hi, sT / c, mT, sW / c, mW, sF / c
        lo = hi
      }
      tend = n * interval
      for (i = 1; i <= n; i++) {
        t = i * interval
        if (t <= 5) { a5 += W[i]; c5++ }
        if (t > tend - 10) { al += W[i]; cl++ }
      }
      printf "  Первый замер: T %d °C. Пик мощности: %.1f Вт на %.1f с от начала\n", T[1], pmax, tpmax
      printf "%spmax=%.1f\n%stpmax=%.1f\n%stfirst1=%d\n%sw5=%.1f\n%swl=%.1f\n", pfx, pmax, pfx, tpmax, pfx, T[1], pfx, a5 / c5, pfx, al / cl >> out
    }' "$1"
}

phase_stats() { ts_stats "$1" "$2" "$3" "$4" "$P_SET" "$E_SET"; }
burst_phase_stats() { phase_stats "$@"; burst_stats "$@"; }

# fan stats from the sampler log: fans start at column 3
fan_stats() {
  awk '
    { for (i = 3; i <= NF; i++) { s[i] += $i; if ($i > m[i]) m[i] = $i }; n++; nf = NF }
    END {
      if (!n) { print "  нет данных о вентиляторах"; exit }
      for (i = 3; i <= nf; i++)
        printf "  fan%d: сред %d / макс %d об/мин%s\n", i - 2, s[i] / n, m[i], (m[i] == 0 ? " (не вращается или нет такого вентилятора)" : "")
    }' "$1"
}

# run_phase name PFX seconds interval [loadspec] [statsfn]
#   loadspec: "" = no load, "all" = every CPU, "cpus:0,2,4,6" = pinned to that list
run_phase() {
  local name=$1 pfx=$2 secs=$3 interval=$4 loadspec=${5:-} statsfn=${6:-phase_stats}
  local tsf="$OUT/$name.turbostat.txt" smp="$OUT/$name.samples.txt"
  local p0 c0 p1 c1 left t0 rc iters lcpus

  iters=$(awk -v s="$secs" -v i="$interval" 'BEGIN { printf "%d", s / i }')
  LOAD_TOOL=
  p0=$(thr_pkg); c0=$(thr_core)
  t0=$(date +%s)
  start_sampler "$smp"
  case $loadspec in
    all) start_load "$secs" ;;
    cpus:*)
      lcpus=${loadspec#cpus:}
      start_load "$secs" "$(awk -F, '{ print NF }' <<<"$lcpus")" "$lcpus"
      ;;
  esac
  "$TURBOSTAT" --quiet --interval "$interval" --num_iterations "$iters" \
    --show Core,CPU,Busy%,Bzy_MHz,PkgTmp,PkgWatt --out "$tsf" 2>"$OUT/$name.turbostat.err" &
  TS_PID=$!

  left=$secs
  while kill -0 "$TS_PID" 2>/dev/null; do
    sleep 1
    left=$(( left - 1 ))
    [ $(( left % 2 )) -eq 0 ] && progress "  [$name] прошло $(( secs - left ))/${secs} с, Package $(temp_now)"
  done
  progress_end
  wait "$TS_PID" 2>/dev/null
  rc=$?
  TS_PID=
  stop_load
  stop_sampler
  p1=$(thr_pkg); c1=$(thr_core)

  # a phase that ended early or without data is a failed measurement, never report it as a result
  if [ "$rc" -ne 0 ] || [ ! -s "$tsf" ] || [ $(( $(date +%s) - t0 )) -lt $(( secs - 5 )) ]; then
    echo "ОШИБКА: turbostat завершился раньше времени (код $rc) в фазе '$name'. stderr:"
    head -5 "$OUT/$name.turbostat.err"
    exit 1
  fi

  [ -n "$LOAD_TOOL" ] && echo "  Нагрузка: ${LOAD_TOOL}"
  "$statsfn" "$tsf" "${pfx}_" "$OUT/$name.stats" "$interval"
  echo "  Вентиляторы:"
  fan_stats "$smp"
  echo "  Троттлинг за фазу: package +$(( p1 - p0 )), core (сумма по CPU) +$(( c1 - c0 ))"
  echo "${pfx}_thr_pkg=$(( p1 - p0 ))" >> "$OUT/$name.stats"
  echo "${pfx}_thr_core=$(( c1 - c0 ))" >> "$OUT/$name.stats"
  # shellcheck disable=SC1090
  . "$OUT/$name.stats"
}

# phase name PFX seconds interval loadspec statsfn needs_cold(0|1)
# 0 s (or anything shorter than one sampling step) means "skip this phase", not an error.
phase() {
  local iters
  iters=$(awk -v s="$3" -v i="$4" 'BEGIN { printf "%d", s / i }')
  if [ "$iters" -lt 1 ]; then
    echo "  Пропущено (${3} с)"
    return 0
  fi
  [ "${7:-0}" = 1 ] && wait_cold
  run_phase "$1" "$2" "$3" "$4" "$5" "$6"
}

# ------------------------------------------------------- spec comparison, remarks

# facts only: Intel numbers (page fetched from intel.com) next to what was measured on this machine
spec_compare() {
  section "11. Сравнение с данными Intel (i7-12700H) и замеры"
  kv "Intel: Base / Max Turbo / Min Assured" "45 Вт / 115 Вт / 35 Вт"
  kv "Intel: макс. турбо P-ядер / E-ядер" "4700 МГц / 3500 МГц (TJunction 100 °C)"
  kv "RAPL на этой системе" "$(for c in /sys/class/powercap/intel-rapl:0/constraint_*_name; do [ -r "$c" ] && printf '%s=%s Вт ' "$(cat "$c")" "$(rd "${c%_name}_power_limit_uw" | awk '{ printf "%.0f", $1 / 1e6 }')"; done)"
  kv "Burst (старт Package ${BURST_tfirst1:-н/д} °C)" "пик ${BURST_pmax:-н/д} Вт на ${BURST_tpmax:-н/д} с; сред первые 5 с ${BURST_w5:-н/д} Вт; последние 10 с ${BURST_wl:-н/д} Вт"
  kv "4 P-ядра (CPU ${FOUR_CPUS})" "P Bzy сред ${FOUR_pfavg:-н/д} МГц (мин ${FOUR_pfmin:-н/д} / макс ${FOUR_pfmax:-н/д}); T сред ${FOUR_tavg:-н/д} / макс ${FOUR_tmax:-н/д} °C; ${FOUR_wavg:-н/д} Вт сред"
  kv "Полная нагрузка (${LOAD_SECS} с)" "${LOAD_wavg:-н/д} Вт сред; P ${LOAD_pfavg:-н/д} МГц, E ${LOAD_efavg:-н/д} МГц; T сред ${LOAD_tavg:-н/д} / макс ${LOAD_tmax:-н/д} °C"
}

remarks() {
  section "12. Автоматические замечания"
  local found=0
  note() { echo " * $*"; found=1; }

  [ "$AC_ONLINE" = 1 ] || note "Питание НЕ от сети: лимиты мощности занижены, результаты нерепрезентативны. Повторите тест от блока питания."

  if gt "${IDLE_tavg:-0}" 55; then
    note "Простой: средняя T ${IDLE_tavg} °C при Busy ${IDLE_bavg}% и ${IDLE_wavg} Вт (ориентир для простоя 40-55 °C)."
  fi
  if [ "${IDLE_c85:-0}" -gt 0 ]; then
    note "Простой: ${IDLE_c85} замеров с T >= 85 °C (макс ${IDLE_tmax} °C) при средней мощности ${IDLE_wavg} Вт, что говорит о плохой передаче тепла с кристалла."
  fi
  if [ "${LOAD_tmax:-0}" -ge 95 ]; then
    note "Нагрузка: пакет дошёл до ${LOAD_tmax} °C (критический порог около 100 °C), замеров с T >= 95 °C: ${LOAD_c95}."
  fi
  if [ "${LOAD_thr_pkg:-0}" -gt 0 ]; then
    note "Нагрузка: счётчик package_throttle_count вырос на ${LOAD_thr_pkg}, то есть троттлинг подтверждён."
  fi
  if [ "${IDLE_thr_pkg:-0}" -gt 50 ]; then
    note "Простой: package_throttle_count вырос на ${IDLE_thr_pkg} даже в простое."
  fi
  if gt "$(( ${LOAD_ffirst:-0} - ${LOAD_flast:-0} ))" 300; then
    note "Нагрузка: частота упала с ${LOAD_ffirst} до ${LOAD_flast} МГц за время теста."
  fi
  if gt "${COOL_tfirst:-0}" 0 && gt "${COOL_tlast:-0}" 65; then
    note "Остывание: через ${COOL_SECS} с после нагрузки T всё ещё ${COOL_tlast} °C (медленно)."
  fi
  [ "$found" -eq 0 ] && echo " Явных признаков перегрева в этом тесте не найдено."
}

# ---------------------------------------------------------------------- main

detect_cpus

echo "Полная проверка охлаждения. Отчёт: $OUT"
echo "Длительность: простой ${IDLE_SECS} с, burst ${BURST_SECS} с (шаг ${BURST_INTERVAL} с), 4 P-ядра ${FOUR_SECS} с, нагрузка ${LOAD_SECS} с, остывание ${COOL_SECS} с (+ ожидание остывания перед фазами)."
echo "Закройте тяжёлые программы и не трогайте ноутбук до конца теста."

sysinfo

section "6. Простой (${IDLE_SECS} с)"
echo "  Режим на момент теста: fan_mode=$(rd /sys/devices/platform/msi-ec/fan_mode), shift_mode=$(rd /sys/devices/platform/msi-ec/shift_mode), cooler_boost=$(rd /sys/devices/platform/msi-ec/cooler_boost)"
phase idle IDLE "$IDLE_SECS" "$INTERVAL" "" phase_stats 0

section "7. Burst: старт после остывания, все CPU, шаг ${BURST_INTERVAL} с (${BURST_SECS} с)"
phase burst BURST "$BURST_SECS" "$BURST_INTERVAL" all burst_phase_stats 1

section "8. 4 P-ядра: по одному потоку на ядро, CPU ${FOUR_CPUS} (${FOUR_SECS} с)"
phase four FOUR "$FOUR_SECS" "$INTERVAL" "cpus:${FOUR_CPUS}" phase_stats 1

section "9. Полная нагрузка (${LOAD_SECS} с)"
phase load LOAD "$LOAD_SECS" "$INTERVAL" all phase_stats 1

section "10. Остывание (${COOL_SECS} с)"
phase cool COOL "$COOL_SECS" "$INTERVAL" "" phase_stats 0

spec_compare
remarks

section "13. Ядерные сообщения о троттлинге/термике (dmesg)"
dmesg 2>/dev/null | grep -iE 'throttl|thermal|prochot' | tail -20
[ "${PIPESTATUS[1]}" -ne 0 ] && echo "  (ничего не найдено)"

section "Итоговые счётчики троттлинга (с момента загрузки)"
kv "package_throttle_count (cpu0)" "$(thr_pkg)"
kv "core_throttle_count (сумма)" "$(thr_core)"

echo
echo "Файлы: $OUT"
sleep 1
chown -R "$OWNER": "$OUT" 2>/dev/null
tar -C "$OWNER_HOME" -czf "$OUT.tar.gz" "$(basename "$OUT")" 2>/dev/null && chown "$OWNER:" "$OUT.tar.gz" 2>/dev/null
echo "Архив для сервиса: $OUT.tar.gz"
