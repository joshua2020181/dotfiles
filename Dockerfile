# dotlab/Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential locales ca-certificates sudo && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ARG DISPLAY
ENV DISPLAY=${DISPLAY:-:0}

ARG USER=joshua
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} ${USER} && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USER} && \
    usermod -aG sudo ${USER} && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER}

USER ${USER}
WORKDIR /home/${USER}

COPY --chmod=755 setup_scripts/install_basics.sh /home/${USER}/install_basics.sh
COPY --chmod=755 setup_scripts/install_custom.sh /home/${USER}/install_custom.sh
COPY --chmod=755 setup_scripts/nvim_docker.sh /home/${USER}/nvim_docker.sh

USER ${USER}
WORKDIR /home/${USER}

RUN ./install_basics.sh && rm install_basics.sh
RUN ./install_custom.sh && rm install_custom.sh
RUN ./nvim_docker.sh && rm nvim_docker.sh

CMD ["zsh", "-l"]
