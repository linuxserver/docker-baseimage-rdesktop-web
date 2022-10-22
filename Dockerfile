# guacamole builder
FROM ghcr.io/linuxserver/baseimage-alpine:3.16 as guacbuilder

ARG GUACD_VERSION=1.1.0

RUN \
  echo "**** install build deps ****" && \
  apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    ossp-uuid-dev && \
  apk add --no-cache \
    alpine-sdk \
    autoconf \
    automake \
    cairo-dev \
    cunit-dev \
    ffmpeg-dev \
    freerdp-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libssh2-dev \
    libvncserver-dev \
    libvorbis-dev \
    libwebp-dev \
    libwebsockets-dev \
    openssl-dev \
    pango-dev \
    perl \
    pulseaudio-dev

RUN \
  echo "**** compile guacamole ****" && \
  mkdir /buildout && \
  mkdir /tmp/guac && \
  cd /tmp/guac && \
  wget \
    http://apache.org/dyn/closer.cgi?action=download\&filename=guacamole/${GUACD_VERSION}/source/guacamole-server-${GUACD_VERSION}.tar.gz \
    -O guac.tar.gz && \
  tar -xf guac.tar.gz && \
  cd guacamole-server-${GUACD_VERSION} && \
  CFLAGS="$CFLAGS -Wno-error=deprecated-declarations -Wno-error=discarded-qualifiers" \
  ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --disable-static \
    --with-libavcodec \
    --with-libavutil \
    --with-libswscale \
    --with-ssl \
    --without-winsock \
    --with-vorbis \
    --with-pulse \
    --with-pango \
    --with-terminal \
    --with-vnc \
    --with-rdp \
    --with-ssh \
    --without-telnet \
    --with-webp \
    --with-websockets && \
  make && \
  make DESTDIR=/buildout install

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-alpine:3.16 as nodebuilder
ARG GCLIENT_RELEASE

RUN \
  echo "**** install build deps ****" && \
  apk add --no-cache \
    curl \
    g++ \
    gcc \
    linux-pam-dev \
    make \
    nodejs \
    npm \
    python3 
	

RUN \
  echo "**** grab source ****" && \
  mkdir -p /gclient && \
  if [ -z ${GCLIENT_RELEASE+x} ]; then \
    GCLIENT_RELEASE=$(curl -sX GET "https://api.github.com/repos/linuxserver/gclient/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
  /tmp/gclient.tar.gz -L \
    "https://github.com/linuxserver/gclient/archive/${GCLIENT_RELEASE}.tar.gz" && \
  tar xf \
  /tmp/gclient.tar.gz -C \
    /gclient/ --strip-components=1

RUN \
  echo "**** install node modules ****" && \
  cd /gclient && \
  npm install

# runtime stage
FROM ghcr.io/linuxserver/baseimage-rdesktop:alpine

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Copy build outputs
COPY --from=nodebuilder /gclient /gclient
COPY --from=guacbuilder /buildout /

RUN \ 
  echo "**** install packages ****" && \
  apk add --no-cache \
    ca-certificates \
    cairo \
    cunit \
    ffmpeg \
    font-noto \
    freerdp \
    freerdp-libs \
    libjpeg-turbo \
    libpng \
    libssh2 \
    libvncserver \
    libvorbis \
    libwebp \
    libwebsockets \
    nodejs \
    openbox \
    openssl \
    pango \
    perl \
    websocat && \
  apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    ossp-uuid && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    's/NLIMC/NLMC/g' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000

VOLUME /config
