#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM python:3.15-rc-alpine3.24

ENV HY_VERSION 1.3.0
ENV HYRULE_VERSION 1.1.0

RUN pip install --no-cache-dir "hy == $HY_VERSION" "hyrule == $HYRULE_VERSION"

CMD ["hy"]
