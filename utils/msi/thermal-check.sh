#!/bin/bash

# ./utils/msi/thermal-check.sh [idle_sec=60] [load_sec=180] [cool_sec=60]
#
# Full thermal check of the laptop: system info -> idle -> full CPU load -> cooldown.
# Writes ~/thermal-report-<stamp>/report.txt (+ raw logs) and a .tar.gz to hand to service.
# Does not change any fan / shift / power settings: it measures the mode that is set now.

set -u

IDLE_SECS=${1:-60}
LOAD_SECS=${2:-180}
COOL_SECS=${3:-60}
INTERVAL=2

for v in "$IDLE_SECS" "$LOAD_SECS" "$COOL_SECS"; do
  [[ $v =~ ^[0-9]+$ ]] || { echo "Usage: $0 [idle_sec] [load_sec] [cool_sec]"; exit 1; }
done

if [ "$EUID" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
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

OWNER=${SUDO_USER:-root}
OWNER_HOME=$(getent passwd "$OWNER" | cut -d: -f6)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$OWNER_HOME/thermal-report-$STAMP"
mkdir -p "$OUT"
REPORT="$OUT/report.txt"
exec > >(tee -a "$REPORT") 2>&1

rd() { [ -r "$1" ] && cat "$1" 2>/dev/null || echo "н/д"; }
kv() { printf '%-34s %s\n' "$1" "$2"; }
section() { echo; echo "=== $* ==="; }
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

thr_pkg() { rd /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count; }
thr_core() {
  cat /sys/devices/system/cpu/cpu*/thermal_throttle/core_throttle_count 2>/dev/null \
    | awk '{ s += $1 } END { print s + 0 }'
}
fans() { sensors -u 2>/dev/null | awk '/^ *fan[0-9]+_input:/ { printf "%d ", $2 }'; }
temp_now() { sensors 2>/dev/null | awk '/^Package id 0:/ { print $4; exit }'; }

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

  local cf=/sys/devices/system/cpu/cpu0/cpufreq
  kv "Governor" "$(rd $cf/scaling_governor)"
  kv "Energy perf preference" "$(rd $cf/energy_performance_preference)"
  kv "Макс. частота (cpuinfo), МГц" "$(rd $cf/cpuinfo_max_freq | awk '{ print ($1 + 0) / 1000 }')"
  kv "Лимит scaling_max_freq, МГц" "$(rd $cf/scaling_max_freq | awk '{ print ($1 + 0) / 1000 }')"
  kv "intel_pstate no_turbo" "$(rd /sys/devices/system/cpu/intel_pstate/no_turbo)"
  kv "intel_pstate max_perf_pct" "$(rd /sys/devices/system/cpu/intel_pstate/max_perf_pct)"

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

start_load() {
  if command -v stress-ng >/dev/null; then
    LOAD_TOOL="stress-ng --cpu $(nproc) --cpu-method matrixprod"
    stress-ng --cpu "$(nproc)" --cpu-method matrixprod --timeout "${1}s" >/dev/null 2>&1 &
    LOAD_PIDS+=($!)
  else
    LOAD_TOOL="sha256sum /dev/zero x$(nproc) (stress-ng не найден: sudo apt install stress-ng)"
    local i
    for i in $(seq "$(nproc)"); do
      timeout "$1" sha256sum /dev/zero >/dev/null 2>&1 &
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

# stats of the turbostat log: human lines to stdout, key=value to $3 with prefix $2
ts_stats() {
  awk -v interval="$INTERVAL" -v pfx="$2" -v out="$3" '
    $1 == "Core" { delete h; for (i = 1; i <= NF; i++) h[$i] = i; next }
    $1 == "-" && h["PkgTmp"] {
      n++
      T[n] = $(h["PkgTmp"]); W[n] = $(h["PkgWatt"])
      F[n] = $(h["Bzy_MHz"]); B[n] = $(h["Busy%"])
    }
    END {
      if (!n) { print "  нет данных turbostat (проверьте sudo / модуль msr)"; print pfx "n=0" > out; exit }
      t90 = -1
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
      }
      k = (n < 5) ? n : 5
      for (i = 1; i <= k; i++) {
        tf += T[i]; ff += F[i]; wf += W[i]
        tl += T[n - i + 1]; fl += F[n - i + 1]; wl += W[n - i + 1]
      }
      tf /= k; ff /= k; wf /= k; tl /= k; fl /= k; wl /= k
      printf "  Замеров: %d (шаг %d с)\n", n, interval
      printf "  Температура пакета, °C : мин %d / сред %.1f / макс %d\n", tmin, ts / n, tmax
      printf "  Мощность пакета, Вт    : мин %.1f / сред %.1f / макс %.1f\n", wmin, ws / n, wmax
      printf "  Частота Bzy_MHz        : мин %d / сред %d / макс %d\n", fmin, fs / n, fmax
      printf "  Загрузка Busy%%         : сред %.1f\n", bs / n
      printf "  Замеров с T >= 85 / 90 / 95 °C: %d / %d / %d\n", c85, c90, c95
      printf "  Первые 5 замеров       : T %.1f °C, %d МГц, %.1f Вт\n", tf, ff, wf
      printf "  Последние 5 замеров    : T %.1f °C, %d МГц, %.1f Вт\n", tl, fl, wl
      if (t90 >= 0) printf "  До первых 90 °C        : %d с от начала\n", t90
      printf "%sn=%d\n%stmin=%d\n%stavg=%.1f\n%stmax=%d\n%swavg=%.1f\n%swmax=%.1f\n", pfx, n, pfx, tmin, pfx, ts / n, pfx, tmax, pfx, ws / n, pfx, wmax > out
      printf "%sfavg=%d\n%sbavg=%.1f\n%sc85=%d\n%sc90=%d\n%sc95=%d\n", pfx, fs / n, pfx, bs / n, pfx, c85 + 0, pfx, c90 + 0, pfx, c95 + 0 >> out
      printf "%stfirst=%.1f\n%stlast=%.1f\n%sffirst=%d\n%sflast=%d\n%st90=%d\n", pfx, tf, pfx, tl, pfx, ff, pfx, fl, pfx, t90 >> out
    }' "$1"
}

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

run_phase() { # name PFX seconds [load]
  local name=$1 pfx=$2 secs=$3 load=${4:-}
  local tsf="$OUT/$name.turbostat.txt" smp="$OUT/$name.samples.txt"
  local p0 c0 p1 c1 left

  p0=$(thr_pkg); c0=$(thr_core)
  start_sampler "$smp"
  [ -n "$load" ] && start_load "$secs"
  turbostat --quiet --interval "$INTERVAL" --num_iterations $(( secs / INTERVAL )) \
    --show Core,CPU,Busy%,Bzy_MHz,PkgTmp,PkgWatt --out "$tsf" 2>/dev/null &
  TS_PID=$!

  left=$secs
  while kill -0 "$TS_PID" 2>/dev/null; do
    sleep 1
    left=$(( left - 1 ))
    if [ $(( left % 30 )) -eq 0 ] && [ "$left" -gt 0 ]; then
      echo "  ... осталось ~${left} с, Package ${TEMP_NOW:-$(temp_now)}"
    fi
  done
  wait "$TS_PID" 2>/dev/null
  TS_PID=
  stop_load
  stop_sampler
  p1=$(thr_pkg); c1=$(thr_core)

  ts_stats "$tsf" "${pfx}_" "$OUT/$name.stats"
  echo "  Вентиляторы:"
  fan_stats "$smp"
  echo "  Троттлинг за фазу: package +$(( p1 - p0 )), core (сумма по CPU) +$(( c1 - c0 ))"
  echo "${pfx}_thr_pkg=$(( p1 - p0 ))" >> "$OUT/$name.stats"
  echo "${pfx}_thr_core=$(( c1 - c0 ))" >> "$OUT/$name.stats"
  # shellcheck disable=SC1090
  . "$OUT/$name.stats"
}

# ------------------------------------------------------------------- remarks

remarks() {
  section "9. Автоматические замечания"
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
  if [ "${LOAD_t90:--1}" -ge 0 ] && [ "${LOAD_t90:-0}" -le 20 ]; then
    note "Нагрузка: 90 °C достигнуты уже через ${LOAD_t90} с, что говорит о слабой теплоёмкости/контакте радиатора."
  fi
  if [ "${LOAD_thr_pkg:-0}" -gt 0 ]; then
    note "Нагрузка: счётчик package_throttle_count вырос на ${LOAD_thr_pkg}, то есть троттлинг подтверждён."
  fi
  if [ "${IDLE_thr_pkg:-0}" -gt 0 ]; then
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

echo "Полная проверка охлаждения. Отчёт: $OUT"
echo "Длительность: простой ${IDLE_SECS} с, нагрузка ${LOAD_SECS} с, остывание ${COOL_SECS} с."
echo "Закройте тяжёлые программы и не трогайте ноутбук до конца теста."

sysinfo

section "6. Простой (${IDLE_SECS} с)"
echo "  Режим на момент теста: fan_mode=$(rd /sys/devices/platform/msi-ec/fan_mode), shift_mode=$(rd /sys/devices/platform/msi-ec/shift_mode), cooler_boost=$(rd /sys/devices/platform/msi-ec/cooler_boost)"
run_phase idle IDLE "$IDLE_SECS"

section "7. Полная нагрузка (${LOAD_SECS} с)"
START_TEMP=$(temp_now)
LOAD_TOOL=
echo "  Температура перед нагрузкой: Package ${START_TEMP}"
run_phase load LOAD "$LOAD_SECS" load
echo "  Нагрузка: ${LOAD_TOOL}"

section "8. Остывание (${COOL_SECS} с)"
run_phase cool COOL "$COOL_SECS"

remarks

section "10. Ядерные сообщения о троттлинге/термике (dmesg)"
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
