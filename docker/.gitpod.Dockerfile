##
## Install system packages
##
FROM gitpod/workspace-full as prepare

USER gitpod
# Only copy build, for package information needed for the system package install.
# configure.ac is needed because build/sage_bootstrap uses it to recognize SAGE_ROOT.
COPY --chown=gitpod:gitpod ./configure.ac ./configure.ac
COPY --chown=gitpod:gitpod ./build ./build

# Install system packages
RUN sudo apt-get update
RUN sudo apt-get install -y --no-install-recommends \
        $(build/bin/sage-get-system-packages debian \
            _bootstrap \
            $(PATH=build/bin:$PATH build/bin/sage-package list \
                 --has-file=spkg-configure.m4 :standard: \
              | grep -E -v "pari|tox|flint" ))
    # As of 2021-12, gitpod uses ubuntu-focal. To save space, we filter out some packages that are
    # too old and will be rejected by our configure script.
    # We do not install pari, as it is not recognized even if installed
    # We do not install tox, since it pulls in javascript-common which does not install for some reason

## Homebrew has some more up-to-date packages (but sage is not yet able to find them)
### RUN brew update && brew upgrade
### RUN brew install arb flint fplll tox
### We do not install ecl from brew, since this breaks the build of maxima
### Installing pari from brew doesn't work as gitpod gp executable is then hidden by pari/gp
### RUN brew install pari pari-elldata pari-galdata pari-galpol pari-seadata
### Give prio to brew over other system packages
### ENV PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"

##
## Prebuild non-Python packages that have no (working) system-installed package 
##
FROM prepare as prebuild
USER gitpod
### We cannot copy everything due to https://github.com/gitpod-io/gitpod/issues/7157
### COPY --chown=gitpod:gitpod . .
### Thus only selectively copy the files we need
COPY --chown=gitpod:gitpod ./bootstrap ./bootstrap
COPY --chown=gitpod:gitpod ./src/doc/bootstrap ./src/doc/bootstrap
COPY --chown=gitpod:gitpod ./src/bin ./src/bin
COPY --chown=gitpod:gitpod ./m4 ./m4
COPY --chown=gitpod:gitpod ./pkgs ./pkgs
COPY --chown=gitpod:gitpod ./sage ./sage
COPY --chown=gitpod:gitpod ./Makefile ./Makefile
RUN ./bootstrap
RUN mkdir -p sage-local && sudo ln -s /home/gitpod/sage-local /workspace/sage-local
RUN ./configure --prefix=/workspace/sage-local --with-sage-venv
### V=0 since otherwise we would reach log limit
### Gitpod also puts a timeout at 1h, so we cannot install everything here with `make build-local`
RUN MAKE='make -j8' make V=0 \
    arb ecl flint cddlib eclib fplll giac gengetopt singular \
    pari pari_elldata pari_galdata pari_galpol pari_seadata

##
## Build final image
##
FROM prepare
# Reuse the prebuild packages
COPY --from=prebuild /home/gitpod/sage-local /home/gitpod/sage-local

# Configure 
## Gitpod sets PIP_USER: yes by default, which leads to problems during build (e.g pip not being installed in the venv)
RUN unset PIP_USER
## Gitpod installs pyenv by default, and sage's pip install targets the pyenv python for some reason
RUN pyenv global system
