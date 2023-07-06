FROM python:3.9-alpine3.18

ENV HY_VERSION 0.27.0
ENV HYRULE_VERSION 0.4.0

RUN pip install --no-cache-dir "hy == $HY_VERSION" "hyrule == $HYRULE_VERSION"

CMD ["hy"]
