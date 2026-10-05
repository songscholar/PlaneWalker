FROM public.ecr.aws/docker/library/debian@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

RUN apt-get update
RUN apt-get install --yes --no-install-recommends wine64 xvfb xauth fonts-dejavu-core

ENV WINEDEBUG=-all
ENV WINEPREFIX=/tmp/planewalker-wine

ENTRYPOINT ["/usr/bin/xvfb-run", "--auto-servernum", "/usr/lib/wine/wine64"]
