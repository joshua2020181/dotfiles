# dotlab/Dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential locales ca-certificates sudo && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ARG DISPLAY
ENV DISPLAY=${DISPLAY:-:0}

ARG USERNAME=joshua
ARG UID=1000
ARG GID=1000

RUN set -eux; \
    olduser="$(getent passwd 1000 | cut -d: -f1)"; \
    oldgroup="$(getent group 1000 | cut -d: -f1)"; \
    usermod  -l joshua "${olduser}"; \
    groupmod -n joshua "${oldgroup}"; \
    usermod  -d /home/joshua -m joshua; \
    echo "joshua ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/joshua; \
    chmod 0440 /etc/sudoers.d/joshua

USER ${USERNAME}
WORKDIR /home/${USERNAME}

COPY --chmod=755 setup_scripts/install_basics.sh /home/${USERNAME}/install_basics.sh
COPY --chmod=755 setup_scripts/install_custom.sh /home/${USERNAME}/install_custom.sh
COPY --chmod=755 setup_scripts/nvim_docker.sh /home/${USERNAME}/nvim_docker.sh

RUN ./install_basics.sh && rm install_basics.sh
RUN ./install_custom.sh && rm install_custom.sh
RUN ./nvim_docker.sh && rm nvim_docker.sh

CMD ["zsh", "-l"]
