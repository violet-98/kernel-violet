#!/bin/bash
kernel_dir="${PWD}"
CCACHE=$(command -v ccache)
objdir="${kernel_dir}/out"
anykernel=$HOME/anykernel
ZIMAGE=$kernel_dir/out/arch/arm64/boot/Image.gz-dtb
kernel_name="RyZeN_violet-Q-dtbo"
KERVER=$(make kernelversion)
# Zip Name
set_naming_dynamic() {
    local suffix="DN"
    if [ -d "${kernel_dir}/KernelSU" ]; then
        suffix="${suffix}-KSU"
    elif [ -d "${kernel_dir}/KernelSU-Next" ]; then
        suffix="${suffix}-KSUN"
    fi
    if [[ -f "${kernel_dir}/fs/susfs.c" || -f "${kernel_dir}/include/linux/susfs.h" ]]; then
        suffix="${suffix}-SUSFS"
    fi
    export zip_name="${kernel_name}-${suffix}-$(TZ="Asia/Dhaka" date +"%d%m%Y-%H%M").zip"
}
set_naming() {
    local suffix=""
    if [ -d "${kernel_dir}/KernelSU" ]; then
        suffix="KSU"
    elif [ -d "${kernel_dir}/KernelSU-Next" ]; then
        suffix="KSUN"
    fi
    if [[ -f "${kernel_dir}/fs/susfs.c" || -f "${kernel_dir}/include/linux/susfs.h" ]]; then
        suffix="${suffix}-SUSFS"
    fi
    export zip_name="${kernel_name}-${suffix}-$(TZ="Asia/Dhaka" date +"%d%m%Y-%H%M").zip"
}

TC_DIR=$HOME/CLANG-13/
#Setup Compiler
if ! [ $(uname -m) == "aarch64" ]; then
    CLANG_DIR=$TC_DIR
else
    CLANG_DIR=/home/coder/project/clang
fi
export CONFIG_FILE="vendor/violet-perf_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=arch
export KBUILD_BUILD_USER=BlackTape
LINUX_COMPILE_BY="BlackTape"
LINUX_COMPILE_HOST="arch"
export PATH="$CLANG_DIR/bin:$PATH"

# Telegram Config
export CHATID TOKEN
BOT_MSG_URL="https://api.telegram.org/bot${TOKEN}/sendMessage"
BOT_BUILD_URL="https://api.telegram.org/bot${TOKEN}/sendDocument"
BOT_STICKER_URL="https://api.telegram.org/bot${TOKEN}/sendSticker"

# Build Machine details
cores=$(nproc --all)
os=$(cat /etc/issue)
time=$(TZ="Asia/Dhaka" date "+%a %b %d %r")

# send normal msgs to tg
tg_post_msg() {
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$1"
}

# send build to tg
tg_post_build()
{
	#Post MD5Checksum alongwith for easeness
	MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)
	#Show the Checksum alongwith caption
	curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
	-F chat_id="$CHATID" \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2"
}

# send a nice sticker ro act as a sperator between builds
tg_post_sticker() {
  curl -s -X POST "$BOT_STICKER_URL" -d chat_id="$CHATID" \
    -d sticker="CAACAgUAAxkBAAECHIJgXlYR8K8bYvyYIpHaFTJXYULy4QACtgIAAs328FYI4H9L7GpWgR4E"
}

# KernelSU: Sync with repo
if [ -d "${kernel_dir}/KernelSU" ] || [ -d "${kernel_dir}/KernelSU-Next" ]; then
    echo "KernelSU: Sync with repo"
    git submodule update --init --recursive
else
    echo "No KernelSU or KernelSU-Next directory found — skipping submodule sync"
fi

#start off by sending a trigger msg
send_tg_msg() {
tg_post_sticker
	tg_post_msg "<b>Kernel Build Triggered ⌛</b>%0A<b>Kernel : </b><code>$kernel_name</code>%0A<b>Device : </b><code>Redmi Note 7 Pro (violet)</code>%0A<b>Upstream : </b><code>$KERVER</code>%0A<b>Date : </b><code>$time</code>"
}

# Cloning Compiler
if ! [ $(uname -m) == "aarch64" ]; then
    if ! [ -d "$TC_DIR" ]; then
        echo "Toolchain not found! Cloning to $TC_DIR..."
        if ! git clone --depth=1 --single-branch https://github.com/kdrag0n/proton-clang $TC_DIR; then
            echo "Cloning failed! Aborting..."
            exit 1
        fi
    fi
fi

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'

setup_dynamic() {
    echo  # ensures prompt is on a new line
    read -p "Want to Build Dynamic Kernel? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
    git apply dynamic.patch
        echo "✅ Patch applied."
        set_naming_dynamic
        echo "📦 Zip name set to: $zip_name"
    else
        echo "❌ Skipped applying dynamic.patch."
        set_naming
        echo "📦 Zip name set to: $zip_name"
    fi
}
make_defconfig() {
    START=$(date +"%s")
    echo -e ${LGR} "####### Generating Defconfig #######${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j$(nproc --all)
}
compile()
{
    cd ${kernel_dir}
    echo -e ${LGR} "######### Compiling kernel #########${NC}"
    make -j$(nproc --all) \
    O=out \
    ARCH=${ARCH}\
    CC="ccache clang" \
    CLANG_TRIPLE="aarch64-linux-gnu-" \
    CROSS_COMPILE="aarch64-linux-gnu-" \
    CROSS_COMPILE_ARM32="arm-linux-gnueabi-" \
    LLVM=1 \
    LLVM_IAS=1 \
    AR=llvm-ar \
    NM=llvm-nm \
    LD=ld.lld \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    2>&1 | tee build.log
}

completion() {
    cd ${objdir}
    COMPILED_IMAGE=arch/arm64/boot/Image.gz-dtb
    COMPILED_DTBO=arch/arm64/boot/dtbo.img
    if [[ -f ${COMPILED_IMAGE} && ${COMPILED_DTBO} ]]; then
        git clone --depth=1 -q https://github.com/violet-98/AnyKernel3 -b violet $anykernel
        mv -f $ZIMAGE ${COMPILED_DTBO} $anykernel
        cd $anykernel
        find . -name "*.zip" -type f
        find . -name "*.zip" -type f -delete
        zip -r AnyKernel.zip *
        mv AnyKernel.zip $zip_name
        mv $anykernel/$zip_name $HOME/$zip_name
        cd ~ || exit 1
        rm -rf $anykernel
        END=$(date +"%s")
        DIFF=$(($END - $START))
        tg_post_build "$HOME/$zip_name" "Build Time : $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
        goup() {
            bash <(curl -s https://raw.githubusercontent.com/Sanjivns/GoFile-Upload/refs/heads/master/upload) "$@"
        }
        url=$(goup "$HOME/$zip_name")
        echo $url
        zip_size=$(du -h $HOME/$zip_name | awk '{print $1}')
        tg_post_msg "<b>Compiled successfully✅</b>%0A<b>File Name:</b> <code>$zip_name</code>%0A<b>File Size:</b> <code>$zip_size</code>%0A<b>Download Link:</b> <a href='${url}'>Click Here</a>%0A<b>Build Time: $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)</b>"
        rm $HOME/$zip_name
        echo -e ${LGR} "###########################################"
        echo -e ${LGR} "############# OkThisIsEpic!  ##############"
        echo -e ${LGR} "###########################################${NC}"
    else
        tg_post_build "$kernel_dir/build.log" "Debug Mode Logs"
        tg_post_msg "<code>Compilation failed❎</code>"
        echo -e ${RED} "###########################################"
        echo -e ${RED} "##           This Is Not Epic!           ##"
        echo -e ${RED} "###########################################${NC}"
    fi
}
send_tg_msg

setup_dynamic
make_defconfig
compile
completion