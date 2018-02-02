Introduction
============

This Starter Kit for your _AWS OpsWorks for Puppet Enterprise_ server helps you set up a new development environment for Puppet on your workstation.

To follow this guide, you must have completed the following prerequisites during Puppet server creation:

- Download the Puppet sign-in credentials (Do this before your server is online.)
- Download the Starter Kit (Do this before your server is online.)
- Specified an r10k remote URL (to point to your Git _control-repo_ repository)
- Specified an r10k private key (mandatory if your repository is _not_ public)

**These steps are required. Be sure that you complete all of them.**


Getting started
===============

Before you work with your Puppet Enterprise server, install the following:

- AWS CLI [(Installation instructions)](http://docs.aws.amazon.com/cli/latest/userguide/installing.html)
- Git [(Installation instructions)](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- Puppet Client Tools [(Installation instructions)](https://puppet.com/download-puppet-enterprise-client-tools)

For Linux and macOS users, **ensure you add the Puppet Client Tools to your PATH**. For example, in a Bash shell, run the following: `echo 'export PATH=/opt/puppetlabs/bin:$PATH' >> ~/.bash_profile && source ~/.bash_profile`

The AWS CLI works with the AWS OpsWorks CM API. Use the Puppet Client Tools to work directly with your Puppet server.


Connect to your Puppet server
=============================
To work with your Puppet Enterprise server using Puppet´s Code Manager, add a _control-repo_ to your Git server. This Starter Kit comes with a prepared control-repo that you can push to your r10k remote. It includes an example branch that includes the configuration to set up a NGinX server with a demo website. See below.

## Downloading the Puppet server certificate

To work with your Puppet Enterprise server, download and install its certificate authority (CA) by running the following AWS CLI command:

```
# From your Starter Kit root
aws --region=ap-southeast-1 opsworks-cm describe-servers --server-name firstpuppetmaster \
--query "Servers[0].EngineAttributes[?Name=='PUPPET_API_CA_CERT'].Value" \
--output text >| .config/ssl/cert/ca.pem
```

## Downloading a user access token

The Puppet API also requires a short-term token for your specific user. Generate the token by running the following command:

```
# From your Starter Kit root
puppet-access login --config-file .config/puppetlabs/client-tools/puppet-access.conf --lifetime 8h
```

You are prompted for you user name and password. These are the credentials you downloaded after you launched the Puppet server, or the credentials of a user created in your server's Puppet Enterprise (PE) Console.

After you sign in, you should see a message similar to the following.
```
Access token saved to: .config/puppetlabs/token
```

Uploading the included control repo to your Git repository
==========================================================
The Puppet community recommends a specific structure for your Git repository. You can view the recommended structure in the [PuppetLabs Control Repo](https://github.com/puppetlabs/control-repo) project.

To work with your Puppet Enterprise Master using Puppet Code Manager, add a control-repo to your Git server. This Starter Kit comes with two prepared control repo folders: `control-repo` and `control-repo-example`. The `control-repo` folder includes a `production` branch that is unchanged from what you would see in the Puppet GitHub [repository](https://github.com/puppetlabs/control-repo). The `control-repo-example` folder also has a `production` branch that includes a quickstart example to set up a NGinX server with a demo website.

## Add your Git remote
To follow this guide, push the `control-repo-example` production branch to your Git remote (The r10k_remote URL of your PE Server).

```
# From your Starter Kit root
cd  control-repo-example
git checkout -- .
git remote add origin ssh://git@github.com:pravi100/control-repo.git
git push origin production
```

Puppet's Code Manager uses Git branches as _environments_. By default, all nodes are in the production environment. 
Do _not_ push to a master branch. The `master` branch is reserved for the Puppet server.

## Deploy the code to your Puppet master
```
# From your Starter Kit root
puppet-code deploy --all --wait --config-file .config/puppet-code.conf
```

This lets the Puppet Master download your Puppet code from your Git repository (r10k_remote).

## Connect your first node
To connect your first node to the Puppet Master, use the **userdata.sh** script that is included in this Starter Kit. It uses the AWS OpsWorks AssociateNode API to connect a node to your master. 

To allow your node to connect to your server, you have to create an AWS Identity and Access Management (IAM) role to use as your EC2 instance profile. The following AWS CloudFormation command creates a IAM role with the name _myPuppetinstanceprofile_ for you.

```
aws cloudformation --region ap-southeast-1 create-stack \
--stack-name myPuppetinstanceprofile \
--template-url https://s3.amazonaws.com/opsworks-cm-us-east-1-prod-default-assets/misc/owpe/opsworks-cm-nodes-roles.yaml \
--capabilities CAPABILITY_IAM
```

The easiest way to create a new node is to use the [Amazon EC2 Launch Wizard](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/launching-instance.html). Choose an Amazon Linux AMI. In Step 3: "Configure Instance Details", select _myPuppetinstanceprofile_ as your IAM role. In the "Advanced Details" section, upload the **userdata.sh** script.

You don't have to change anything for Step 4. Proceed to Step 5.

By applying tags to your EC2 instance, you can customize the behavior of the userdata.sh. For this example, apply the role `nginx_webserver` to your node by adding the following tag: `pp_role` with the value `nginx_webserver`.

In Step 6, choose Add Rule, and then choose the type HTTP to open port 80 for the NGinX-Webserver in this example.

Choose Review and then Launch to proceed to the final Step 7. When your new node starts, it applies the NGinX configuration of our example. When you open the webpage linked to the public DNS of your new node, you should see a website that is hosted by your Puppet-managed NGinX webserver.

For more information, see the [AWS OpsWorks for Puppet Enterprise user guide](http://docs.aws.amazon.com/opsworks/latest/userguide/opspup-unattend-assoc.html).



