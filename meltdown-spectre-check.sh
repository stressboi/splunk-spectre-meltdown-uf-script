#! /bin/sh
# Spectre & Meltdown checker
# Stephane Lesimple
# Modified by brodsky@splunk.com to output more friendly for Splunk UF Scripted Input
VERSION=0.16-SplunkUF
DATETIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
IPADD=$(hostname -I)
PROC=$(cat /proc/cpuinfo | grep 'model name' | uniq | cut -c14-80)
TRIMPROC="$(echo -e "${PROC}" | sed -e 's/[[:space:]]*$//')"

# print status function
pstatus()
{
	case "$1" in
		red)    col="";;
		green)  col="";;
		yellow) col="";;
		*)      col="";;
	esac
	/bin/echo -ne "$col$2 \033[0m"
	[ -n "$3" ] && /bin/echo -n "($3)"
	/bin/echo
}

# The 3 below functions are taken from the extract-linux script, available here:
# https://github.com/torvalds/linux/blob/master/scripts/extract-vmlinux
# The functions have been modified for better integration to this script
# The original header of the file has been retained below

# ----------------------------------------------------------------------
# extract-vmlinux - Extract uncompressed vmlinux from a kernel image
#
# Inspired from extract-ikconfig
# (c) 2009,2010 Dick Streefland <dick@streefland.net>
#
# (c) 2011      Corentin Chary <corentin.chary@gmail.com>
#
# Licensed under the GNU General Public License, version 2 (GPLv2).
# ----------------------------------------------------------------------

vmlinux=''
vmlinux_err=''
check_vmlinux()
{
	readelf -h $1 > /dev/null 2>&1 || return 1
	return 0
}

try_decompress()
{
	# The obscure use of the "tr" filter is to work around older versions of
	# "grep" that report the byte offset of the line instead of the pattern.

	# Try to find the header ($1) and decompress from here
	for     pos in `tr "$1\n$2" "\n$2=" < "$5" | grep -abo "^$2"`
	do
		if ! which $3 >/dev/null 2>&1; then
			vmlinux_err="missing '$3' tool, please install it, usually it's in the '$4' package"
			return 0
		fi
		pos=${pos%%:*}
		tail -c+$pos "$5" | $3 > $vmlinuxtmp 2> /dev/null
		check_vmlinux "$vmlinuxtmp" && vmlinux=$vmlinuxtmp && return 0
	done
	return 1
}

extract_vmlinux()
{
	[ -n "$1" ] || return 1
	# Prepare temp files:
	vmlinuxtmp="$(mktemp /tmp/vmlinux-XXX)"

	# Initial attempt for uncompressed images or objects:
	if check_vmlinux "$1"; then
		cat "$1" > "$vmlinuxtmp"
		echo "$vmlinuxtmp"
		return 0
	fi

	# That didn't work, so retry after decompression.
	try_decompress '\037\213\010' xy    gunzip     gunzip	"$1" && return 0
	try_decompress '\3757zXZ\000' abcde unxz       xz-utils	"$1" && return 0
	try_decompress 'BZh'          xy    bunzip2    bzip2	"$1" && return 0
	try_decompress '\135\0\0\0'   xxx   unlzma     xz-utils	"$1" && return 0
	try_decompress '\211\114\132' xy    'lzop -d'  lzop	"$1" && return 0
	return 1
}

# end of extract-vmlinux functions

/bin/echo -e "$DATETIME Spectre and Meltdown mitigation detection tool v$VERSION"
/bin/echo -e "$DATETIME Found_IPADDRESS=$IPADD"
/bin/echo -e "$DATETIME Found_PROC='$TRIMPROC'"

# root check

if [ "$(id -u)" -ne 0 ]; then
	/bin/echo -e "$DATETIME Note that you should launch this script with root privileges to get accurate information."
	/bin/echo -e "$DATETIME We'll proceed but you might see permission denied errors."
	/bin/echo -e "$DATETIME To run it as root, you can try the following command: sudo $0"
fi

/bin/echo -e "$DATETIME Checking vulnerabilities against Target_UNAME='"$(uname -s) $(uname -r) $(uname -v) $(uname -m)"'"

###########
# SPECTRE 1
/bin/echo -e "$DATETIME CVE-2017-5753 [bounds check bypass] aka 'Spectre Variant 1'"
/bin/echo -n "$DATETIME * Kernel_compiled_with_LFENCE_opcode_inserted="

status=0
img=''
# try to find the image of the current running kernel
[ -e /boot/vmlinuz-linux       ] && img=/boot/vmlinuz-linux
[ -e /boot/vmlinuz-$(uname -r) ] && img=/boot/vmlinuz-$(uname -r)
[ -e /boot/kernel-$( uname -r) ] && img=/boot/kernel-$( uname -r)
[ -e /boot/bzImage-$(uname -r) ] && img=/boot/bzImage-$(uname -r)
[ -e /boot/kernel-genkernel-$(uname -m)-$(uname -r) ] && img=/boot/kernel-genkernel-$(uname -m)-$(uname -r)
if [ -z "$img" ]; then
	pstatus yellow UNKNOWN "couldn't find your kernel image in /boot, if you used netboot, this is normal"
else
	if ! which readelf >/dev/null 2>&1; then
		pstatus yellow UNKNOWN "missing 'readelf' tool, please install it, usually it's in the 'binutils' package"
	else
		extract_vmlinux $img
		if [ "$vmlinux_err" != "" ]; then
			pstatus yellow UNKNOWN "couldn't extract your kernel from $img: $vmlinux_err"
		elif [ -z "$vmlinux" -o ! -r "$vmlinux" ]; then
			pstatus yellow UNKNOWN "couldn't extract your kernel from $img"
		elif ! which objdump >/dev/null 2>&1; then
			pstatus yellow UNKNOWN "missing 'objdump' tool, please install it, usually it's in the binutils package"
		else
			# here we disassemble the kernel and count the number of occurences of the LFENCE opcode
			# in non-patched kernels, this has been empirically determined as being around 40-50
			# in patched kernels, this is more around 70-80, sometimes way higher (100+)
			# v0.13: 68 found in a 3.10.23-xxxx-std-ipv6-64 (with lots of modules compiled-in directly), which doesn't have the LFENCE patches,
			# so let's push the threshold to 70.
			# TODO LKML patch is starting to dump LFENCE in favor of the PAUSE opcode, we might need to check that (patch not stabilized yet)
			nb_lfence=$(objdump -D "$vmlinux" | grep -wc lfence)
			if [ "$nb_lfence" -lt 70 ]; then
				pstatus red NO "only $nb_lfence opcodes found, should be >= 70"
				status=1
			else
				pstatus green YES "$nb_lfence opcodes found, which is >= 70"
				status=2
			fi
		fi
	fi
fi

/bin/echo -ne "$DATETIME > CVE-2017-2753_STATUS="
[ "$status" = 0 ] && pstatus yellow UNKNOWN
[ "$status" = 1 ] && pstatus red VULNERABLE
[ "$status" = 2 ] && pstatus green 'NOT_VULNERABLE'

###########
# VARIANT 2
/bin/echo -e "$DATETIME CVE-2017-5715 [branch target injection] aka 'Spectre Variant 2'"
/bin/echo "$DATETIME * Mitigation 1"
/bin/echo -n "$DATETIME *   hardware_support_for_mitigation="
if [ ! -e /dev/cpu/0/msr ]; then
	# try to load the module ourselves (and remember it so we can rmmod it afterwards)
	modprobe msr 2>/dev/null && insmod_msr=1
fi
if [ ! -e /dev/cpu/0/msr ]; then
	pstatus yellow UNKNOWN "couldn't read /dev/cpu/0/msr, is msr support enabled in your kernel?"
else
	# the new MSR 'SPEC_CTRL' is at offset 0x48
	# here we use dd, it's the same as using 'rdmsr 0x48' but without needing the rdmsr tool
	# if we get a read error, the MSR is not there
	dd if=/dev/cpu/0/msr of=/dev/null bs=8 count=1 skip=9 2>/dev/null
	if [ $? -eq 0 ]; then
		pstatus green YES
	else
		pstatus red NO
	fi
fi

if [ "$insmod_msr" = 1 ]; then
	# if we used modprobe ourselves, rmmod the module
	rmmod msr 2>/dev/null
fi

/bin/echo -n "$DATETIME *   Kernel_support_for_IBRS="
if [ ! -e /sys/kernel/debug/sched_features ]; then
	# try to mount the debugfs hierarchy ourselves and remember it to umount afterwards
	mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null && mounted_debugfs=1
fi
if [ -e /sys/kernel/debug/ibrs_enabled ]; then
	# if the file is there, we have IBRS compiled-in
	pstatus green YES
	ibrs_supported=1
	ibrs_enabled=$(cat /sys/kernel/debug/ibrs_enabled 2>/dev/null)
elif [ -e /sys/kernel/debug/x86/ibrs_enabled ]; then
	# RedHat uses a different path (see https://access.redhat.com/articles/3311301)
	pstatus green YES
	ibrs_supported=1
	ibrs_enabled=$(cat /sys/kernel/debug/x86/ibrs_enabled 2>/dev/null)
else
	pstatus red NO
fi

/bin/echo -n "$DATETIME *   IBRS_enabled_for_Kernel_space="
# 0 means disabled
# 1 is enabled only for kernel space
# 2 is enabled for kernel and user space
case "$ibrs_enabled" in
	"") [ "$ibrs_supported" = 1 ] && pstatus yellow UNKNOWN || pstatus red NO;;
	0)     pstatus red NO;;
	1 | 2) pstatus green YES;;
	*)     pstatus yellow UNKNOWN;;
esac

/bin/echo -n "$DATETIME *   IBRS_enabled_for_User_space="
case "$ibrs_enabled" in
	"") [ "$ibrs_supported" = 1 ] && pstatus yellow UNKNOWN || pstatus red NO;;
	0 | 1) pstatus red NO;;
	2) pstatus green YES;;
	*) pstatus yellow UNKNOWN;;
esac

/bin/echo "$DATETIME * Mitigation 2"
/bin/echo -n "$DATETIME *   Kernel_compiled_with_retpoline_option="
# We check the RETPOLINE kernel options
if [ -e /proc/config.gz ]; then
	# either the running kernel exports his own config
	if zgrep -q '^CONFIG_RETPOLINE=y' /proc/config.gz; then
		pstatus green YES
		retpoline=1
	else
		pstatus red NO
	fi
elif [ -e /boot/config-$(uname -r) ]; then
	# or we can find a config file in /root with the kernel release name
	if grep  -q '^CONFIG_RETPOLINE=y' /boot/config-$(uname -r); then
		pstatus green YES
		retpoline=1
	else
		pstatus red NO
	fi
else
	pstatus yellow UNKNOWN "couldn't read your kernel configuration"
fi

/bin/echo -n "$DATETIME *   Kernel_compiled_with_a_retpoline-aware_compiler="
# Now check if the compiler used to compile the kernel knows how to insert retpolines in generated asm
# For gcc, this is -mindirect-branch=thunk-extern (detected by the kernel makefiles)
# See gcc commit https://github.com/hjl-tools/gcc/commit/23b517d4a67c02d3ef80b6109218f2aadad7bd79
# In latest retpoline LKML patches, the noretpoline_setup symbol exists only if CONFIG_RETPOLINE is set
# *AND* if the compiler is retpoline-compliant, so look for that symbol
if [ -n "$vmlinux" ]; then
	# look for the symbol
	if [ -e /boot/System.map-$(uname -r) ]; then
		if grep -qw noretpoline_setup /boot/System.map-$(uname -r); then
			retpoline_compiler=1
			pstatus green YES "noretpoline_setup symbol found in System.map"
		fi
	elif which nm >/dev/null 2>&1; then
		# the proper way: use nm and look for the symbol
		if nm "$vmlinux" 2>/dev/null | grep -qw 'noretpoline_setup'; then
			retpoline_compiler=1
			pstatus green YES "noretpoline_setup symbol found in vmlinux"
		fi
	elif grep -q noretpoline_setup "$vmlinux"; then
		# if we don't have nm, nevermind, the symbol name is long enough to not have
		# any false positive using good old grep directly on the binary
		retpoline_compiler=1
		pstatus green YES "noretpoline_setup symbol found in vmlinux"
	fi
	if [ "$retpoline_compiler" != 1 ]; then
		pstatus red NO
	fi
else
	pstatus yellow UNKNOWN "couldn't find your kernel image"
fi


/bin/echo -ne "$DATETIME > CVE-2017-5715_STATUS="
if grep -q AMD /proc/cpuinfo; then
	pstatus green "NOT_VULNERABLE" "your CPU is not vulnerable as per the vendor"
elif [ "$ibrs_enabled" = 1 -o "$ibrs_enabled" = 2 ]; then
	pstatus green "NOT_VULNERABLE" "IBRS mitigates the vulnerability"
elif [ "$retpoline" = 1 -a "$retpoline_compiler" = 1 ]; then
	pstatus green "NOT_VULNERABLE" "retpoline mitigate the vulnerability"
else
	pstatus red VULNERABLE "IBRS hardware + kernel support OR kernel with retpoline are needed to mitigate the vulnerability"
fi

##########
# MELTDOWN
/bin/echo -e "$DATETIME CVE-2017-5754 [rogue data cache load] aka 'Meltdown' aka 'Variant 3'"
/bin/echo -n "$DATETIME * Kernel_supports_Page_Table_Isolation="
kpti_support=0
kpti_can_tell=0
if [ -e /proc/config.gz ]; then
	# either the running kernel exports his own config
	kpti_can_tell=1
	if zgrep -q '^\(CONFIG_PAGE_TABLE_ISOLATION=y\|CONFIG_KAISER=y\)' /proc/config.gz; then
		kpti_support=1
	fi
elif [ -e /boot/config-$(uname -r) ]; then
	# or we can find a config file in /root with the kernel release name
	kpti_can_tell=1
	if grep  -q '^\(CONFIG_PAGE_TABLE_ISOLATION=y\|CONFIG_KAISER=y\)' /boot/config-$(uname -r); then
		kpti_support=1
	fi
fi
if [ "$kpti_support" = 0 -a -e /boot/System.map-$(uname -r) ]; then
	# it's not an elif: some backports don't have the PTI config but still include the patch
	# so we try to find an exported symbol that is part of the PTI patch in System.map
	kpti_can_tell=1
	if grep -qw kpti_force_enabled /boot/System.map-$(uname -r); then
		kpti_support=1
	fi
fi
if [ "$kpti_support" = 0 -a -n "$vmlinux" ]; then
	# same as above but in case we don't have System.map and only vmlinux, look for the
	# nopti option that is part of the patch (kernel command line option)
	kpti_can_tell=1
	if ! which strings >/dev/null 2>&1; then
		pstatus yellow UNKNOWN "missing 'strings' tool, please install it, usually it's in the binutils package"
	else
		if strings "$vmlinux" | grep -qw nopti; then
			kpti_support=1
		fi
	fi
fi

if [ "$kpti_support" = 1 ]; then
	pstatus green YES
elif [ "$kpti_can_tell" = 1 ]; then
	pstatus red NO
else
	pstatus yellow UNKNOWN "couldn't read your kernel configuration"
fi

/bin/echo -n "$DATETIME * PTI_enabled_and_active="
if grep ^flags /proc/cpuinfo | grep -qw pti; then
	# vanilla PTI patch sets the 'pti' flag in cpuinfo
	kpti_enabled=1
elif grep ^flags /proc/cpuinfo | grep -qw kaiser; then
	# kernel line 4.9 sets the 'kaiser' flag in cpuinfo
	kpti_enabled=1
elif [ -e /sys/kernel/debug/x86/pti_enabled ]; then
	# RedHat Backport creates a dedicated file, see https://access.redhat.com/articles/3311301
	kpti_enabled=$(cat /sys/kernel/debug/x86/pti_enabled 2>/dev/null)
elif dmesg | grep -Eq 'Kernel/User page tables isolation: enabled|Kernel page table isolation enabled'; then
	# if we can't find the flag, grep in dmesg
	kpti_enabled=1
else
	kpti_enabled=0
fi
if [ "$kpti_enabled" = 1 ]; then
	pstatus green YES
else
	pstatus red NO
fi

if [ "$mounted_debugfs" = 1 ]; then
	# umount debugfs if we did mount it ourselves
	umount /sys/kernel/debug
fi

/bin/echo -ne "$DATETIME > CVE-2017-5754_STATUS="
if grep -q AMD /proc/cpuinfo; then
	pstatus green "NOT_VULNERABLE" "your CPU is not vulnerable as per the vendor"
elif [ "$kpti_enabled" = 1 ]; then
	pstatus green "NOT_VULNERABLE" "PTI mitigates the vulnerability"
else
	pstatus red "VULNERABLE" "PTI is needed to mitigate the vulnerability"
fi


[ -n "$vmlinux" -a -f "$vmlinux" ] && rm -f "$vmlinux"
