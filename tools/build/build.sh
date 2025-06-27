#!/bin/bash

# Thanks to Adam Spaini for the script (@adams4d13)


kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
output_dir="${kernel_dir}/output"
anykernel_dir="${kernel_dir}/tc/anykernel"
kernel_name="GoreKernel_vayu_"
zip_name="$kernel_name$(date +"%Y%m%d").zip"
ZIMAGE="${objdir}/arch/arm64/boot/Image"
CLANG_DIR="${kernel_dir}/tc/clang"
GCC64_DIR="${kernel_dir}/tc/gcc64"
GCC32_DIR="${kernel_dir}/tc/gcc32"
MKDTBOIMG="${kernel_dir}/tc/libufdt/utils/src/mkdtboimg.py"
DTBO_IMG="${anykernel_dir}/dtbo.img"
DISPLAY="arch/arm64/boot/dts/qcom/xiaomi/overlay/common/display"

export CONFIG_FILE="sm8150-perf_defconfig"
export ARCH="arm64"
export KBUILD_BUILD_HOST=adams4d13
export KBUILD_BUILD_USER=arch-linux
export PATH="${CLANG_DIR}/bin:${GCC64_DIR}/bin:${GCC32_DIR}/bin:${PATH}"

# Colores
NC='\033[0m'
RED='\033[0;31m'
LGR='\033[1;32m'
LYW='\033[1;33m'



clone_tools() {
    echo -e "${LYW}Setting up toolchains...${NC}"
    
    mkdir -p "${kernel_dir}/tc"

    [ -d "$CLANG_DIR" ] || {
        echo -e "${LYW}Cloning Crdroid Clang...${NC}"
        git clone -q --depth=1 --single-branch \
            https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git \
            -b 15.0 "$CLANG_DIR"
    }

    [ -d "$GCC64_DIR" ] || {
        echo -e "${LYW}Cloning GCC64...${NC}"
        git clone -q --depth=1 --single-branch \
            https://github.com/mvaisakh/gcc-arm64.git "$GCC64_DIR"
    }

    [ -d "$GCC32_DIR" ] || {
        echo -e "${LYW}Cloning GCC32...${NC}"
        git clone -q --depth=1 --single-branch \
            https://github.com/mvaisakh/gcc-arm.git "$GCC32_DIR"
    }

    [ -f "$MKDTBOIMG" ] || {
        echo -e "${LYW}Cloning libufdt...${NC}"
        git clone -q --depth=1 \
            https://android.googlesource.com/platform/system/libufdt "${kernel_dir}/tc/libufdt"
    }

    if [ ! -d "$anykernel_dir" ]; then
        echo -e "${LYW}Cloning AnyKernel3 to tc/anykernel...${NC}"
        git clone -q https://github.com/adamspaini/AnyKernel3.git -b master "$anykernel_dir"
    else
        echo -e "${LYW}Updating AnyKernel in tc/anykernel...${NC}"
        (cd "$anykernel_dir" && git pull -q)
    fi
}

make_defconfig() {
    echo -e "${LGR}Generating Defconfig${NC}"
    make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j$(nproc)
}

compile() {
    echo -e "${LGR}######### Compiling kernel #########${NC}"
    make -j$(nproc) -l$(nproc) \
        O=${objdir} \
        ARCH=arm64 \
        CC="ccache clang" \
        SUBARCH=arm64 \
        DTC_EXT=dtc \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
        AR=llvm-ar \
        STRIP=llvm-strip \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        READELF=llvm-readelf \
        HOSTCC=clang \
        HOSTCXX=clang++ \
        HOSTAR=llvm-ar \
        HOSTLD=ld.lld \
        LLVM_NM=llvm-nm \
        LD=ld.lld \
        NM=llvm-nm \
        LLVM=1 \
        LLVM_IAS=1
}

miui() {
    echo -e "${LYW}Aplicando ajustes para MIUI (brillo y resolución del panel)...${NC}"
    sed -i 's/<70>/<695>/g'   $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
    sed -i 's/<154>/<1546>/g' $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
    sed -i 's/<70>/<695>/g'   $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi
    sed -i 's/<154>/<1546>/g' $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi
}


create_images() {
    echo -e "${LGR}Creando imágenes DTBO y DTB...${NC}"
    
    mkdir -p "${anykernel_dir}"
    
    local dtbo_input="${objdir}/arch/arm64/boot/dts/qcom/vayu-sm8150-overlay.dtbo"
    
    if [ -f "$dtbo_input" ]; then
        # Imagen DTBO
        python3 "$MKDTBOIMG" create "${DTBO_IMG}" --page_size=4096 "$dtbo_input"
        python3 "$MKDTBOIMG" create "${anykernel_dir}/dtbo-miui.img" --page_size=4096 "$dtbo_input"
        
        # Concatenar y generar dtb.img
        if find "${objdir}/arch/arm64/boot/dts/qcom" -name 'sm8150-v2*.dtb' | grep -q .; then
            find "${objdir}/arch/arm64/boot/dts/qcom" -name 'sm8150-v2*.dtb' -exec cat {} + > "${anykernel_dir}/dtb.img"
        else
            echo -e "${LYW}Advertencia: No se encontraron archivos sm8150-v2*.dtb${NC}"
        fi
    else
        echo -e "${RED}Error: No se encontró vayu-sm8150-overlay.dtbo${NC}"
        exit 1
    fi
}


restore() {
    echo -e "${LYW}Restaurando archivos de panel modificados...${NC}"
    git restore $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
    git restore $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi
}


finalize_build() {
    cd "${objdir}"
    
    if [[ -f "${ZIMAGE}" && -f "${DTBO_IMG}" ]]; then
        echo -e "${LGR}Build successful!${NC}"

        cp -v "${ZIMAGE}" "${DTBO_IMG}" "${anykernel_dir}/"
        
        [ -f "${anykernel_dir}/dtb.img" ] && cp -v "${anykernel_dir}/dtb.img" "${anykernel_dir}/"

        mkdir -p "$output_dir"
        (cd "$anykernel_dir" && zip -r9 "${output_dir}/${zip_name}" ./*)
    
        echo -e "${LGR}Kernel ZIP: ${output_dir}/${zip_name}${NC}"
    else
        echo -e "${RED}Build failed! Missing:${NC}"
        [ -f "${ZIMAGE}" ] || echo -e "${RED}- ${ZIMAGE}${NC}"
        [ -f "${DTBO_IMG}" ] || echo -e "${RED}- ${DTBO_IMG}${NC}"
        exit 1
    fi
}

echo -e "${LYW}Cleaning up space...${NC}"
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache 2>/dev/null

clone_tools
make_defconfig
compile
create_images
finalize_build

cd "${kernel_dir}"
