#!/usr/bin/env bash
#
#  build.sh - Automic kernel building script for Rosemary Kernel
#
#  Copyright (C) 2021-2023, Crepuscular's AOSP WorkGroup
#  Author: EndCredits <alicization.han@gmail.com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.
#
#  Add clang to your PATH before using this script.
#

ARCH=arm64;
CC=clang;
LD=ld.lld
CLANG_TRIPLE=aarch64-linux-gnu-;
CROSS_COMPILE=aarch64-linux-gnu-;
CROSS_COMPILE_COMPAT=arm-linux-gnueabi-;
THREAD=$(nproc --all);
CC_ADDITION_FLAGS="LD=$LD";
OUT="../out";

TARGET_KERNEL_FILE=arch/arm64/boot/Image;
TARGET_KERNEL_DTB=arch/arm64/boot/dtb;
TARGET_KERNEL_DTBO=arch/arm64/boot/dtbo.img
TARGET_KERNEL_NAME=Driftwood-Kernel;

DEFCONFIG_PATH=arch/arm64/configs
DEFCONFIG_NAME=vendor/picasso_user_defconfig;
DISABLE_KSU_FRAGMENT=vendor/disable_ksu.config;

LOCAL_VERSION_NUMBER=$(cat $DEFCONFIG_PATH/$DEFCONFIG_NAME | grep CONFIG_LOCALVERSION= | cut -d = -f 2 | sed 's/"//g' | sed 's/-Driftwood-//g')
TARGET_KERNEL_MOD_VERSION=$(make kernelversion)-$LOCAL_VERSION_NUMBER;

START_SEC=$(date +%s);
CURRENT_TIME=$(date '+%Y-%m%d%H%M');

ANYKERNEL_URL=https://codeload.github.com/EndCredits/AnyKernel3/zip/refs/heads/picasso;
ANYKERNEL_PATH=AnyKernel3-picasso;
ANYKERNEL_FILE=anykernel.zip;

WITH_KERNELSU=1

TARGET_CONFIG="$OUT/.config"

link_all_dtb_files(){
    find $OUT/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + > $OUT/arch/arm64/boot/dtb;
}

make_defconfig(){
    echo "------------------------------";
    echo " Building Kernel Defconfig..";
    echo "------------------------------";

    if [ $WITH_KERNELSU == 0 ]; then
        DEFCONFIG_NAME="$DEFCONFIG_NAME $DISABLE_KSU_FRAGMENT"
    fi

    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE LLVM=1 LLVM_IAS=1 $CC_ADDITION_FLAGS O=$OUT -j$THREAD $DEFCONFIG_NAME;
    if [ $WITH_KERNELSU == 1 ]; then
        # 1. 强行关闭 TRACEPOINT 钩子
        echo "⚙️ 正在强行修改并补全子选项: $TARGET_CONFIG ..."

        # 1. 强行关闭 TRACEPOINT 钩子
        sed -i 's/^CONFIG_KSU_TRACEPOINT_HOOK=y/# CONFIG_KSU_TRACEPOINT_HOOK is not set/g' "$TARGET_CONFIG"

        # 2. 强行开启 MANUAL 手动钩子
        sed -i 's/^# CONFIG_KSU_MANUAL_HOOK is not set/CONFIG_KSU_MANUAL_HOOK=y/g' "$TARGET_CONFIG"
        sed -i 's/^CONFIG_KSU_MANUAL_HOOK=n/CONFIG_KSU_MANUAL_HOOK=y/g' "$TARGET_CONFIG"

        # 3. 核心修复：强行喂饱新出现的 3 个 LSM / Auto 钩子选项，防止 CI 环境弹窗死锁
        # 从你的 ReSukiSU 检查日志看，这里全部需要设置为 y
        for cfg in CONFIG_KSU_MANUAL_HOOK_AUTO_SETUID_HOOK CONFIG_KSU_MANUAL_HOOK_AUTO_INITRC_HOOK CONFIG_KSU_MANUAL_HOOK_AUTO_INPUT_HOOK; do
        # 删掉可能存在的冲突行或注释行
        sed -i "/$cfg/d" "$TARGET_CONFIG"
        # 直接追加进配置文件
        echo "$cfg=y" >> "$TARGET_CONFIG"
    done

    # 4. 安全兜底
    if ! grep -q "CONFIG_KSU_MANUAL_HOOK=" "$TARGET_CONFIG"; then
        echo "CONFIG_KSU_MANUAL_HOOK=y" >> "$TARGET_CONFIG"
    fi

    echo "✅ 强改及子项补全成功！当前配置状态："
    grep -E "CONFIG_KSU_MANUAL_HOOK|CONFIG_KSU_TRACEPOINT_HOOK" "$TARGET_CONFIG"
    else
        echo "❌ 错误：未找到目标文件 $TARGET_CONFIG，请确认路径是否正确！"
    fi
}

build_kernel(){
    echo "------------------------------";
    echo " Building Kernel ...........";
    echo "------------------------------";

    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE LLVM=1 LLVM_IAS=1 $CC_ADDITION_FLAGS O=$OUT -j$THREAD;
    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Kernel Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"

}

generate_flashable(){
    echo "------------------------------";
    echo " Generating Flashable Kernel";
    echo "------------------------------";

    cd $OUT;
    
    if [ ! -d $ANYKERNEL_PATH ]; then
        echo ' Getting AnyKernel ';
        curl $ANYKERNEL_URL -o $ANYKERNEL_FILE;
        unzip -o $ANYKERNEL_FILE;
    else
        echo ' Anykernel 3 Detected. Skipping download '
    fi

    echo ' Removing old package file ';
    rm -rf $ANYKERNEL_PATH/$TARGET_KERNEL_NAME*;

    echo ' Copying Kernel File '; 
    cp -r $TARGET_KERNEL_FILE $ANYKERNEL_PATH/;
    cp -r $TARGET_KERNEL_DTB $ANYKERNEL_PATH/;
    cp -r $TARGET_KERNEL_DTBO $ANYKERNEL_PATH/;

    echo ' Packaging flashable Kernel ';
    cd $ANYKERNEL_PATH;
    zip -q -r $TARGET_KERNEL_NAME-$CURRENT_TIME-$TARGET_KERNEL_MOD_VERSION.zip *;

    echo " Target File:  $OUT/$ANYKERNEL_PATH/$TARGET_KERNEL_NAME-$CURRENT_TIME-$TARGET_KERNEL_MOD_VERSION.zip ";
}

save_defconfig(){
    echo "------------------------------";
    echo " Saving kernel config ........";
    echo "------------------------------";

    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE $CC_ADDITION_FLAGS O=$OUT -j$THREAD savedefconfig;
    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Finished. Kernel config saved to $OUT/defconfig"
    echo "Moving kernel defconfig to source tree"
    mv $OUT/defconfig $DEFCONFIG_PATH/$DEFCONFIG_NAME
    echo "Kernel Config Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"

}

clean(){
    echo "Clean source tree and build files..."
    make mrproper -j$THREAD;
    make clean -j$THREAD;
    rm -rf $OUT;
}

main(){
    if [[ $2 == "noksu" ]]; then
        echo "Building without Kernel SU"
        WITH_KERNELSU=0
    fi
    if [ $1 == "help" -o $1 == "-h" ]
    then
        echo "build.sh: A very simple Kernel build helper"
        echo "usage: build.sh <operation> <optional argument>"
        echo
        echo "Build operations:"
        echo "    all             Perform a build without cleaning."
        echo "    cleanbuild      Clean the source tree and build files then perform a all build."
        echo
        echo "    flashable       Only generate the flashable zip file. Don't use it before you have built once."
        echo "    savedefconfig   Save the defconfig file to source tree."
        echo "    defconfig       Only build kernel defconfig"
        echo "    help ( -h )     Print help information."
        echo "    version         Display the version number."
        echo
        echo "Optional argument"
        echo "    noksu           Build without Kernel SU (with \"all\" and \"defconfig\" operation)"
        echo
    elif [ $1 == "savedefconfig" ]
    then
        save_defconfig;
    elif [ $1 == "cleanbuild" ]
    then
        clean;
        make_defconfig;
        build_kernel;
        link_all_dtb_files;
        generate_flashable;
    elif [ $1 == "flashable" ]
    then
        generate_flashable;
    elif [ $1 == "kernelonly" ]
    then
        make_defconfig
        build_kernel
    elif [ $1 == "all" ]
    then
        make_defconfig
        build_kernel
        link_all_dtb_files
        generate_flashable
    elif [ $1 == "defconfig" ]
    then
        make_defconfig;
    elif [ $1 == "version" ] 
    then 
        echo "Current version is: $LOCAL_VERSION_NUMBER"
    else
        echo "Incorrect usage. Please run: "
        echo "  bash build.sh help (or -h) "
        echo "to display help message."
    fi
}

main "$1" "$2";
