#!/bin/sh

export PATH="$PATH:/opt/local/bin:/opt/local/sbin:/opt/homebrew/bin/"

path="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )/$(basename "${BASH_SOURCE[0]}")"
cd "$TARGET_NAME"; pwd

env=$(env|sort|grep -v 'LLBUILD_BUILD_ID=\|LLBUILD_LANE_ID=\|LLBUILD_TASK_ID=\|Apple_PubSub_Socket_Render=\|DISPLAY=\|SHLVL=\|SSH_AUTH_SOCK=\|SECURITYSESSIONID=')
hash="$(git describe --always --tags --dirty) $(md5 -q "$path")-$(md5 -qs "$env")"

set -e; set -o xtrace

cmake_dir="$TARGET_TEMP_DIR/CMake"
install_dir="$TARGET_TEMP_DIR/Install"

mkdir -p "$cmake_dir"; cd "$cmake_dir"
if [ -e Makefile -a -f .cmakehash ] && [ "$(cat '.cmakehash')" = "$hash" ]; then
    exit 0
fi

if [ -e ".cmakeenv" ]; then
echo "Rebuilding.."
cat '.cmakeenv'
echo "$env"
fi


command -v cmake >/dev/null 2>&1 || { echo >&2 "error: building $TARGET_NAME requires CMake. Please install CMake. Aborting."; exit 1; }
command -v pkg-config >/dev/null 2>&1 || { echo >&2 "error: building $TARGET_NAME requires pkg-config. Please install pkg-config. Aborting."; exit 1; }
command -v git-lfs >/dev/null 2>&1 || { echo >&2 "error: building $TARGET_NAME requires git-lfs. Please install git-lfs. Aborting."; exit 1; }

mv "$cmake_dir" "$cmake_dir.tmp"
[ -d "$install_dir" ] && mv "$install_dir" "$install_dir.tmp"
rm -Rf "$cmake_dir.tmp" "$install_dir.tmp"
mkdir -p "$cmake_dir"; cd "$cmake_dir"

args=("$PROJECT_DIR/$TARGET_NAME") # -G Xcode
cxxfs=( -w -fvisibility=default )
args+=(-DVTK_USE_X:BOOL=OFF)
args+=(-DVTK_USE_COCOA:BOOL=ON)
#args+=(-DVTK_USE_64BITS_IDS=ON) 
args+=(-DBUILD_DOCUMENTATION=OFF)
args+=(-DBUILD_EXAMPLES=OFF)
args+=(-DBUILD_SHARED_LIBS=OFF)
args+=(-DBUILD_TESTING=OFF)
args+=(-DCMAKE_POLICY_VERSION_MINIMUM=3.5)
args+=(-DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET")
args+=(-DCMAKE_OSX_ARCHITECTURES="$ARCHS")

args+=(-DVTK_USE_SYSTEM_ZLIB:BOOL=ON)
# Sachmet: das mitgelieferte libpng haelt TARGET_OS_MAC (Xcode-26-SDK) fuer Classic Mac OS und sucht <fp.h>; statisches Homebrew-libpng
args+=(-DVTK_USE_SYSTEM_PNG:BOOL=ON)
args+=(-DPNG_LIBRARY=/opt/homebrew/lib/libpng16.a)
# Sachmet: /opt/homebrew/include darf NICHT als Ganzes in den Suchpfad, sonst deckt Homebrews tiffconf.h die generierte
# von vtktiff zu (unknown type name TIFF_INT8_T). libpng16/ enthaelt nur die drei png-Header.
args+=(-DPNG_PNG_INCLUDE_DIR=/opt/homebrew/include/libpng16)
args+=(-DVTK_USE_SYSTEM_EXPAT=ON)
args+=(-DVTK_USE_SYSTEM_LIBXML2=ON)

# args+=(-DCMAKE_VERBOSE_MAKEFILE:BOOL=ON)

[ "$CONFIGURATION" == 'Release' ] && args+=( -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS_RELEASE=-O3 )

args+=(-DVTK_Group_StandAlone=OFF -DVTK_Group_Rendering=OFF) # disable the default groups
args+=(-DModule_vtkIOImage=ON)
args+=(-DModule_vtkFiltersGeneral=ON)
args+=(-DModule_vtkImagingMorphological=ON)
args+=(-DModule_vtkImagingStencil=ON)
args+=(-DModule_vtkRenderingOpenGL2=ON)
args+=(-DModule_vtkRenderingVolumeOpenGL2=ON)
args+=(-DModule_vtkRenderingAnnotation=ON)
args+=(-DModule_vtkInteractionWidgets=ON)
args+=(-DModule_vtkIOGeometry=ON)
args+=(-DModule_vtkIOExport=ON)
args+=(-DModule_vtkFiltersTexture=ON)
args+=(-DModule_vtktiff=ON)

args+=(-DCMAKE_INSTALL_PREFIX="$install_dir")
args+=(-DVTK_INSTALL_INCLUDE_DIR="include")

args+=(-DCMAKE_IGNORE_PATH="/opt/local/include;/opt/local/lib")

if [ ! -z "$CLANG_CXX_LIBRARY" ] && [ "$CLANG_CXX_LIBRARY" != 'compiler-default' ]; then
#    args+=(-DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="$CLANG_CXX_LIBRARY")
    cxxfs+=(-stdlib="$CLANG_CXX_LIBRARY")
fi
if [ ! -z "$CLANG_CXX_LANGUAGE_STANDARD" ]; then
#    args+=(-DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="$CLANG_CXX_LANGUAGE_STANDARD")
    cxxstd="$CLANG_CXX_LANGUAGE_STANDARD"
    if [ "$cxxstd" = "c++0x" ]; then
        cxxstd="c++11"
    fi
    cxxfs+=(-std="$cxxstd")
fi

# Remove any lingering -std=c++0x from toolchain defaults
for i in "${!cxxfs[@]}"; do
    if [ "${cxxfs[$i]}" = "-std=c++0x" ]; then
        unset 'cxxfs[$i]'
    fi
done
cxxfs+=( -std=c++11 )

if [ ${#cxxfs[@]} -ne 0 ]; then
    cxxfss="${cxxfs[@]}"
    args+=(-DCMAKE_CXX_FLAGS="$cxxfss")
fi

# Force a modern C++ standard for VTK/eigen compatibility
args+=(-DCMAKE_CXX_STANDARD=11)
args+=(-DCMAKE_CXX_STANDARD_REQUIRED=ON)

# Sachmet: Eigen 3.3.4 im VTK-Submodul scheitert mit clang 21 (Transpositions.h:387 "no member named derived");
# Korrektur wie in Eigen 3.3.7: trt statt trt.derived(). Idempotent, direkt im Submodul-Arbeitsbaum.
eig="$PROJECT_DIR/$TARGET_NAME/ThirdParty/eigen/vtkeigen/eigen/src/Core/Transpositions.h"
grep -q "matrix.derived(), trt.derived())" "$eig" && sed -i "" "s/matrix.derived(), trt.derived())/matrix.derived(), trt)/" "$eig"
cmake "${args[@]}"

echo "$hash" > "$cmake_dir/.cmakehash"
echo "$env" > "$cmake_dir/.cmakeenv"

exit 0
