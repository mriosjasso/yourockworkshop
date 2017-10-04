#!/usr/bin/env bash

#   This script is for blue-green deployment to Cloud Foundry.

#   CF_DOMAIN               default to mybluemix.net
#   CF_ID                   The Cloud Foundry ID to authensticate with.
#   CF_PWD                  The Cloud Foundry password to authenticate with.
#   CF_TARGET               The Bluemix API endpoint; defaults to https://api.ng.bluemix.net
#   CF_TIMEOUT              The Cloud Foundry deploy timeout.  Default to 180 (max).
#   CF_ORG?                 The Cloud Foundry organization to deploy into.
#   CF_SPACE?               The Cloud Foundry space to deploy into.
#   APP_NAME                The application name.
#   APP_PATH                The application path on disk.
#   APP_MANIFEST_PATH       The application manifest file path
#   CF_ENV_PREFIX?          The prefix of exported environment variables for Cloud Foundry application.
#   CF_SERVICE_PREFIX?      The prefix of bind service names for Cloud Foundry application.
#   ADDITIONAL_ROUTES       Space separated list of additional routes to add to the running app

## Limitation

# * the manifest file should not contain services nor environment variables section

REQUIRED=("CF_ID" "CF_PWD" "APP_NAME")
for name in ${REQUIRED[*]}; do
    if [ -z "${!name}" ]; then
        echo "The '${name}' environment variable is required."
        exit 1
    fi
done

APP_DEPLOY_VERSION=$(date +%s)
APP_DEPLOY_NAME="${APP_NAME}-${APP_DEPLOY_VERSION}"
if [ -z "${APP_PATH}" ]; then
    APP_PATH=$(pwd)
fi

# decide the application directory
[ -d $APP_PATH ] && APP_DIR="$APP_PATH" || APP_DIR=$(dirname "$APP_PATH")

CF_DOMAIN="${CF_DOMAIN:-mybluemix.net}"
export APP_URL="https://${APP_DEPLOY_NAME}.${CF_DOMAIN}"

PROD_APP_URL="${APP_NAME}.${CF_DOMAIN}"
APP_ROUTES="${PROD_APP_URL} ${ADDITIONAL_ROUTES}"

install-cf-cli() {
    # install cf CLI
    if [ -z "$(which cf)" ]; then
        curl -sLO http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.9.0/cf-linux-amd64.tgz
        [ -f /usr/bin/sudo ] && sudo tar -xzf cf-linux-amd64.tgz -C /usr/bin
        # TODO handle env without sudo
        rm -rf cf-linux-amd64.tgz
    else
        echo "found cf command, skipping install"
    fi
}

cf-login() {
    echo "Logging into $CF_TARGET"
    cf login -a "${CF_TARGET:-https://api.ng.bluemix.net}" -u $CF_ID -p "$CF_PWD" \
    -o ${CF_ORG:-$CF_ID} -s ${CF_SPACE:-dev}
}

push2cf() {
    pushd ${APP_DIR} > /dev/null

    local APP_VERSION=unknown
    local APP_MANIFEST

    if [ -d "${APP_MANIFEST_PATH}" ]; then
        APP_MANIFEST=${APP_MANIFEST_PATH}/manifest.yml
    elif [ -f "${APP_MANIFEST_PATH}" ]; then
        APP_MANIFEST=${APP_MANIFEST_PATH}
    else
        APP_MANIFEST=${APP_DIR}/manifest.yml
    fi

    GIT_REVISION=$(git rev-parse HEAD)
    if [ $? == 0 ]; then
        echo "Detected git revision ${GIT_REVISION}"
        APP_VERSION="${GIT_REVISION}"
    fi

    local RETURN_CODE=0

    echo "using manifest file: ${APP_MANIFEST}"
    cat  ${APP_MANIFEST}

    # setup services
    if [ -n "${CF_SERVICE_PREFIX}" ]; then
        cat <<EOT >> ${APP_MANIFEST}
  services:
EOT
        for cf_service in $(compgen -e | grep "${CF_SERVICE_PREFIX}"); do
            cat <<EOT >> ${APP_MANIFEST}
    - ${!cf_service}
EOT
        done
    fi

    # setup env variables
    cat <<EOT >> ${APP_MANIFEST}
  env:
    APP_VERSION: ${APP_VERSION}
    NODE_ENV: production
EOT

    if [ -n "${CF_ENV_PREFIX}" ]; then
        for cfg in $(compgen -e | grep ${CF_ENV_PREFIX}); do
            cat <<EOT >> ${APP_MANIFEST}
    ${cfg}: ${!cfg}
    ${cfg#${CF_ENV_PREFIX#^}}: ${!cfg}
EOT
        done
    fi

    # login
    cf-login
    cf push  ${APP_DEPLOY_NAME} -m ${MEMORY_SIZE:-1G} -k ${DISK_SIZE:-1G} -p ${APP_PATH} -f ${APP_MANIFEST} -t ${CF_TIMEOUT:-180} --no-route
    RETURN_CODE=$?

    popd > /dev/null
    if [ "$RETURN_CODE" -ne 0 ]; then
        echo "Could not deploy the application"
    fi
    return ${RETURN_CODE}
}

run-integration-tests() {
    echo "run integration test against ${APP_URL}"
    local RETURN_CODE=0
    pushd ${APP_DIR} > /dev/null

    if [ "$SKIP_NPM_INSTALL" != "true" ]; then
        echo "running npm install"
        npm install
    fi
    npm run-script integration

    RETURN_CODE=$?

    popd > /dev/null

    return ${RETURN_CODE}
}

remove-app() {
    if [ -n "${1}" ]; then
        cf stop "${1}"
        cf delete "${1}" -f -r
    else
        echo "missing application name, failed to remove app."
    fi
}

dump-logs-app() {
    if [ -n "${1}" ]; then
        cf logs "${1}" --recent
    else
        echo "missing application name, failed to get app logs."
    fi
}

getRouteArguments() {
    local HOST=${1}
    local DOMAIN_HOST_ARGS=${HOST}

    # Does the domain end with the CF_DOMAIN?
    if $(echo ${HOST} | grep -qE "$CF_DOMAIN$"); then
        DOMAIN_HOST_ARGS="${CF_DOMAIN} -n ${HOST%.${CF_DOMAIN}}"
    fi

    echo ${DOMAIN_HOST_ARGS}
}

setProdRoutes() {
    local RETURN_CODE=0

    for HOST in ${APP_ROUTES}; do
        # mapping the app to the URL
        cf map-route ${APP_DEPLOY_NAME} $(getRouteArguments ${HOST})
    done

    APP_LISTING=$(cf apps | grep "$APP_DEPLOY_NAME")
    for ROUTE in ${APP_ROUTES}; do
        if [ -z "$(echo ${APP_LISTING} | grep ${ROUTE})" ]
        then
            echo "Missing production route ${ROUTE}"
            RETURN_CODE=1
        fi
    done

    return ${RETURN_CODE}
}

promote2prod() {
    local OUTDATED_APPS=$(cf apps | grep "${PROD_APP_URL}" | awk '{print $1}')

    for OLD_APP in $OUTDATED_APPS; do
        [ "${OLD_APP}" == "${APP_DEPLOY_NAME}" ] && continue

        for HOST in ${APP_ROUTES}; do
            cf unmap-route ${OLD_APP} $(getRouteArguments ${HOST})
        done

        remove-app "${OLD_APP}"
    done
}

# workflow
install-cf-cli
push2cf

RETURN_CODE=$?
if [ "$RETURN_CODE" -eq 0 ]; then
    run-integration-tests
    RETURN_CODE=$?
fi

if [ "$RETURN_CODE" -eq 0 ]; then
    setProdRoutes
    RETURN_CODE=$?
fi

if [ "$RETURN_CODE" -eq 0 ]; then
    promote2prod
else
    dump-logs-app "${APP_DEPLOY_NAME}"
    remove-app "${APP_DEPLOY_NAME}"
fi

cf logout

exit ${RETURN_CODE}
