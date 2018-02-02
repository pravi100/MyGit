#!/bin/bash
set -euo pipefail

#set aws settings
declare -x PP_INSTANCE_ID=$(curl --silent --show-error --retry 3 http://169.254.169.254/latest/meta-data/instance-id)
# this uses the EC2 instance ID as the node name
declare -x PP_IMAGE_NAME=$(curl --silent --show-error --retry 3 http://169.254.169.254/latest/meta-data/ami-id)
declare -x PP_REGION=$(curl --silent --show-error --retry 3 http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')

# put the opsworks name of your server if you don't use the ocm_server tag
declare -x OCM_SERVER="firstpuppetmaster"
# put the region of your OCM Server if you don't use the ocm_region tag
declare -x OCM_REGION="ap-southeast-1"

# we're detecting if a tag is set, if so, override anything in the file
declare -x TAG_SERVER=$(aws ec2 describe-tags --region $PP_REGION --filters "Name=resource-id,Values=$PP_INSTANCE_ID" \
--query 'Tags[?Key==`ocm_server`].Value' --output text)
declare -x TAG_REGION=$(aws ec2 describe-tags --region $PP_REGION --filters "Name=resource-id,Values=$PP_INSTANCE_ID" \
--query 'Tags[?Key==`ocm_region`].Value' --output text)

if [ -n $TAG_SERVER ] && [ ! -z $TAG_SERVER ]; then
 declare -x OCM_SERVER=$TAG_SERVER
fi

if [ -n $TAG_REGION ] && [ ! -z $TAG_REGION ]; then
 declare -x OCM_REGION=$TAG_REGION
fi

#set global settings
declare -x PUPPETSERVER=$(aws  opsworks-cm describe-servers --region=$OCM_REGION \
--query "Servers[?ServerName=='$OCM_SERVER'].Endpoint" --output text)
declare -x PRUBY='/opt/puppetlabs/puppet/bin/ruby'
declare -x PUPPET='/opt/puppetlabs/bin/puppet'
declare -x DAEMONSPLAY='true'
declare -x SPLAYLIMIT='30'
declare -x PUPPET_CA_PATH='/etc/puppetlabs/puppet/ssl/certs/ca.pem'

function loadmodel {
  aws configure add-model --service-model https://s3.amazonaws.com/opsworks-cm-us-east-1-prod-default-assets/misc/owpe/model-2017-09-05/opsworkscm-2016-11-01.normal.json --service-name opsworks-cm-puppet
}

function preparepuppet {
 mkdir -p /opt/puppetlabs/puppet/cache/state
 mkdir -p /etc/puppetlabs/puppet/ssl/certs/
 mkdir -p /etc/puppetlabs/code/modules/

 echo "{\"disabled_message\":\"Locked by OpsWorks Deploy - $(date --iso-8601=seconds)\"}" > /opt/puppetlabs/puppet/cache/state/agent_disabled.lock
}

function establishtrust {
 aws  opsworks-cm describe-servers --region=$OCM_REGION --server-name $OCM_SERVER \
--query "Servers[0].EngineAttributes[?Name=='PUPPET_API_CA_CERT'].Value" --output text > /etc/puppetlabs/puppet/ssl/certs/ca.pem
}

function installpuppet {
 ADD_EXTENSIONS=$(generate_csr_attributes)
 curl --retry 3 --cacert /etc/puppetlabs/puppet/ssl/certs/ca.pem "https://$PUPPETSERVER:8140/packages/current/install.bash" | \
/bin/bash -s agent:certname=$PP_INSTANCE_ID \
agent:splay=$DAEMONSPLAY \
extension_requests:pp_instance_id=$PP_INSTANCE_ID \
extension_requests:pp_region=$PP_REGION \
extension_requests:pp_image_name=$PP_IMAGE_NAME $ADD_EXTENSIONS

 $PUPPET resource service puppet ensure=stopped
}

function generate_csr_attributes {
 pp_tags=$(aws ec2 describe-tags --region $PP_REGION --filters "Name=resource-id,Values=$PP_INSTANCE_ID" \
--query 'Tags[?starts_with(Key, `pp_`)].[Key,Value]' --output text | sed s/\\t/=/)

 csr_attrs=""
 for i in $pp_tags
 do
   csr_attrs="$csr_attrs extension_requests:$i"
 done

 echo $csr_attrs
}


function installpuppetbootstrap {
 $PUPPET help bootstrap > /dev/null && bootstrap_installed=true || bootstrap_installed=false
 if [ "$bootstrap_installed" = false ]; then
         echo "Puppet Bootstrap not present, installing"
         curl --retry 3 https://s3.amazonaws.com/opsworks-cm-us-east-1-prod-default-assets/misc/owpe/puppet-agent-bootstrap-0.2.1.tar.gz \
         -o /tmp/puppet-agent-bootstrap-0.2.1.tar.gz
         $PUPPET module install /tmp/puppet-agent-bootstrap-0.2.1.tar.gz --ignore-dependencies
         echo "Puppet Bootstrap installed"
 else
         echo "Puppet Bootstrap already present"
 fi
}

function runpuppet {
 sleep $[ ( $RANDOM % $SPLAYLIMIT ) + 1]s
 $PUPPET agent --enable
 $PUPPET agent --onetime --no-daemonize --no-usecacheonfailure --no-splay --verbose
 $PUPPET resource service puppet ensure=running enable=true
}

function associatenode {
 CERTNAME=$($PUPPET config print certname --section agent)
 SSLDIR=$($PUPPET config print ssldir --section agent)
 PP_CSR_PATH="$SSLDIR/certificate_requests/$CERTNAME.pem"
 PP_CERT_PATH="$SSLDIR/certs/$CERTNAME.pem"

 #clear out extranious certs and generate a new one
 $PUPPET bootstrap purge
 $PUPPET bootstrap csr

 # submit the cert
 ASSOCIATE_TOKEN=$(aws opsworks-cm associate-node --region $OCM_REGION --server-name $OCM_SERVER --node-name $CERTNAME --engine-attributes Name=PUPPET_NODE_CSR,Value="`cat $PP_CSR_PATH`" --query "NodeAssociationStatusToken" --output text)

 #wait
 aws opsworks-cm wait node-associated --region $OCM_REGION --node-association-status-token "$ASSOCIATE_TOKEN" --server-name $OCM_SERVER
 #install and verify
 aws opsworks-cm-puppet describe-node-association-status --region $OCM_REGION --node-association-status-token "$ASSOCIATE_TOKEN" --server-name $OCM_SERVER --query 'EngineAttributes[0].Value' --output text > $PP_CERT_PATH

 $PUPPET bootstrap verify

}

# Order of execution of functions
loadmodel
preparepuppet
establishtrust
installpuppet
installpuppetbootstrap
associatenode
runpuppet
