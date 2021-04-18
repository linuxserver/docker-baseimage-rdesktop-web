FROM ghcr.io/linuxserver/baseimage-ubuntu:focal as builder

ARG GUACD_VERSION=1.1.0

COPY /buildroot /

RUN \
 echo "**** install build deps ****" && \
 apt-get update && \
 apt-get install -qy --no-install-recommends \
	autoconf \
	automake \
	checkinstall \
	freerdp2-dev \
	g++ \
	gcc \
	git \
	libavcodec-dev \
	libavutil-dev \
	libcairo2-dev \
	libjpeg-turbo8-dev \
	libogg-dev \
	libossp-uuid-dev \
	libpulse-dev \
	libssl-dev \
	libswscale-dev \
	libtool \
	libvorbis-dev \
	libwebsockets-dev \
	libwebp-dev \
	make

RUN \
 echo "**** prep build ****" && \
 mkdir /tmp/guacd && \
 git clone https://github.com/apache/guacamole-server.git /tmp/guacd && \
 echo "**** build guacd ****" && \
 cd /tmp/guacd && \
 git checkout ${GUACD_VERSION} && \
 autoreconf -fi && \
 ./configure --prefix=/usr && \
 make -j 2 && \
 mkdir -p /tmp/out && \
 /usr/bin/list-dependencies.sh \
	"/tmp/guacd/src/guacd/.libs/guacd" \
	$(find /tmp/guacd | grep "so$") \
	> /tmp/out/DEPENDENCIES && \
 PREFIX=/usr checkinstall \
	-y \
	-D \
	--nodoc \
	--pkgname guacd \
	--pkgversion "${GUACD_VERSION}" \
	--pakdir /tmp \
	--exclude "/usr/share/man","/usr/include","/etc" && \
 mkdir -p /tmp/out && \
 mv \
	/tmp/guacd_${GUACD_VERSION}-*.deb \
	/tmp/out/guacd_${GUACD_VERSION}.deb

# nodejs builder
FROM ghcr.io/linuxserver/baseimage-ubuntu:focal as nodebuilder
ARG GCLIENT_RELEASE

RUN \
 echo "**** install build deps ****" && \
 apt-get update && \
 apt-get install -y \
	gnupg && \
 curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
 echo 'deb https://deb.nodesource.com/node_12.x focal main' \
	> /etc/apt/sources.list.d/nodesource.list && \
 apt-get update && \
 apt-get install -y \
	nodejs 

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
FROM ghcr.io/linuxserver/baseimage-rdesktop:focal

# set version label
ARG BUILD_DATE
ARG VERSION
ARG GUACD_VERSION=1.1.0
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Copy build outputs
COPY --from=builder /tmp/out /tmp/out
COPY --from=nodebuilder /gclient /gclient

RUN \
 echo "**** install guacd ****" && \
 dpkg --path-include=/usr/share/doc/${PKG_NAME}/* \
        -i /tmp/out/guacd_${GUACD_VERSION}.deb && \
 echo "**** install packages ****" && \
 apt-get update && \
 apt-get install -y \
	gnupg && \
 curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - && \
 echo 'deb https://deb.nodesource.com/node_12.x focal main' \
        > /etc/apt/sources.list.d/nodesource.list && \
 apt-get update && \
 DEBIAN_FRONTEND=noninteractive \
 apt-get install --no-install-recommends -y \
	ca-certificates \
	libfreerdp2-2 \
	libfreerdp-client2-2 \
	libossp-uuid16 \
	nodejs \
	obconf \
	openbox \
	python \
	xterm && \
 apt-get install -qy --no-install-recommends \
	$(cat /tmp/out/DEPENDENCIES) && \
 echo "**** grab websocat ****" && \
 WEBSOCAT_RELEASE=$(curl -sX GET "https://api.github.com/repos/vi/websocat/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]'); \
 curl -o \
 /usr/bin/websocat -L \
	"https://github.com/vi/websocat/releases/download/${WEBSOCAT_RELEASE}/websocat_nossl_amd64-linux-static" && \
 chmod +x /usr/bin/websocat && \
 echo "**** cleanup ****" && \
 apt-get autoclean && \
 rm -rf \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 3000
VOLUME /config
