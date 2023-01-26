# Get and install Easy noVNC.
FROM golang:bullseye AS easy-novnc-build
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /src
RUN go mod init build && \
    go get github.com/geek1011/easy-novnc@v1.1.0 && \
    go build -o /bin/easy-novnc github.com/geek1011/easy-novnc

# Get TigerVNC and Supervisor for isolating the container.
FROM ubuntu:22.04 as baseimage2
ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y --no-install-recommends --allow-unauthenticated \
        lxde gtk2-engines-murrine gnome-themes-standard gtk2-engines-pixbuf gtk2-engines-murrine arc-theme \
        freeglut3 libgtk2.0-dev libwxgtk3.0-gtk3-dev libwx-perl libxmu-dev libgl1-mesa-glx libgl1-mesa-dri  \
        xdg-utils locales locales-all pcmanfm jq curl git qtbase5-dev \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN apt update && apt install python3-pip gcc-12 python3-dev git dh-autoreconf libx11-dev libx11-xcb-dev libarcus-dev libfontenc-dev libice-dev libsm-dev libxau-dev libxaw7-dev libxcomposite-dev libxcursor-dev libxdamage-dev libxdmcp-dev libxext-dev libxfixes-dev libxi-dev libxinerama-dev libxkbfile-dev libxmu-dev libxmuu-dev libxpm-dev libxrandr-dev libxrender-dev libxres-dev libxss-dev libxt-dev libxtst-dev libxv-dev libxvmc-dev libxxf86vm-dev xtrans-dev libxcb-render0-dev libxcb-render-util0-dev libxcb-xkb-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev libxcb-randr0-dev libxcb-shape0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-xinerama0-dev xkb-data libxcb-dri3-dev uuid-dev libxcb-util-dev -y && rm -rf /var/lib/apt/lists/*
RUN pip install --upgrade pip
RUN pip install conan==1.56 ninja cmake sip setuptools --upgrade
ADD ./requirements.txt requirements.txt
RUN pip3 install -r requirements.txt

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends tigervnc-standalone-server supervisor gosu && \
    rm -rf /var/lib/apt/lists && \
    mkdir -p /usr/share/desktop-directories

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends lxterminal nano wget openssh-client rsync ca-certificates xdg-utils htop tar xzip gzip bzip2 zip unzip && \
    rm -rf /var/lib/apt/lists

RUN apt update && apt install -y --no-install-recommends --allow-unauthenticated \
        lxde gtk2-engines-murrine gnome-themes-standard gtk2-engines-pixbuf gtk2-engines-murrine arc-theme \
        freeglut3 libgtk2.0-dev libwxgtk3.0-gtk3-dev libwx-perl libxmu-dev libgl1-mesa-glx libgl1-mesa-dri  \
        xdg-utils locales locales-all pcmanfm jq curl qtbase5-dev \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN adduser cura \
  && chpasswd << "cura:CuraCura"  \
  && mkdir -p /cura \
  && mkdir -p /prints/ \
  && chown -R cura:cura /cura /home/cura/ /prints/ \
  && mkdir -p /home/cura/.config/ \
  && chmod +x /cura \
  # We can now set the Download directory for Firefox and other browsers. 
  # We can also add /prints/ to the file explorer bookmarks for easy access.
  && echo "XDG_DOWNLOAD_DIR=\"/prints/\"" >> /home/cura/.config/user-dirs.dirs \
  && echo "file:///prints prints" >> /home/cura/.gtk-bookmarks 

FROM baseimage2 as curabuilder

USER cura
RUN conan config install https://github.com/ultimaker/conan-config.git
RUN conan profile new default --detect --force

RUN git clone https://github.com/Ultimaker/Cura.git /home/cura/cura
WORKDIR /home/cura/cura
RUN git checkout 62fa625dd61e4bf89d877e5890c1c37bbe589cf9

RUN conan install . --build=missing -o cura:devtools=False -g VirtualPythonEnv
RUN sed -i 's/QT_QPA_PLATFORMTHEME=xdgdesktopportal/QT_QPA_PLATFORMTHEME=gtk3/' /home/cura/cura/conanfile.py
COPY --from=easy-novnc-build /bin/easy-novnc /usr/local/bin/
COPY menu.xml /etc/xdg/openbox/
COPY supervisord.conf /etc/
EXPOSE 8080

#COPY --from=curabuilder /cura/dist/cura_app /cura_app

VOLUME /home/cura/
VOLUME /prints/

WORKDIR /home/cura

# It's time! Let's get to work! We use /home/cura/ as a bindable volume for Cura and its configurations. We use /prints/ to provide a location for STLs and GCODE files.
USER root
RUN chown -R cura:cura /home/cura/ /prints/ /dev/stdout
RUN chmod 777 -R /home/cura/cura
USER cura
ENV QT_QPA_PLATFORMTHEME=gtk3
CMD ["supervisord"]
