#!/bin/bash
kill_ldmsd () {
  ps aux |grep ldmsd | grep -v grep | awk '{print $2}' | xargs kill -9
}

die () {
  echo "ERROR: $@"
  exit -1
}

test_stream_publish () {
  ldmsd_stream_publish -x sock -h localhost -p ${SAMP_PORT} -t string -s amd_gpu_sampler -a munge -f sampler.conf
}

# hello :) 
AGG_PORT=10545
SAMP_PORT=10544
AUTH_TYPE="munge"
XPRT_TYPE="sock"
SAMPLE_INTERVAL=1000000
COMPONENT_ID=90002

command -v ldmsd &>/dev/null || die "Cannot find ldmsd"

cat << SAMPLER > sampler.conf
### This is the configuration file for LDMS's sampler daemon
env SAMPLE_INTERVAL=$SAMPLE_INTERVAL
env COMPONENT_ID=$COMPONENT_ID
  
metric_sets_default_authz perm=0777
  
load name=meminfo
config name=meminfo producer=\${HOSTNAME} instance=\${HOSTNAME}/meminfo component_id=\${COMPONENT_ID} schema=meminfo perm=0777
start name=meminfo interval=\${SAMPLE_INTERVAL}
SAMPLER

cat << AGGREGATOR > aggregator.conf
### This is the configuration file for LDMS's aggregator daemon
auth_add name=$AUTH_TYPE plugin=$AUTH_TYPE
#listen port=$AGG_PORT xprt=$XPRT_TYPE auth=$AUTH_TYPE

# Loading the stream_csv_store plugin
load name=stream_csv_store
config name=stream_csv_store path=/local_data/amd_gpu_sampler_data container=gpu_sampler_data stream=amd_gpu_sampler buffer=0

# Loading the store_csv plugin
load name=store_csv

# Store Group Add
strgp_add name=store_csv plugin=store_csv schema=meminfo container=meminfo

config name=store_csv path=/local_data/amd_gpu_sampler_data

# Store Group Producer Add
strgp_prdcr_add name=store_csv regex=.*

# Store Group Start
strgp_start name=store_csv

# Producer Add
prdcr_add name=localhost type=active interval=$SAMPLE_INTERVAL xprt=$XPRT_TYPE host=localhost port=$SAMP_PORT auth=$AUTH_TYPE

# Producer Subscribe Definition
prdcr_subscribe regex=.* stream=amd_gpu_sampler

# Producer Start
prdcr_start name=localhost

# Updater Add
updtr_add name=update_all interval=$SAMPLE_INTERVAL auto_interval=true

# Updater Producer Add
updtr_prdcr_add name=update_all regex=.*

# Updater Start
updtr_start name=update_all

AGGREGATOR

[ -f sampler.conf ] || die "Cannot locate sampler.conf at $PWD"
# first, let's launch ldmsd samplers daemon as a regular user
ldmsd -x sock:$SAMP_PORT \
      -c sampler.conf \
      -l /tmp/sampler_ldmsd.log \
      -v DEBUG \
      -a ${AUTH_TYPE} \
      -r $(pwd)/ldmsd-sampler.pid \
      -m 2G

sleep 10
if ! ps aux |grep sampler_ldmsd &>/dev/null ; then
  die "Sampler LDMSD didn't start"
else
  ps aux |grep sampler_ldmsd
fi

[ -f aggregator.conf ] || die "Cannot locate aggregator.conf at $PWD"
ldmsd -x sock:$AGG_PORT \
      -c aggregator.conf \
      -l /tmp/aggregator_ldmsd.log \
      -v DEBUG \
      -a ${AUTH_TYPE} \
      -r $(pwd)/ldmsd-aggregator.pid \
      -m 2G

sleep 10

if ! ps aux |grep aggregator_ldmsd &>/dev/null ; then
  die "Aggregator LDMSD didn't start" 
else
  ps aux |grep aggregator_ldmsd
fi
