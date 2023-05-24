#!/bin/bash
RETVAL=0
## nfs.sh to be executed once per AZ subscription
#./nfs.sh

./networks.sh && \
./bastion.sh && \
./hub.sh && \
./spoke.sh && \
./rmd.sh && \
./polt.sh && \
./registry.sh
RETVAL=$?
[[ ${RETVAL} -eq 0 ]] && success "- completed" || error "- fail"
exit ${RETVAL
