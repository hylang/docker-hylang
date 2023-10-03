FROM python:3.12-slim-bullseye

ENV HY_VERSION 0.27.0
ENV HYRULE_VERSION 0.4.0

RUN pip install --no-cache-dir "hy == $HY_VERSION" "hyrule == $HYRULE_VERSION"

CMD ["hy"]
