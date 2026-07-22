#!/bin/sh
# Install AerynOS packages into a rootfs and slim it for containers.
# Called from the Dockerfile rootfs stage:
#   RUN --network=default --security=insecure build-aerynos-rootfs
set -eu

ROOTFS="${ROOTFS:-/aerynos-rootfs}"
MOSS_CACHE="${MOSS_CACHE:-/var/cache/moss}"
REPO_NAME="${REPO_NAME:-unstable}"
REPO_URL="${REPO_URL:-https://cdn.aerynos.dev/stream/unstable/x86_64/stone.index}"
# sed + grep for scripts; no gawk (we install a pure-bash command-not-found helper).
# Large transitive deps (e.g. ICU) are still pulled by moss, then removed in slim_container_rootfs.
PACKAGES="${PACKAGES:-bash moss ca-certificates uutils-coreutils curl sed grep}"
OUT_TAR="${OUT_TAR:-/rootfs.tar}"

# ---------------------------------------------------------------------------
# Reduce image size after moss install.
#
# Moss stores file contents under /.moss/assets and hardlinks them into /usr.
# Remove unwanted paths here, then delete asset blobs that no longer have
# any hardlink (nlink == 1). This must run before creating the rootfs tar.
# ---------------------------------------------------------------------------
slim_container_rootfs() {
	_rootfs="$1"

	echo "==> Slimming rootfs (docs, locales, ICU, host tools, moss cache, …)"

	# --- baseline (docs / locales / console data) ---
	rm -rf \
		"${_rootfs}/usr/share/man" \
		"${_rootfs}/usr/share/doc" \
		"${_rootfs}/usr/share/info" \
		"${_rootfs}/usr/share/gtk-doc" \
		"${_rootfs}/usr/share/help" \
		"${_rootfs}/usr/share/locale" \
		"${_rootfs}/usr/share/i18n" \
		"${_rootfs}/usr/share/cracklib" \
		"${_rootfs}/usr/share/kbd" \
		"${_rootfs}/usr/share/xkeyboard-config-2" \
		"${_rootfs}/usr/share/consolefonts" \
		"${_rootfs}/usr/share/fonts" \
		"${_rootfs}/usr/share/terminus" \
		"${_rootfs}/usr/share/bash-completion" \
		"${_rootfs}/usr/share/zsh" \
		"${_rootfs}/usr/share/fish" \
		"${_rootfs}/usr/share/pixmaps" \
		"${_rootfs}/usr/share/icons" \
		"${_rootfs}/usr/share/applications" \
		"${_rootfs}/usr/share/metainfo" \
		"${_rootfs}/usr/share/polkit-1" \
		"${_rootfs}/usr/share/gcc-16" \
		"${_rootfs}/usr/share/gdb" \
		"${_rootfs}/usr/include"

	if [ -d "${_rootfs}/usr/lib/locale" ]; then
		find "${_rootfs}/usr/lib/locale" -mindepth 1 -maxdepth 1 \
			! -name 'C.utf8' -exec rm -rf {} +
	fi

	rm -rf \
		"${_rootfs}/usr/lib/udev/hwdb.bin" \
		"${_rootfs}/usr/lib/udev/hwdb.d" \
		"${_rootfs}/usr/lib/systemd" \
		"${_rootfs}/usr/share/systemd" \
		"${_rootfs}/usr/lib/sysusers.d" \
		"${_rootfs}/usr/lib/tmpfiles.d" \
		"${_rootfs}/usr/lib/sysctl.d" \
		"${_rootfs}/usr/lib/modules-load.d" \
		"${_rootfs}/usr/lib/environment.d" \
		"${_rootfs}/usr/lib/kernel" \
		"${_rootfs}/usr/lib/binfmt.d" \
		"${_rootfs}/usr/lib/credstore" \
		"${_rootfs}/usr/share/factory" \
		"${_rootfs}/usr/lib/sysimage" \
		"${_rootfs}/usr/lib/modprobe.d"

	rm -f \
		"${_rootfs}/usr/bin/systemctl" \
		"${_rootfs}/usr/bin/journalctl" \
		"${_rootfs}/usr/bin/hostnamectl" \
		"${_rootfs}/usr/bin/timedatectl" \
		"${_rootfs}/usr/bin/loginctl" \
		"${_rootfs}/usr/bin/busctl" \
		"${_rootfs}/usr/bin/localectl" \
		"${_rootfs}/usr/bin/resolvectl" \
		"${_rootfs}/usr/bin/networkctl" \
		"${_rootfs}/usr/bin/homectl" \
		"${_rootfs}/usr/bin/userdbctl" \
		"${_rootfs}/usr/bin/portablectl" \
		"${_rootfs}/usr/bin/machinectl" \
		"${_rootfs}/usr/bin/bootctl" \
		"${_rootfs}/usr/bin/coredumpctl" \
		"${_rootfs}/usr/bin/kernel-install" \
		"${_rootfs}/usr/bin/oomctl" \
		"${_rootfs}/usr/bin/varlinkctl" \
		"${_rootfs}/usr/bin/udevadm" \
		"${_rootfs}/usr/bin/localedef" \
		"${_rootfs}/usr/bin/zic" \
		"${_rootfs}/usr/bin/zdump" \
		"${_rootfs}/usr/bin/sln" \
		"${_rootfs}/usr/bin/locate" \
		"${_rootfs}/usr/bin/updatedb" \
		"${_rootfs}/usr/bin/importctl"

	if [ -d "${_rootfs}/usr/bin" ]; then
		find "${_rootfs}/usr/bin" -maxdepth 1 \( \
			-name 'systemd-*' -o -name 'ntp-*' -o -name 'ntpd' -o -name 'ntpd-rs' \
			-o -name 'setfont' -o -name 'loadkeys' -o -name 'kbd_mode' \
			-o -name 'dumpkeys' -o -name 'showconsolefont' -o -name 'setvtrgb' \
			-o -name 'unicode_start' -o -name 'unicode_stop' -o -name 'psf*' \
			-o -name 'mapscrn' -o -name 'resizecons' \
			\) -delete 2>/dev/null || true
	fi

	# Zoneinfo: UTC only
	if [ -d "${_rootfs}/usr/share/zoneinfo" ]; then
		_tz_tmp="${_rootfs}/.slim-zoneinfo-$$"
		mkdir -p "${_tz_tmp}/Etc"
		for _z in UTC GMT Zulu Universal Greenwich Etc/UTC Etc/Universal Etc/Zulu Etc/GMT; do
			if [ -e "${_rootfs}/usr/share/zoneinfo/${_z}" ]; then
				mkdir -p "${_tz_tmp}/$(dirname "${_z}")"
				mv "${_rootfs}/usr/share/zoneinfo/${_z}" "${_tz_tmp}/${_z}" 2>/dev/null \
					|| cp -a "${_rootfs}/usr/share/zoneinfo/${_z}" "${_tz_tmp}/${_z}"
			fi
		done
		rm -rf "${_rootfs}/usr/share/zoneinfo"
		mv "${_tz_tmp}" "${_rootfs}/usr/share/zoneinfo"
		ln -sf /usr/share/zoneinfo/UTC "${_rootfs}/etc/localtime" 2>/dev/null || true
	fi

	# Terminfo: common types only
	if [ -d "${_rootfs}/usr/share/terminfo" ]; then
		_ti_tmp="${_rootfs}/.slim-terminfo-$$"
		mkdir -p "${_ti_tmp}"
		for _t in \
			xterm xterm-256color xterm-color xterm-direct \
			screen screen-256color \
			tmux tmux-256color \
			linux vt100 vt102 vt220 dumb ansi \
			rxvt rxvt-unicode rxvt-unicode-256color \
			putty putty-256color \
			gnome gnome-256color \
			konsole konsole-256color \
			alacritty foot kitty
		do
			_c=$(printf '%s' "${_t}" | cut -c1)
			if [ -e "${_rootfs}/usr/share/terminfo/${_c}/${_t}" ]; then
				mkdir -p "${_ti_tmp}/${_c}"
				mv "${_rootfs}/usr/share/terminfo/${_c}/${_t}" "${_ti_tmp}/${_c}/" 2>/dev/null \
					|| cp -a "${_rootfs}/usr/share/terminfo/${_c}/${_t}" "${_ti_tmp}/${_c}/"
			fi
		done
		rm -rf "${_rootfs}/usr/share/terminfo"
		mkdir -p "${_rootfs}/usr/share/terminfo"
		if [ -n "$(ls -A "${_ti_tmp}" 2>/dev/null || true)" ]; then
			mv "${_ti_tmp}"/* "${_rootfs}/usr/share/terminfo/"
		fi
		rm -rf "${_ti_tmp}"
	fi

	find "${_rootfs}/usr" -type f \( -name '*.a' -o -name '*.la' \) -delete 2>/dev/null || true

	# =========================================================================
	# P0: packaging dups + ICU stack + gconv trim
	# =========================================================================
	echo "==> P0: relink /usr/bin/[ → coreutils multicall"
	# uutils ships a full second multicall as `[` (~11.5MiB). `test` is the real one.
	if [ -e "${_rootfs}/usr/bin/test" ]; then
		rm -f "${_rootfs}/usr/bin/["
		ln -f "${_rootfs}/usr/bin/test" "${_rootfs}/usr/bin/["
	elif [ -e "${_rootfs}/usr/bin/coreutils" ]; then
		rm -f "${_rootfs}/usr/bin/["
		ln -f "${_rootfs}/usr/bin/coreutils" "${_rootfs}/usr/bin/["
	fi

	echo "==> P0: drop ICU / libxml2 / libstdc++ / xkb (transitive host junk)"
	rm -f \
		"${_rootfs}/usr/lib"/libicu*.so* \
		"${_rootfs}/usr/lib"/libxml2.so* \
		"${_rootfs}/usr/lib"/libstdc++.so* \
		"${_rootfs}/usr/lib/libstdc++.modules.json" \
		"${_rootfs}/usr/lib"/libxkbregistry.so* \
		"${_rootfs}/usr/lib"/libxkbcommon.so* \
		"${_rootfs}/usr/lib"/libxkbcommon-x11.so* \
		"${_rootfs}/usr/bin/xmllint" \
		"${_rootfs}/usr/bin/xmlcatalog"
	rm -rf \
		"${_rootfs}/usr/lib/icu" \
		"${_rootfs}/usr/share/icu" \
		"${_rootfs}/usr/share/libxml2" \
		"${_rootfs}/usr/share/xml"

	echo "==> P0: trim gconv to UTF/UNICODE essentials"
	if [ -d "${_rootfs}/usr/lib/gconv" ]; then
		# Keep modules config + UTF / UNICODE / ASCII-ish converters only.
		find "${_rootfs}/usr/lib/gconv" -type f ! -name 'gconv-modules*' \
			! -name 'UTF-*.so' ! -name 'UNICODE.so' ! -name 'ANSI_X3.4.so' \
			! -name 'ISO8859-1.so' ! -name 'ISO-8859-1.so' \
			! -name 'ASCII.so' ! -name 'US-ASCII.so' \
			-delete 2>/dev/null || true
		# If nothing matched UTF names, keep gconv-modules only (glibc may still work for C.utf8)
		find "${_rootfs}/usr/lib/gconv" -type d -empty -delete 2>/dev/null || true
	fi

	# =========================================================================
	# P1: small dups + residual host libs
	# =========================================================================
	echo "==> P1: gawk versioned dup hardlink (if both present)"
	if [ -e "${_rootfs}/usr/bin/gawk" ] && [ -e "${_rootfs}/usr/bin/gawk-5.4.0" ]; then
		rm -f "${_rootfs}/usr/bin/gawk-5.4.0"
		ln -f "${_rootfs}/usr/bin/gawk" "${_rootfs}/usr/bin/gawk-5.4.0"
	fi

	echo "==> P1: drop pcre2-16/32, brotlienc, p11 client/helpers, host crypto residual"
	rm -f \
		"${_rootfs}/usr/lib"/libpcre2-16.so* \
		"${_rootfs}/usr/lib"/libpcre2-32.so* \
		"${_rootfs}/usr/lib"/libbrotlienc.so* \
		"${_rootfs}/usr/lib/pkcs11/p11-kit-client.so" \
		"${_rootfs}/usr/lib"/libcryptsetup.so* \
		"${_rootfs}/usr/lib"/libdevmapper.so* \
		"${_rootfs}/usr/lib"/libbpf.so* \
		"${_rootfs}/usr/lib"/libdw*.so* \
		"${_rootfs}/usr/lib"/libelf.so* \
		"${_rootfs}/usr/lib"/libnss_systemd.so* \
		"${_rootfs}/usr/lib"/libnss_mymachines.so* \
		"${_rootfs}/usr/lib"/libnss_myhostname.so* \
		"${_rootfs}/usr/lib"/libnss_resolve.so* \
		"${_rootfs}/usr/lib/security/pam_systemd.so" \
		"${_rootfs}/usr/lib/security/pam_systemd_home.so" \
		"${_rootfs}/usr/lib/security/pam_systemd_loadkey.so" \
		"${_rootfs}/usr/lib/security/pam_pwquality.so" \
		"${_rootfs}/usr/lib"/libpwquality.so* \
		"${_rootfs}/usr/lib"/libcrack.so*
	rm -rf \
		"${_rootfs}/usr/lib/cryptsetup" \
		"${_rootfs}/usr/lib/p11-kit" \
		"${_rootfs}/usr/share/dbus-1" \
		"${_rootfs}/usr/share/mime" \
		"${_rootfs}/usr/lib/udev" \
		"${_rootfs}/usr/sbin/cracklib"* \
		"${_rootfs}/usr/bin/pwmake" \
		"${_rootfs}/usr/bin/pwscore" \
		"${_rootfs}/usr/bin/p11-kit" \
		"${_rootfs}/usr/bin/trust"

	# Keep libp11-kit.so + p11-kit-trust.so for CA trust if present; drop only client/remote.

	# =========================================================================
	# P2: drop gawk stack; neutralize awk-dependent hooks; curl cannot drop NEEDED libs
	# =========================================================================
	echo "==> P2: remove gawk + gmp/mpfr; pure-bash command-not-found"
	rm -f \
		"${_rootfs}/usr/bin/gawk" \
		"${_rootfs}/usr/bin/gawk-"* \
		"${_rootfs}/usr/bin/awk" \
		"${_rootfs}/usr/bin/gawkbug" \
		"${_rootfs}/usr/lib"/libgmp.so* \
		"${_rootfs}/usr/lib"/libgmpxx.so* \
		"${_rootfs}/usr/lib"/libmpfr.so*
	rm -rf "${_rootfs}/usr/lib/gawk" "${_rootfs}/usr/share/awk"

	# Disable systemd OSC prompt (uses sed every prompt; optional)
	rm -f \
		"${_rootfs}/usr/share/defaults/profile.d/80-systemd-osc-context.sh" \
		"${_rootfs}/usr/share/defaults/profile.d/70-systemd-shell-extra.sh"

	# Replace stock CNF (moss|head|awk recursion) with pure bash
	mkdir -p "${_rootfs}/usr/share/defaults/profile.d"
	cat > "${_rootfs}/usr/share/defaults/profile.d/80-command-not-found.sh" <<'CNFEOF'
# Container-safe command_not_found_handle (no awk/sudo recursion)
command_not_found_handle() {
	local cmd=$1 line pkg
	local FUNCNEST=8

	if command -v moss >/dev/null 2>&1; then
		for bin_type in binary sysbinary; do
			line=$(NO_COLOR=1 moss info "${bin_type}(${cmd})" 2>/dev/null) || continue
			line=${line%%$'\n'*}
			case ${line} in
				Name*)
					set -- ${line}
					# "Name <pkg> ..."
					if [ "$#" -ge 2 ] && [ "$1" = "Name" ]; then
						pkg=$2
						printf "bash: %s: command not found (try: moss install %s)\n" \
							"${cmd}" "${pkg}" >&2
						return 127
					fi
					;;
			esac
		done
	fi
	printf "bash: %s: command not found\n" "${cmd}" >&2
	return 127
}
CNFEOF

	# P2 curl: distro curl hard-links ldap/krb5/ssh2/idn2/http3 — cannot drop
	# those .so files without a rebuilt curl. Keep NEEDED set intact.
	# Remove only non-linked extras if any appear later.
	rm -f \
		"${_rootfs}/usr/lib"/libcurl.so*.a \
		"${_rootfs}/usr/share/curl" 2>/dev/null || true
	# OpenSSL legacy/fips modules not required for basic HTTPS
	rm -rf \
		"${_rootfs}/usr/lib/ossl-modules" \
		"${_rootfs}/usr/lib/engines-3" 2>/dev/null || true

	# =========================================================================
	# moss cache / locks / repo index (re-fetched on sync)
	# =========================================================================
	echo "==> Removing moss cache, locks, staging, isolation, local repo index"
	rm -rf \
		"${_rootfs}/.moss/cache" \
		"${_rootfs}/.moss/root" \
		"${_rootfs}/.moss/tmp" \
		"${_rootfs}/.moss/scratch" \
		"${_rootfs}/.moss/repo" \
		"${_rootfs}/var/cache/moss" \
		"${_rootfs}/var/cache" \
		"${_rootfs}/var/tmp/"* \
		"${_rootfs}/tmp/"*
	rm -f \
		"${_rootfs}/.moss/.moss-lockfile" \
		"${_rootfs}/.moss/lock" \
		"${_rootfs}/.moss/"*.lock 2>/dev/null || true
	find "${_rootfs}/.moss" -type f \( \
		-name '*lock*' -o -name '*.lock' -o -name 'CACHEDIR.TAG' \
		\) -delete 2>/dev/null || true

	mkdir -p \
		"${_rootfs}/.moss/cache" \
		"${_rootfs}/var/cache" \
		"${_rootfs}/var/tmp" \
		"${_rootfs}/tmp"
	chmod 1777 "${_rootfs}/tmp" "${_rootfs}/var/tmp" 2>/dev/null || true

	# GC content-addressed blobs no longer hardlinked from the live tree
	if [ -d "${_rootfs}/.moss/assets" ]; then
		echo "==> GC orphaned moss assets (nlink=1)"
		find "${_rootfs}/.moss/assets" -type f -links 1 -delete
		find "${_rootfs}/.moss/assets" -type d -empty -delete 2>/dev/null || true
	fi
}

mkdir -pv \
	"${ROOTFS}/etc" "${ROOTFS}/proc" "${ROOTFS}/run" "${ROOTFS}/sys" \
	"${ROOTFS}/tmp" "${ROOTFS}/var" "${ROOTFS}/home" "${ROOTFS}/root" \
	"${MOSS_CACHE}" "$(dirname "${OUT_TAR}")"

moss -D "${ROOTFS}" repo add "${REPO_NAME}" "${REPO_URL}" -p0
moss -D "${ROOTFS}" repo list
# Intentional word-split of package list
# shellcheck disable=SC2086
moss -D "${ROOTFS}" -y --cache "${MOSS_CACHE}" install ${PACKAGES}
moss -D "${ROOTFS}" state prune -k 1 --include-newer -y
rm -rf "${ROOTFS}/.moss/cache/downloads/"*

printf '%s\n' \
	'export PATH=/usr/bin:/usr/sbin' \
	'export LANG=C.UTF-8' \
	> "${ROOTFS}/etc/profile"

mkdir -pv "${ROOTFS}/etc/profile.d"
cat > "${ROOTFS}/etc/profile.d/00-container.sh" <<'EOF'
# AerynOS container image defaults
export PATH="${PATH:-/usr/bin:/usr/sbin}"
export LANG="${LANG:-C.UTF-8}"
EOF

mkdir -pv "${ROOTFS}/var/tmp" "${ROOTFS}/var/log"
chmod 1777 "${ROOTFS}/tmp" "${ROOTFS}/var/tmp"

# Pre-slim: required tools from seed packages (gawk intentionally optional)
missing=""
for bin in bash moss sed grep ls cat curl; do
	if [ ! -x "${ROOTFS}/usr/bin/${bin}" ] && [ ! -L "${ROOTFS}/usr/bin/${bin}" ]; then
		missing="${missing} ${bin}"
	fi
done
if [ -n "${missing}" ]; then
	echo "error: rootfs missing required binaries:${missing}" >&2
	exit 1
fi

slim_container_rootfs "${ROOTFS}"

# Post-slim essentials (no gawk)
for bin in bash moss sed grep ls cat curl; do
	if [ ! -e "${ROOTFS}/usr/bin/${bin}" ] && [ ! -L "${ROOTFS}/usr/bin/${bin}" ]; then
		echo "error: slim removed required binary: ${bin}" >&2
		exit 1
	fi
done
if [ ! -d "${ROOTFS}/usr/lib/locale/C.utf8" ]; then
	echo "error: slim removed C.utf8 locale" >&2
	exit 1
fi
# curl must still load
if ! chroot "${ROOTFS}" /usr/bin/curl --version >/dev/null 2>&1; then
	# chroot may fail without /proc; try direct loader
	if [ -x "${ROOTFS}/usr/lib/ld-linux-x86-64.so.2" ]; then
		"${ROOTFS}/usr/lib/ld-linux-x86-64.so.2" --library-path "${ROOTFS}/usr/lib" \
			"${ROOTFS}/usr/bin/curl" --version >/dev/null 2>&1 \
			|| { echo "error: curl broken after slim (missing NEEDED libs?)" >&2; exit 1; }
	fi
fi
# [ must still work via multicall
if [ ! -e "${ROOTFS}/usr/bin/[" ]; then
	echo "error: /usr/bin/[ missing after slim" >&2
	exit 1
fi

tar -C "${ROOTFS}" -cf "${OUT_TAR}" .
echo "Wrote ${OUT_TAR} (slimmed P0–P2 container rootfs)"
