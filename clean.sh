#!/bin/bash
source config.sh
source common.sh
alert "clean"

### main entry
clean_local_ssh_host_keys
login_az && \
clean
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
logout_az
[[ -f ~/.azure.${CSDM_SUBSCRIPTION} ]] && rm -f ~/.azure.${CSDM_SUBSCRIPTION} &> /dev/null
exit ${RETVAL}
    