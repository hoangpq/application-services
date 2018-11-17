# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

FROM ubuntu:bionic-20181018

MAINTAINER Nick Alexander "nalexander@mozilla.com"

#----------------------------------------------------------------------------------------------------------------------
#-- Configuration -----------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------

ENV ANDROID_BUILD_TOOLS "28.0.3"
ENV ANDROID_SDK_VERSION "3859397"
ENV ANDROID_PLATFORM_VERSION "28"

ENV LANG en_US.UTF-8

# Do not use fancy output on taskcluster
ENV TERM dumb

ENV GRADLE_OPTS -Xmx4096m -Dorg.gradle.daemon=false

# Used to detect in scripts whether we are running on taskcluster
ENV CI_TASKCLUSTER true

ENV \
    #
    # Some APT packages like 'tzdata' wait for user input on install by default.
    # https://stackoverflow.com/questions/44331836/apt-get-install-tzdata-noninteractive
    DEBIAN_FRONTEND=noninteractive

#----------------------------------------------------------------------------------------------------------------------
#-- System ------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------

RUN apt-get update -qq \
    # We need to install tzdata before all of the other packages. Otherwise it will show an interactive dialog that
    # we cannot navigate while building the Docker image.
    && apt-get install -qy tzdata \
    && apt-get install -qy --no-install-recommends openjdk-8-jdk \
                          wget \
                          expect \
                          git \
                          curl \
                          python \
                          python-pip \
                          locales \
                          unzip \
    && apt-get clean

RUN pip install --upgrade pip
RUN pip install 'taskcluster>=4,<5'

RUN locale-gen en_US.UTF-8

#----------------------------------------------------------------------------------------------------------------------
#-- Android -----------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------

RUN mkdir -p /build/android-sdk
WORKDIR /build

ENV ANDROID_HOME /build/android-sdk
ENV ANDROID_SDK_HOME /build/android-sdk
ENV PATH ${PATH}:${ANDROID_SDK_HOME}/tools:${ANDROID_SDK_HOME}/tools/bin:${ANDROID_SDK_HOME}/platform-tools:/opt/tools:${ANDROID_SDK_HOME}/build-tools/${ANDROID_BUILD_TOOLS}

RUN curl -L https://dl.google.com/android/repository/sdk-tools-linux-${ANDROID_SDK_VERSION}.zip > sdk.zip \
    && unzip -q sdk.zip -d ${ANDROID_SDK_HOME} \
    && rm sdk.zip \
    && mkdir -p /build/android-sdk/.android/ \
    && touch /build/android-sdk/.android/repositories.cfg \
    && yes | sdkmanager --licenses \
    && sdkmanager --verbose "platform-tools" \
        "platforms;android-${ANDROID_PLATFORM_VERSION}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "extras;android;m2repository" \
        "extras;google;m2repository"

#----------------------------------------------------------------------------------------------------------------------
#-- Configuration -----------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------

# r15c agrees with mozilla-central and, critically, supports the --deprecated-headers flag needed to
# build OpenSSL.
ENV ANDROID_NDK_VERSION "r15c"

#----------------------------------------------------------------------------------------------------------------------
#-- Android NDK -------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------------

ENV ANDROID_NDK_HOME /build/android-ndk

RUN curl -L https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux-x86_64.zip > ndk.zip \
	&& unzip -q ndk.zip -d /build \
	&& rm ndk.zip \
  && mv /build/android-ndk-${ANDROID_NDK_VERSION} ${ANDROID_NDK_HOME}

ENV ANDROID_NDK_TOOLCHAIN_DIR /build/android-ndk-toolchain
ENV ANDROID_NDK_API_VERSION 21

RUN set -eux; \
    python "$ANDROID_NDK_HOME/build/tools/make_standalone_toolchain.py" --arch="arm"   --api="$ANDROID_NDK_API_VERSION" --install-dir="$ANDROID_NDK_TOOLCHAIN_DIR/arm-$ANDROID_NDK_API_VERSION" --deprecated-headers --force; \
    python "$ANDROID_NDK_HOME/build/tools/make_standalone_toolchain.py" --arch="arm64" --api="$ANDROID_NDK_API_VERSION" --install-dir="$ANDROID_NDK_TOOLCHAIN_DIR/arm64-$ANDROID_NDK_API_VERSION" --deprecated-headers --force; \
    python "$ANDROID_NDK_HOME/build/tools/make_standalone_toolchain.py" --arch="x86"   --api="$ANDROID_NDK_API_VERSION" --install-dir="$ANDROID_NDK_TOOLCHAIN_DIR/x86-$ANDROID_NDK_API_VERSION" --deprecated-headers --force

#----------------------------------------------------------------------------------------------------------------------
#-- Rust (cribbed from https://github.com/rust-lang-nursery/docker-rust/blob/ced83778ec6fea7f63091a484946f95eac0ee611/1.27.1/stretch/Dockerfile)
#-- Rust is after the Android NDK since Rust rolls forward more frequently.
#----------------------------------------------------------------------------------------------------------------------

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH \
    RUST_VERSION=1.30.1

RUN set -eux; \
    rustArch='x86_64-unknown-linux-gnu'; rustupSha256='ab125d9b12bf0f3f7e7ad98e826035fa1ae3dbe6ba8b78be4c82f9cde00bc59f'; \
    url="https://static.rust-lang.org/rustup/archive/1.14.0/${rustArch}/rustup-init"; \
    wget "$url"; \
    echo "${rustupSha256} *rustup-init" | sha256sum -c -; \
    chmod +x rustup-init; \
    ./rustup-init -y --no-modify-path --default-toolchain $RUST_VERSION; \
    rm rustup-init; \
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME; \
    rustup --version; \
    cargo --version; \
    rustc --version; \
    rustup target add i686-linux-android; \
    rustup target add armv7-linux-androideabi; \
    rustup target add aarch64-linux-android
