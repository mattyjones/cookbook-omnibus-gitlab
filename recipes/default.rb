#
# Cookbook Name:: cookbook-omnibus-gitlab
# Recipe:: default
#
# Copyright (C) 2014 YOUR_NAME
#
# All rights reserved - Do Not Redistribute
#

attributes_with_secrets = if node['omnibus-gitlab']['data_bag']
                            OmnibusGitlab.fetch_from_databag(node, "omnibus-gitlab")
                          else
                            chef_gem 'chef-vault'
                            require 'chef-vault'
                            GitLab::AttributesWithSecrets.get(node, "omnibus-gitlab")
                          end

pkg_base_url = node['omnibus-gitlab']['package']['base_url']
pkg_repo = node['omnibus-gitlab']['package']['repo']
package 'curl'

case node['platform_family']
when 'debian'
  execute "add #{pkg_base_url}/#{pkg_repo} apt repo" do
    command "curl #{pkg_base_url}/install/repositories/#{pkg_repo}/script.deb.sh | bash"
    creates "/etc/apt/sources.list.d/#{pkg_repo.sub('/','_')}.list"
  end

  package node['omnibus-gitlab']['package']['name'] do
    version node['omnibus-gitlab']['package']['version']
    options '--force-yes'
    notifies :run, 'execute[gitlab-ctl reconfigure]'
  end
when 'rhel'
  execute "add #{pkg_base_url}/#{pkg_repo} yum repo" do
    command "curl #{pkg_base_url}/install/repositories/#{pkg_repo}/script.rpm.sh | bash"
    creates "/etc/yum.repos.d/#{pkg_repo.sub('/','_')}.repo"
  end

  package node['omnibus-gitlab']['package']['name'] do
    version node['omnibus-gitlab']['package']['version']
    notifies :run, 'execute[gitlab-ctl reconfigure]'
    allow_downgrade true
  end
end

# Create /etc/gitlab and its contents
directory "/etc/gitlab"

# Fetch encrypted secrets and node attributes
gitlab_rb = attributes_with_secrets["gitlab_rb"]

template "/etc/gitlab/gitlab.rb" do
  mode "0600"
  variables(gitlab_rb: gitlab_rb)
  helper(:single_quote) { |value| value.nil? ? nil : "'#{value}'" }
  notifies :run, 'execute[gitlab-ctl reconfigure]'
end

file '/etc/gitlab/skip-auto-migrations' do
  if node['omnibus-gitlab']['skip_auto_migrations']
    action :create
  else
    action :delete
  end
end

directory "/etc/gitlab/ssl" do
  mode "0700"
end

# Fetch encrypted secrets and node attributes
ssl = attributes_with_secrets["ssl"]

file node['omnibus-gitlab']['gitlab_rb']['nginx']['ssl_certificate'] do
  content ssl['certificate']
  not_if { ssl['certificate'].nil? }
  notifies :run, 'bash[reload nginx configuration]'
end

file node['omnibus-gitlab']['gitlab_rb']['nginx']['ssl_certificate_key'] do
  content ssl['private_key']
  not_if { ssl['private_key'].nil? }
  mode "0600"
  notifies :run, 'bash[reload nginx configuration]'
end

file node['omnibus-gitlab']['gitlab_rb']['ci-nginx']['ssl_certificate'] do
  content ssl['ci_certificate']
  not_if { ssl['ci_certificate'].nil? }
  notifies :run, 'bash[reload nginx configuration]'
end

file node['omnibus-gitlab']['gitlab_rb']['ci-nginx']['ssl_certificate_key'] do
  content ssl['ci_private_key']
  not_if { ssl['ci_private_key'].nil? }
  mode "0600"
  notifies :run, 'bash[reload nginx configuration]'
end

file node['omnibus-gitlab']['gitlab_rb']['mattermost-nginx']['ssl_certificate'] do
  content ssl['mattermost_certificate']
  not_if { ssl['mattermost_certificate'].nil? }
  notifies :run, 'bash[reload nginx configuration]'
end

file node['omnibus-gitlab']['gitlab_rb']['mattermost-nginx']['ssl_certificate_key'] do
  content ssl['mattermost_private_key']
  not_if { ssl['mattermost_private_key'].nil? }
  mode "0600"
  notifies :run, 'bash[reload nginx configuration]'
end

# Run gitlab-ctl reconfigure if /etc/gitlab/gitlab.rb changed
execute "gitlab-ctl reconfigure" do
  action :nothing
end

# Reload NGINX if the SSL certificate or key has changed
bash "reload nginx configuration" do
  code <<-EOS
  if gitlab-ctl status nginx ; then
    gitlab-ctl hup nginx
  fi
  EOS
  action :nothing
end
