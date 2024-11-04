###################
# STAGE 1: builder
###################

FROM node:18-bullseye as builder

ARG MB_EDITION=oss
ARG VERSION=1

WORKDIR /home/node

# Install required packages
RUN apt-get update && apt-get upgrade -y && apt-get install openjdk-11-jdk curl git -y \
    && curl -O https://download.clojure.org/install/linux-install-1.11.1.1262.sh \
    && chmod +x linux-install-1.11.1.1262.sh \
    && ./linux-install-1.11.1.1262.sh

# Copy only package.json and yarn.lock to leverage Docker layer caching for dependencies
COPY package.json yarn.lock ./

# Install frontend dependencies
RUN yarn --frozen-lockfile

# Copy the rest of the project files
COPY . .

# Version is pulled from git, but git doesn't trust the directory due to different owners
RUN git config --global --add safe.directory /home/node

# Run build command
RUN INTERACTIVE=false CI=true MB_EDITION=$MB_EDITION bin/build.sh :version ${VERSION}

###################
# STAGE 2: runner
###################

FROM --platform=linux/amd64 eclipse-temurin:11-jre-alpine as runner

ENV FC_LANG en-US LC_CTYPE en_US.UTF-8

# dependencies
RUN apk add -U bash fontconfig curl font-noto font-noto-arabic font-noto-hebrew font-noto-cjk java-cacerts && \
    apk upgrade && \
    rm -rf /var/cache/apk/* && \
    mkdir -p /app/certs && \
    curl https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /app/certs/rds-combined-ca-bundle.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias aws-rds -file /app/certs/rds-combined-ca-bundle.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    curl https://cacerts.digicert.com/DigiCertGlobalRootG2.crt.pem -o /app/certs/DigiCertGlobalRootG2.crt.pem  && \
    /opt/java/openjdk/bin/keytool -noprompt -import -trustcacerts -alias azure-cert -file /app/certs/DigiCertGlobalRootG2.crt.pem -keystore /etc/ssl/certs/java/cacerts -keypass changeit -storepass changeit && \
    mkdir -p /plugins && chmod a+rwx /plugins

# add Metabase script and uberjar
COPY --from=builder /home/node/target/uberjar/metabase.jar /app/
COPY bin/docker/run_metabase.sh /app/

# expose our default runtime port
EXPOSE 3000

# run it
ENTRYPOINT ["/app/run_metabase.sh"]
