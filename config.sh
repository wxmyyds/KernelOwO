#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-only

# Compare kernel versions in order to apply the correct patches
version_le() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

# Avoid dirty uname
touch $KERNEL_DIR/.scmversion

msg "KernelSU"
cd $KERNEL_DIR && curl https://raw.githubusercontent.com/$KERNELSU_REPO/refs/heads/$KERNELSU_BRANCH/kernel/setup.sh | bash -s $KERNELSU_BRANCH
msg "Importing KernelSU..."

cd $KERNEL_DIR

echo "CONFIG_KSU_MANUAL_HOOK=y" >> $DEVICE_DEFCONFIG_FILE
echo "CONFIG_KSU_TOOLKIT_SUPPORT=y" >> $DEVICE_DEFCONFIG_FILE

KSU_GIT_VERSION=$(cd KernelSU && git rev-list --count HEAD)
KERNELSU_VERSION=$(($KSU_GIT_VERSION + 30700))

msg "KernelSU Version: $KERNELSU_VERSION"

if [[ $VB_ENABLED == "true" ]]; then
    msg "VB"
fi
if [[ $VB_ENABLED == "false" ]]; then
    msg "NonVB"
    curl https://raw.githubusercontent.com/$BUILDER_REPO/refs/heads/$BUILDER_BRANCH/patches/initramfs_recovery.patch | git am
fi

# Apply ReSukiSU manual hooks via sed
msg "Applying ReSukiSU manual hooks..."

cd $KERNEL_DIR

# ----- fs/exec.c: ksu_handle_execveat -----
# Add extern declaration before do_execve function
sed -i '/^int do_execve(struct filename \*filename,$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\
				void *argv, void *envp, int *flags);\
#endif
' fs/exec.c

# Add hook call before return in do_execve and compat_do_execve
sed -i '/^	return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_execveat((int *)AT_FDCWD, \&filename, \&argv, \&envp, NULL);\
#endif
' fs/exec.c

# ----- fs/stat.c: ksu_handle_stat, ksu_handle_newfstat_ret, ksu_handle_fstat64_ret -----
# Add extern declarations
sed -i '/^#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_stat(int *dfd, const char __user **filename_user,\
				int *flags);\
\
extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);\
#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)\
extern void ksu_handle_fstat64_ret(unsigned long *fd, struct stat64 __user **statbuf_ptr);\
#endif\
#endif
' fs/stat.c

# Add ksu_handle_stat in newfstatat
sed -i '/^SYSCALL_DEFINE4(newfstatat, int, dfd,/,/^}/{
/^	int error;$/a\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif
}' fs/stat.c

# Add ksu_handle_newfstat_ret in newfstat
sed -i '/^SYSCALL_DEFINE2(newfstat, unsigned int, fd,/,/^}/{
/^	return error;$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_newfstat_ret(\&fd, \&statbuf);\
#endif
}' fs/stat.c

# Add ksu_handle_stat in fstatat64
sed -i '/^SYSCALL_DEFINE4(fstatat64, int, dfd,/,/^}/{
/^	int error;$/a\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_stat(\&dfd, \&filename, \&flag);\
#endif
}' fs/stat.c

# Add ksu_handle_fstat64_ret in fstat64
sed -i '/^SYSCALL_DEFINE2(fstat64, unsigned long, fd,/,/^}/{
/^	return error;$/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_fstat64_ret(\&fd, \&statbuf);\
#endif
}' fs/stat.c

# ----- fs/open.c: ksu_handle_faccessat -----
# Add extern declaration before faccessat
sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd,/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
__attribute__((hot))\
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\
				int *mode, int *flags);\
#endif
' fs/open.c

# Add hook call in faccessat
sed -i '/^SYSCALL_DEFINE3(faccessat, int, dfd,/,/^}/{
/^{$/a\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_faccessat(\&dfd, \&filename, \&mode, NULL);\
#endif
}' fs/open.c

# ----- kernel/reboot.c: ksu_handle_sys_reboot -----
# Add extern declaration before reboot syscall
sed -i '/^SYSCALL_DEFINE4(reboot, int, magic1,/i\
#ifdef CONFIG_KSU_MANUAL_HOOK\
extern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\
#endif
' kernel/reboot.c

# Add hook call in reboot syscall
sed -i '/^	int ret = 0;$/a\
#ifdef CONFIG_KSU_MANUAL_HOOK\
	ksu_handle_sys_reboot(magic1, magic2, cmd, \&arg);\
#endif
' kernel/reboot.c

msg "ReSukiSU manual hooks applied successfully"
