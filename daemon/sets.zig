pub const pkg = struct {
    pub const essential = [_][]const u8{
        "bash",
        "coreutils",
        "filesystem",
        "gcc-libs",
        "glibc",
        "gzip",
        "shadow",
        "util-linux",
        "gawk",
        "grep",
        "sed",
    };

    pub const systemd = [_][]const u8{
        "systemd",
        "systemd-sysvcompat",
    };

    pub const sys_utils = [_][]const u8{
        "file",
        "findutils",
        "pciutils",
        "procps-ng",
        "psmisc",
    };

    pub const net_utils = [_][]const u8{
        "iputils",
        "iproute2",
        "networkmanager",
    };

    pub const archive_utils = [_][]const u8{
        "bzip2",
        "tar",
        "xz",
        "zstd",
    };
};

pub const driver = struct {
    pub const amd = [_][]const u8{
        "amd-ucode",
        "linux-firmware-amdgpu",
        "linux-firmware-radeon",
    };

    pub const intel = [_][]const u8{
        "intel-ucode",
        "linux-firmware-intel",
    };

    pub const nvidia = [_][]const u8{
        "linux-firmware-nvidia",
    };
};

pub const firmware = struct {
    pub const wireless = [_][]const u8{
        "linux-firmware-atheros",
        "linux-firmware-broadcom",
        "linux-firmware-mediatek",
        "linux-firmware-realtek",
    };

    pub const misc = [_][]const u8{
        "linux-firmware-cirrus",
        "linux-firmware-other",
    };
};
