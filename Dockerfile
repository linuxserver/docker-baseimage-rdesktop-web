# guacamole builder
FROM ghcr.io/linuxserver/baseimage-arch:latest as guacbuilder

ARG GUACD_VERSION=1.1.0

RUN \
  echo "**** install build deps ****" && \
  pacman -Sy --noconfirm \
    base-devel \
    freerdp \
    git \
    libpulse \
    libvorbis \
    pango \
    wget && \
  echo "**** prep abc user ****" && \
  usermod -s /bin/bash abc && \
  echo '%abc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/abc && \
  mkdir /buildout

USER abc:abc
RUN \
  echo "**** build AUR packages ****" && \
  cd /tmp && \
  AUR_PACKAGES="\
    uuid" && \
  for PACKAGE in ${AUR_PACKAGES}; do \
    sudo chmod 777 -R /root && \
    git clone https://aur.archlinux.org/${PACKAGE}.git && \
    cd ${PACKAGE} && \
    makepkg -sAci --skipinteg --noconfirm && \
    sudo -u root tar xf *pkg.tar.zst -C /buildout && \
    cd /tmp ;\
  done

USER root:root      
RUN \
  echo "**** compile guacamole ****" && \
  mkdir /tmp/guac && \
  cd /tmp/guac && \
  wget \
    http://apache.org/dyn/closer.cgi?action=download\&filename=guacamole/${GUACD_VERSION}/source/guacamole-server-${GUACD_VERSION}.tar.gz \
    -O guac.tar.gz && \
  tar -xf guac.tar.gz && \
  cd guacamole-server-${GUACD_VERSION} && \
  ./configure \
    CPPFLAGS="-Wno-deprecated-declarations" \
    --disable-guacenc \
    --disable-guaclog \
    --prefix=/usr \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --localstatedir=/var \
    --enable-static \
    --with-libavcodec \
    --with-libavutil \
    --with-libswscale \
    --with-ssl \
    --without-winsock \
    --with-vorbis \
    --with-pulse \
    --without-pango \
    --without-terminal \
    --without-vnc \
    --with-rdp \
    --without-ssh \
    --without-telnet \
    --with-webp \
    --without-websockets && \
  make && \
  make DESTDIR=/buildout install && \
  mv /buildout/usr/sbin/guacd /buildout/usr/bin && \
  rm -Rf /buildout/usr/sbin/

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-arch:latest as nodebuilder
ARG GCLIENT_RELEASE

RUN \
  echo "**** install build deps ****" && \
  pacman -Sy --noconfirm \
    base-devel \
    curl \
    nodejs \
    npm \
    pam \
    python
	

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
FROM ghcr.io/linuxserver/baseimage-rdesktop:arch

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
  pacman -Sy --noconfirm --needed \
    base-devel \
    freerdp \
    git \
    nodejs \
    noto-fonts \
    openbox \
    pavucontrol \
    websocat \
    xorg-xmessage && \
  echo "**** build AUR packages ****" && \
  cd /tmp && \
  AUR_PACKAGES="\
    dbus-x11" && \
  pacman -Rns --noconfirm -dd dbus && \
  for PACKAGE in ${AUR_PACKAGES}; do \
    git clone https://aur.archlinux.org/${PACKAGE}.git && \
    chown -R abc:abc ${PACKAGE} && \
    cd ${PACKAGE} && \
    sudo -u abc makepkg -sAci --skipinteg --noconfirm --needed && \
    cd /tmp ;\
  done && \
  echo "**** openbox tweaks ****" && \
  sed -i \
    's/NLIMC/NLMC/g' \
    /etc/xdg/openbox/rc.xml && \
  echo "**** cleanup ****" && \
  pacman -Rsn --noconfirm \
    gcc \
    git \
    $(pacman -Qdtq) || : && \
  rm -rf \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
